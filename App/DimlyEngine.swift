// MARK: - Core Engine
// Central hub for hotkeys, blackout control, DDC actions, and profile coordination.
import AppKit
import Combine
import OSLog

/// Source used for a display brightness update.
enum BrightnessControlMode {
    case ddc
    case fallback
    case checking
}

/// Origin of a brightness write request.
enum BrightnessChangeSource: String {
    case api
    case slider
    case mediaKey
    case automaticRestore

    var isUserInitiated: Bool {
        switch self {
        case .slider, .mediaKey:
            return true
        case .api, .automaticRestore:
            return false
        }
    }
}

/// Core, non-UI engine that owns hotkeys and display actions.
@MainActor
final class DimlyEngine: ObservableObject {
    private struct RestoreBrightnessWriteRecord {
        let percent: Int
        let writtenAt: Date
        let reason: String
    }

    private let settingsStore: AppSettingsStore
    private let launcherHotkeyManager: HotkeyManager
    private let panicHotkeyManager: HotkeyManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "Engine")
    private var settingsCancellable: AnyCancellable?
    private var stateCancellables: Set<AnyCancellable> = []
    private var pendingBrightnessByDisplayID: [String: Int] = [:]
    private var brightnessRequestRevisionByDisplayID: [String: Int] = [:]
    private var builtinRestoreBrightnessByDisplayID: [String: Int] = [:]
    private let animationDriver = BrightnessAnimationDriver()
    private var lastObservedDDCSupportByDisplayID: [String: DDCSupportStatus] = [:]
    private var hotkeyManagers: [UUID: HotkeyManager] = [:]
    private let legacySleepPersistenceKey = "Sleep.activeDisplayIDs"
    private let legacyBlackoutPersistenceKey = "Blackout.activeDisplayIDs"
    private let monitorStateRetentionDays = 90
    private let monitorStateRestoreRetryDelayNanoseconds: UInt64 = 400_000_000
    private let displayChangeRestoreDelayNanoseconds: UInt64 = 180_000_000
    private let wakeRestoreDelayNanoseconds: UInt64 = 750_000_000
    private let ddcResolvedRestoreDelayNanoseconds: UInt64 = 120_000_000
    private let postSessionUnlockRestoreDelayNanoseconds: UInt64 = 420_000_000
    private let topologySettleGraceWindowNanoseconds: UInt64 = 1_900_000_000
    private let topologyQuietWindowNanoseconds: UInt64 = 1_100_000_000
    private let wakeSettleMaximumWindowNanoseconds: UInt64 = 8_000_000_000
    private let duplicateAutomaticRestoreSuppressWindow: TimeInterval = 2.4
    private var workspaceWakeToken: NSObjectProtocol?
    private var workspaceScreensWakeToken: NSObjectProtocol?
    private var workspaceSessionDidResignToken: NSObjectProtocol?
    private var workspaceSessionDidBecomeToken: NSObjectProtocol?
    private var distributedScreenLockedToken: NSObjectProtocol?
    private var distributedScreenUnlockedToken: NSObjectProtocol?
    private var monitorRestoreTask: Task<Void, Never>?
    private var monitorRestoreGeneration: UInt64 = 0
    private var topologySettleDeadline: Date?
    private var wakeSettleHardDeadline: Date?
    private var lastDisplayTopologyChangeAt: Date = .distantPast
    private var activeRestoreCycleGeneration: UInt64?
    private var automaticRestoreBrightnessWriteRecordByDisplayID: [String: RestoreBrightnessWriteRecord] = [:]
    private var automaticRestoreSuppressedUntilByDisplayID: [String: Date] = [:]
    private let userOverrideAutomaticRestoreSuppressWindow: TimeInterval = 12
    private var isSessionInteractive = true
    private var deferredRestoreReasonsAfterSessionUnlock: Set<String> = []
    private var lastKnownPrimaryDisplayStableID: String?
    private var didLogWakeStabilizationEnd = false
    private var brightnessMediaKeyGlobalMonitorToken: Any?
    private var brightnessMediaKeyLocalMonitorToken: Any?
    private var builtinBrightnessReconcileTasks: [String: Task<Void, Never>] = [:]
    @Published private(set) var builtinBrightnessLevels: [String: Int] = [:]
    @Published private(set) var preciseBrightnessLevels: [String: Double] = [:]
    let displayManager: DisplayManager
    let blackoutManager: BlackoutManager
    let ddcManager: DDCManager
    let profileManager: ProfileManager
    let scheduleManager: ScheduleManager
    let nightShiftManager: NightShiftManager
    let trueToneManager: TrueToneManager
    let displayModeManager: DisplayModeManager
    let colorProfileManager: ColorProfileManager
    let displayAppearanceManager: DisplayAppearanceManager
    let lutManager: LUTManager
    var onShowWindow: (() -> Void)?
    var onToggleWindow: (() -> Void)?

    /// Builds all managers and binds settings/hotkeys.
    init(settingsStore: AppSettingsStore, displayManager: DisplayManager = DisplayManager()) {
        self.settingsStore = settingsStore
        self.launcherHotkeyManager = HotkeyManager(
            descriptor: HotkeyDescriptor.toggleLauncher
        )
        self.panicHotkeyManager = HotkeyManager(
            descriptor: HotkeyDescriptor.panicDefault
        )
        self.displayManager = displayManager
        self.blackoutManager = BlackoutManager(
            displayManager: displayManager,
            startupRestoreAnimated: settingsStore.settings.fadeOutAnimationEnabled
        )
        self.ddcManager = DDCManager(displayManager: displayManager)
        self.profileManager = ProfileManager(
            displayManager: displayManager,
            blackoutManager: blackoutManager,
            ddcManager: ddcManager,
            settingsStore: settingsStore
        )
        self.scheduleManager = ScheduleManager()
        self.nightShiftManager = NightShiftManager()
        self.trueToneManager = TrueToneManager()
        self.displayModeManager = DisplayModeManager()
        self.colorProfileManager = ColorProfileManager()
        self.displayAppearanceManager = DisplayAppearanceManager()
        self.lutManager = LUTManager()
        DiagnosticsLogger.shared.log("Engine init: managers constructed", category: "engine")
        self.launcherHotkeyManager.onHotkeyPressed = { [weak self] in
            self?.onShowWindow?()
        }
        self.panicHotkeyManager.onHotkeyPressed = { [weak self] in
            self?.panicBlackout(animated: false)
        }

        migrateLegacyMonitorStatePersistenceIfNeeded()
        apply(settings: settingsStore.settings)
        observeMonitorState()

        settingsCancellable = settingsStore.$settings
            .removeDuplicates()
            .sink { [weak self] newSettings in
                DiagnosticsLogger.shared.log("Settings changed: updating hotkeys", category: "engine")
                self?.apply(settings: newSettings)
            }

        profileManager.engine = self
        scheduleManager.profileManager = profileManager
        installBrightnessMediaKeyMonitors()
        refreshBuiltinBrightnessSnapshots(reason: "startup", persistToSettings: false)
        beginTopologySettleGraceWindow(reason: "startup")
        schedulePersistedMonitorStateRestore(reason: "startup", remainingAttempts: 5)

        workspaceWakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.beginTopologySettleGraceWindow(reason: "workspaceDidWake")
                self.refreshBuiltinBrightnessSnapshots(reason: "workspaceDidWake", persistToSettings: false)
                self.schedulePersistedMonitorStateRestore(
                    reason: "workspaceDidWake",
                    remainingAttempts: 5,
                    initialDelayNanoseconds: self.wakeRestoreDelayNanoseconds
                )
            }
        }
        workspaceScreensWakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.beginTopologySettleGraceWindow(reason: "workspaceScreensDidWake")
                self.refreshBuiltinBrightnessSnapshots(reason: "workspaceScreensDidWake", persistToSettings: false)
                self.schedulePersistedMonitorStateRestore(
                    reason: "workspaceScreensDidWake",
                    remainingAttempts: 5,
                    initialDelayNanoseconds: self.wakeRestoreDelayNanoseconds
                )
                self.displayAppearanceManager.restoreAll(for: self.displayManager.displays, lutProvider: self.activeLUTTables(for:))
                self.trueToneManager.refresh(for: self.displayManager.displays)
            }
        }
        workspaceSessionDidResignToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSessionInteractivity(isInteractive: false, source: "workspaceSessionDidResign")
            }
        }
        workspaceSessionDidBecomeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSessionInteractivity(isInteractive: true, source: "workspaceSessionDidBecome")
            }
        }
        let distributedCenter = DistributedNotificationCenter.default()
        distributedScreenLockedToken = distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSessionInteractivity(isInteractive: false, source: "distributedScreenLocked")
            }
        }
        distributedScreenUnlockedToken = distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateSessionInteractivity(isInteractive: true, source: "distributedScreenUnlocked")
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.blackoutManager.replayStartupFadeIfNeeded()
            }
        }
    }

    @MainActor
    deinit {
        animationDriver.cancelAll()
        builtinBrightnessReconcileTasks.values.forEach { $0.cancel() }
        monitorRestoreTask?.cancel()
        if let brightnessMediaKeyGlobalMonitorToken {
            NSEvent.removeMonitor(brightnessMediaKeyGlobalMonitorToken)
        }
        if let brightnessMediaKeyLocalMonitorToken {
            NSEvent.removeMonitor(brightnessMediaKeyLocalMonitorToken)
        }
        if let workspaceWakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceWakeToken)
        }
        if let workspaceScreensWakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceScreensWakeToken)
        }
        if let workspaceSessionDidResignToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceSessionDidResignToken)
        }
        if let workspaceSessionDidBecomeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceSessionDidBecomeToken)
        }
        let distributedCenter = DistributedNotificationCenter.default()
        if let distributedScreenLockedToken {
            distributedCenter.removeObserver(distributedScreenLockedToken)
        }
        if let distributedScreenUnlockedToken {
            distributedCenter.removeObserver(distributedScreenUnlockedToken)
        }
    }

    // MARK: - Public

    /// Invoked when a hotkey binding is pressed.
    func performHotkeyAction(_ action: HotkeyAction, target: HotkeyTarget) {
        switch action {
        case .toggleWindow:
            onToggleWindow?()
        case .toggleBlackout:
            toggleBlackout(target: target)
        case .toggleSleepWake:
            toggleSleepWake(target: target)
        }
    }

    /// Toggles blackout across all external displays.
    func toggleExternalBlackout() {
        DiagnosticsLogger.shared.log("Toggle all external blackout", category: "engine")
        let externals = displayManager.displays.filter { $0.isExternal }
        guard !externals.isEmpty else { return }
        let shouldClear = externals.contains { blackoutManager.activeDisplayIDs.contains($0.stableIdentity) }
        externals.forEach { display in
            applyUserPowerState(shouldClear ? .visible : .blackout, to: display)
        }
    }

    /// Requests standby for every external display.
    func sleepExternalDisplays() {
        DiagnosticsLogger.shared.log("Sleep all external displays", category: "engine")
        let externals = displayManager.displays.filter { $0.isExternal }
        externals.forEach { standby(display: $0) }
    }

    /// Wakes every external display.
    func wakeExternalDisplays() {
        DiagnosticsLogger.shared.log("Wake all external displays", category: "engine")
        let externals = displayManager.displays.filter { $0.isExternal }
        externals.forEach { wake(display: $0) }
    }

    /// Toggles sleep/wake across externals based on current state.
    func toggleExternalSleepWake() {
        let externals = displayManager.displays.filter { $0.isExternal }
        guard !externals.isEmpty else { return }
        let shouldWake = externals.contains { isDisplayAsleep($0) }
        if shouldWake {
            DiagnosticsLogger.shared.log("Hotkey: wake all external displays", category: "engine")
            wakeExternalDisplays()
        } else {
            DiagnosticsLogger.shared.log("Hotkey: sleep all external displays", category: "engine")
            sleepExternalDisplays()
        }
    }

    /// Emergency restore: wake all displays and clear blackout overlays.
    func panicBlackout(animated: Bool) {
        DiagnosticsLogger.shared.log("Panic blackout invoked", category: "engine")
        wakeExternalDisplays()
        blackoutManager.panic(animated: animated)
        let displayIDs = Set(displayManager.displays.map(\.stableIdentity))
        settingsStore.update { settings in
            for id in displayIDs where settings.monitorPowerStateByDisplayID[id] == .blackout {
                settings.monitorPowerStateByDisplayID[id] = .visible
            }
        }
    }

    /// Indicates whether a display is currently in blackout mode.
    func isDisplayBlackoutActive(_ display: DisplayInfo) -> Bool {
        if display.isBuiltin {
            return settingsStore.settings.monitorPowerStateByDisplayID[display.stableIdentity] == .blackout
        }
        return blackoutManager.activeDisplayIDs.contains(display.stableIdentity)
    }

    /// Toggles blackout mode for a specific display.
    func toggleDisplayBlackout(display: DisplayInfo) {
        DiagnosticsLogger.shared.log(
            "User toggle blackout id=\(display.stableIdentity) builtin=\(display.isBuiltin)",
            category: "engine"
        )
        if isDisplayBlackoutActive(display) {
            applyUserPowerState(.visible, to: display)
            DiagnosticsLogger.shared.log("Display blackout OFF for \(display.stableIdentity)", category: "engine")
            return
        }

        applyUserPowerState(.blackout, to: display)
        DiagnosticsLogger.shared.log("Display blackout ON for \(display.stableIdentity)", category: "engine")
    }

    /// Sets brightness for a display, preferring DDC and falling back to dim overlay.
    func setBrightness(_ percent: Int, for display: DisplayInfo) {
        setBrightness(percent, for: display, source: .api)
    }

    /// Sets brightness for a display and annotates the request source.
    func setBrightness(_ percent: Int, for display: DisplayInfo, source: BrightnessChangeSource) {
        setBrightness(percent, for: display, animated: false, source: source)
    }

    /// Applies brightness to multiple displays using one synchronized transition timeline.
    func setBrightnessSynchronously(_ targets: [(display: DisplayInfo, percent: Int)], animated: Bool) {
        guard !targets.isEmpty else { return }
        animationDriver.cancelAll()

        let normalizedTargets: [(display: DisplayInfo, percent: Int)] = targets.map { target in
            (display: target.display, percent: max(0, min(100, target.percent)))
        }

        guard animated else {
            normalizedTargets.forEach { target in
                setBrightness(target.percent, for: target.display, animated: false)
            }
            return
        }

        var startByDisplayID: [String: Int] = [:]
        var maxDelta = 0
        for target in normalizedTargets {
            let display = target.display
            let start: Int
            if display.isBuiltin {
                start = DisplayHardware.builtinDisplayBrightnessPercent(for: display.displayID)
                    ?? settingsStore.settings.monitorBrightnessByDisplayID[display.stableIdentity]
                    ?? target.percent
            } else {
                start = brightnessPercent(for: display)
            }
            startByDisplayID[display.stableIdentity] = start
            maxDelta = max(maxDelta, abs(target.percent - start))
        }
        guard maxDelta > 0 else {
            normalizedTargets.forEach { target in
                setBrightness(target.percent, for: target.display, animated: false)
            }
            return
        }

        let transitionMultiplier = settingsStore.settings.transitionSpeed.multiplier
        guard transitionMultiplier > 0 else {
            normalizedTargets.forEach { target in
                setBrightness(target.percent, for: target.display, animated: false)
            }
            return
        }
        let totalDuration = 0.36 * transitionMultiplier
        let syncScreen = bestAnimationScreen(for: normalizedTargets.map(\.display))
        animationDriver.start(id: "syncTransition", screen: syncScreen, duration: totalDuration) { [weak self] progress in
            guard let self else { return }
            for target in normalizedTargets {
                let display = target.display
                let id = display.stableIdentity
                let start = startByDisplayID[id] ?? target.percent
                let exact = Double(start) + Double(target.percent - start) * progress
                preciseBrightnessLevels[id] = exact
                let value = Int(exact.rounded())
                if display.isBuiltin {
                    setBuiltinBrightness(value, for: display, animated: false)
                } else {
                    applyExternalBrightness(value, for: display, persist: false, fallbackAnimated: false, precise: exact)
                }
            }
        } onComplete: { [weak self] in
            guard let self else { return }
            for target in normalizedTargets {
                let id = target.display.stableIdentity
                preciseBrightnessLevels.removeValue(forKey: id)
                if target.display.isBuiltin {
                    setBuiltinBrightness(target.percent, for: target.display, animated: false)
                    persistBrightness(target.percent, for: id)
                } else {
                    applyExternalBrightness(target.percent, for: target.display, persist: true, fallbackAnimated: false)
                }
            }
        }
    }

    /// Sets brightness for a display with optional smooth animation.
    func setBrightness(_ percent: Int, for display: DisplayInfo, animated: Bool) {
        setBrightness(percent, for: display, animated: animated, source: .api)
    }

    /// Sets brightness for a display with optional smooth animation and source tagging.
    func setBrightness(_ percent: Int, for display: DisplayInfo, animated: Bool, source: BrightnessChangeSource) {
        let clamped = max(0, min(100, percent))
        if source.isUserInitiated {
            DiagnosticsLogger.shared.log(
                "User brightness request source=\(source.rawValue) id=\(display.stableIdentity) target=\(clamped)",
                category: "engine"
            )
        }
        if display.isBuiltin {
            if source.isUserInitiated {
                handleExplicitBuiltinBrightnessIntent(clamped, for: display, source: source)
            }
            persistBrightness(clamped, for: display.stableIdentity)
            setBuiltinBrightness(
                clamped,
                for: display,
                animated: animated,
                reason: "builtinBrightness[\(source.rawValue)]"
            )
            return
        }
        guard display.isExternal else { return }
        animationDriver.cancel(id: display.stableIdentity)
        if animated {
            animateExternalBrightness(to: clamped, for: display)
            return
        }
        applyExternalBrightness(clamped, for: display, persist: true, fallbackAnimated: settingsStore.settings.fadeOutAnimationEnabled)
    }

    /// Applies one external brightness value immediately.
    private func applyExternalBrightness(_ percent: Int, for display: DisplayInfo, persist: Bool, fallbackAnimated: Bool, precise: Double? = nil) {
        let clamped = max(0, min(100, percent))
        guard display.isExternal else { return }
        if persist {
            persistBrightness(clamped, for: display.stableIdentity)
        }
        pendingBrightnessByDisplayID[display.stableIdentity] = clamped
        let revision = (brightnessRequestRevisionByDisplayID[display.stableIdentity] ?? 0) + 1
        brightnessRequestRevisionByDisplayID[display.stableIdentity] = revision
        let settings = settingsStore.settings
        let overlayOnly = settings.overlayOnlyDisplayIDs.contains(display.stableIdentity)
        let ddcStatus = ddcManager.states[display.stableIdentity]?.status
        let canAttemptDDC = !overlayOnly && ddcStatus != .notSupported
        DiagnosticsLogger.shared.log(
            "Brightness write id=\(display.stableIdentity) target=\(clamped) persist=\(persist) overlayOnly=\(overlayOnly) ddcStatus=\(ddcStatus?.rawValue ?? "nil")",
            category: "engine"
        )
        if overlayOnly {
            blackoutManager.setBrightnessFallback(
                precise ?? Double(clamped),
                for: display,
                animated: fallbackAnimated
            )
            DiagnosticsLogger.shared.log(
                "Brightness path=fallback-overlayOnly id=\(display.stableIdentity) target=\(clamped)",
                category: "engine"
            )
            pendingBrightnessByDisplayID.removeValue(forKey: display.stableIdentity)
            return
        }
        if ddcStatus == .unknown || ddcStatus == nil {
            blackoutManager.setBrightnessFallback(
                precise ?? Double(clamped),
                for: display,
                animated: fallbackAnimated
            )
            // Keep pending target so it can be replayed once DDC capability resolves.
            DiagnosticsLogger.shared.log(
                "Brightness path=fallback-ddcUnknown id=\(display.stableIdentity) target=\(clamped)",
                category: "engine"
            )
            return
        }
        if canAttemptDDC {
            ddcManager.setBrightness(clamped, for: display) { [weak self] success in
                guard let self else { return }
                guard self.brightnessRequestRevisionByDisplayID[display.stableIdentity] == revision else { return }
                if success {
                    DiagnosticsLogger.shared.log(
                        "Brightness path=ddc-success id=\(display.stableIdentity) target=\(clamped)",
                        category: "engine"
                    )
                    self.blackoutManager.clearBrightnessFallback(for: display)
                    self.pendingBrightnessByDisplayID.removeValue(forKey: display.stableIdentity)
                    return
                }
                DiagnosticsLogger.shared.log(
                    "Brightness path=ddc-failed-fallback id=\(display.stableIdentity) target=\(clamped)",
                    category: "engine"
                )
                self.blackoutManager.setBrightnessFallback(
                    precise ?? Double(clamped),
                    for: display,
                    animated: fallbackAnimated
                )
                self.pendingBrightnessByDisplayID.removeValue(forKey: display.stableIdentity)
            }
            return
        }
        blackoutManager.setBrightnessFallback(
            precise ?? Double(clamped),
            for: display,
            animated: fallbackAnimated
        )
        DiagnosticsLogger.shared.log(
            "Brightness path=fallback-ddcNotSupported id=\(display.stableIdentity) target=\(clamped)",
            category: "engine"
        )
        pendingBrightnessByDisplayID.removeValue(forKey: display.stableIdentity)
    }

    /// Smoothly ramps external brightness and applies the final target.
    private func animateExternalBrightness(to target: Int, for display: DisplayInfo) {
        let id = display.stableIdentity
        let start = brightnessPercent(for: display)
        guard start != target else {
            applyExternalBrightness(target, for: display, persist: true, fallbackAnimated: true)
            return
        }
        let delta = target - start
        let transitionMultiplier = settingsStore.settings.transitionSpeed.multiplier
        guard transitionMultiplier > 0 else {
            applyExternalBrightness(target, for: display, persist: true, fallbackAnimated: false)
            return
        }
        let totalDuration = 0.36 * transitionMultiplier
        let isFinalAnimated = settingsStore.settings.fadeOutAnimationEnabled
        let displayScreen = animationScreen(for: display)
        animationDriver.start(id: id, screen: displayScreen, duration: totalDuration) { [weak self] progress in
            guard let self else { return }
            let exact = Double(start) + Double(delta) * progress
            self.preciseBrightnessLevels[id] = exact
            self.applyExternalBrightness(Int(exact.rounded()), for: display, persist: false, fallbackAnimated: false, precise: exact)
        } onComplete: { [weak self] in
            guard let self else { return }
            self.preciseBrightnessLevels.removeValue(forKey: id)
            self.applyExternalBrightness(target, for: display, persist: true, fallbackAnimated: isFinalAnimated)
        }
    }

    /// Returns current brightness value used for UI (0-100).
    func brightnessPercent(for display: DisplayInfo) -> Int {
        if display.isBuiltin {
            return builtinBrightnessLevels[display.stableIdentity]
                ?? settingsStore.settings.monitorBrightnessByDisplayID[display.stableIdentity]
                ?? 100
        }
        if let pending = pendingBrightnessByDisplayID[display.stableIdentity] {
            return pending
        }
        if let fallback = blackoutManager.fallbackBrightnessLevels[display.stableIdentity] {
            return fallback
        }
        if let ddcBrightness = ddcManager.brightnessLevels[display.stableIdentity] {
            return ddcBrightness
        }
        return 100
    }

    /// Returns precise (sub-integer) brightness during animation, falling back to integer when idle.
    func preciseBrightnessLevel(for display: DisplayInfo) -> Double {
        preciseBrightnessLevels[display.stableIdentity] ?? Double(brightnessPercent(for: display))
    }

    /// Returns the NSScreen corresponding to a display, used to pick the correct display link.
    private func animationScreen(for display: DisplayInfo) -> NSScreen? {
        NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)
                .map { CGDirectDisplayID($0.uint32Value) == display.displayID } ?? false
        }
    }

    /// Returns the highest-refresh-rate screen among a set of displays, or the main screen.
    private func bestAnimationScreen(for displays: [DisplayInfo]) -> NSScreen? {
        displays.compactMap { animationScreen(for: $0) }
            .max { ($0.maximumFramesPerSecond) < ($1.maximumFramesPerSecond) }
            ?? NSScreen.main
    }

    /// Triggers a one-shot hardware refresh for a built-in display brightness snapshot.
    func refreshBuiltinBrightnessSnapshot(for display: DisplayInfo, persistToSettings: Bool = false) {
        guard display.isBuiltin else { return }
        let id = display.stableIdentity
        let resolvedBrightness = DisplayHardware.builtinDisplayBrightnessPercent(for: display.displayID)
            ?? settingsStore.settings.monitorBrightnessByDisplayID[id]
        guard let resolvedBrightness else { return }
        updateBuiltinBrightnessSnapshot(resolvedBrightness, for: id)
        guard persistToSettings else { return }
        persistBrightness(resolvedBrightness, for: id)
    }

    /// Refreshes built-in brightness snapshots for the current or supplied display inventory.
    func refreshBuiltinBrightnessSnapshots(
        reason: String,
        persistToSettings: Bool = false,
        displays: [DisplayInfo]? = nil
    ) {
        let builtinDisplays = (displays ?? displayManager.displays).filter(\.isBuiltin)
        let liveIDs = Set(builtinDisplays.map(\.stableIdentity))
        if builtinBrightnessLevels.keys.contains(where: { !liveIDs.contains($0) }) {
            builtinBrightnessLevels = builtinBrightnessLevels.filter { liveIDs.contains($0.key) }
        }
        for display in builtinDisplays {
            refreshBuiltinBrightnessSnapshot(for: display, persistToSettings: persistToSettings)
        }
        DiagnosticsLogger.shared.log(
            "Builtin brightness snapshot refresh reason=\(reason) displays=\(builtinDisplays.count) persist=\(persistToSettings)",
            category: "engine"
        )
    }

    /// Returns which brightness path is currently expected for this display.
    func brightnessMode(for display: DisplayInfo) -> BrightnessControlMode {
        guard display.isExternal else { return .fallback }
        if settingsStore.settings.overlayOnlyDisplayIDs.contains(display.stableIdentity) {
            return .fallback
        }
        if blackoutManager.fallbackBrightnessLevels[display.stableIdentity] != nil {
            return .fallback
        }
        if ddcManager.brightnessLevels[display.stableIdentity] != nil {
            return .ddc
        }
        let ddcStatus = ddcManager.states[display.stableIdentity]?.status
        if ddcStatus == .supported {
            return .ddc
        }
        // "Checking DDC" is shown only during startup/topology/wake cable-check windows.
        if ddcManager.cableCheckDisplayIDs.contains(display.stableIdentity) && (ddcStatus == .unknown || ddcStatus == nil) {
            return .checking
        }
        return .fallback
    }

    /// Puts a display into standby via DDC or blackout fallback.
    func standby(display: DisplayInfo) {
        let settings = settingsStore.settings
        automaticRestoreSuppressedUntilByDisplayID.removeValue(forKey: display.stableIdentity)
        if display.isBuiltin {
            applyBuiltinBlackout(display, animated: settings.fadeOutAnimationEnabled, persistState: true)
            DiagnosticsLogger.shared.log("Standby mapped to builtin blackout for \(display.stableIdentity)", category: "engine")
            return
        }

        let overlayOnly = settings.overlayOnlyDisplayIDs.contains(display.stableIdentity)
        let fadeOut = settings.fadeOutAnimationEnabled
        let ddcSupported = ddcManager.states[display.stableIdentity]?.status == .supported

        if overlayOnly || !ddcSupported {
            if !ddcSupported {
                logger.info("DDC standby unsupported; using blackout fallback for \(display.stableIdentity, privacy: .public)")
            }
            blackoutManager.blackout(display, animated: fadeOut)
            persistPowerState(.blackout, for: display.stableIdentity, reason: "standbyFallback")
            DiagnosticsLogger.shared.log("Standby fallback to blackout for \(display.stableIdentity)", category: "engine")
            return
        }

        if blackoutManager.hasPersistentOverlay(for: display) {
            if ddcManager.standby(display) {
                persistPowerState(.standby, for: display.stableIdentity, reason: "standbyDDC")
            } else {
                persistPowerState(.blackout, for: display.stableIdentity, reason: "standbyDDCFallback")
            }
            return
        }

        blackoutManager.showTransitionOverlay(for: display, animated: fadeOut) { [weak self] in
            guard let self else { return }
            if self.ddcManager.standby(display) == false {
                self.logger.info("DDC standby failed; using blackout fallback for \(display.stableIdentity, privacy: .public)")
                self.blackoutManager.promoteTransitionToPersistent(display: display)
                self.persistPowerState(.blackout, for: display.stableIdentity, reason: "standbyTransitionFallback")
                DiagnosticsLogger.shared.log("Standby failed, fallback to blackout for \(display.stableIdentity)", category: "engine")
                return
            }
            self.persistPowerState(.standby, for: display.stableIdentity, reason: "standbyTransitionDDC")
        }
    }

    /// Wakes a display via DDC or removes blackout fallback.
    func wake(display: DisplayInfo) {
        let settings = settingsStore.settings
        if display.isBuiltin {
            noteUserOverride(ofAutomaticRestoreFor: display.stableIdentity, reason: "wakeBuiltin")
            applyBuiltinVisible(display, animated: settings.fadeInAnimationEnabled, persistState: true)
            DiagnosticsLogger.shared.log("Wake mapped to builtin restore for \(display.stableIdentity)", category: "engine")
            return
        }

        let overlayOnly = settings.overlayOnlyDisplayIDs.contains(display.stableIdentity)
        let fadeIn = settings.fadeInAnimationEnabled
        let ddcSupported = ddcManager.states[display.stableIdentity]?.status == .supported
        let wasDDCAsleep = ddcManager.states[display.stableIdentity]?.lastCommand == .standby

        if overlayOnly || !ddcSupported {
            if !ddcSupported {
                logger.info("DDC wake unsupported; clearing blackout fallback for \(display.stableIdentity, privacy: .public)")
            }
            blackoutManager.unblackout(display, animated: fadeIn)
            persistPowerState(.visible, for: display.stableIdentity, reason: "wakeFallback")
            DiagnosticsLogger.shared.log("Wake fallback to unblackout for \(display.stableIdentity)", category: "engine")
            return
        }

        if ddcManager.wake(display) == false {
            logger.info("DDC wake failed; clearing blackout fallback for \(display.stableIdentity, privacy: .public)")
            blackoutManager.unblackout(display, animated: fadeIn)
            persistPowerState(.visible, for: display.stableIdentity, reason: "wakeDDCFallback")
            DiagnosticsLogger.shared.log("Wake failed, fallback to unblackout for \(display.stableIdentity)", category: "engine")
            return
        }

        if blackoutManager.hasPersistentOverlay(for: display) {
            blackoutManager.unblackout(display, animated: fadeIn)
        }

        let delaySeconds: TimeInterval = (fadeIn && wasDDCAsleep) ? 2.0 : 0.0
        blackoutManager.hideTransitionOverlay(for: display, animated: fadeIn, delay: delaySeconds)
        persistPowerState(.visible, for: display.stableIdentity, reason: "wakeDDC")
    }

    // MARK: - Display Control Facades

    /// Sets DDC contrast (0...100) and persists the value.
    func setContrast(_ percent: Int, for display: DisplayInfo) {
        ddcManager.setContrast(percent, for: display) { [weak self] success in
            guard success else { return }
            self?.settingsStore.update { settings in
                settings.monitorContrastByDisplayID[display.stableIdentity] = percent
            }
        }
    }

    /// Sets DDC input source and persists the value.
    func setInputSource(_ source: DDCInputSource, for display: DisplayInfo) {
        ddcManager.setInputSource(source, for: display) { [weak self] success in
            guard success else { return }
            self?.settingsStore.update { settings in
                settings.monitorInputSourceByDisplayID[display.stableIdentity] = source.rawValue
            }
        }
    }

    /// Sets display resolution/refresh rate mode and persists the mode ID.
    func setDisplayMode(_ mode: DisplayMode, for display: DisplayInfo) {
        let succeeded = displayModeManager.setMode(mode, for: display)
        if succeeded {
            settingsStore.update { settings in
                settings.monitorDisplayModeByDisplayID[display.stableIdentity] = mode.id
            }
        }
    }

    /// Sets an ICC color profile and persists the profile path.
    func setColorProfile(_ profile: ColorProfile, for display: DisplayInfo) {
        let succeeded = colorProfileManager.setProfile(profile, for: display)
        if succeeded {
            settingsStore.update { settings in
                settings.monitorColorProfileByDisplayID[display.stableIdentity] = profile.id
            }
            // Re-apply any active gamma LUT filter after the ICC switch.
            displayAppearanceManager.restoreAll(for: displayManager.displays, lutProvider: activeLUTTables(for:))
        }
    }

    /// Applies a display appearance filter (gamma LUT) and persists it.
    func setDisplayFilter(_ filter: DisplayFilter, for display: DisplayInfo) {
        displayAppearanceManager.applyFilter(filter, lutTables: activeLUTTables(for: display), to: display)
        settingsStore.update { settings in
            settings.displayFilterByDisplayID[display.stableIdentity] = filter
        }
    }

    /// Sets or clears the active LUT for a display and immediately composes it with the current filter.
    func setActiveLUT(_ entry: LUTEntry?, for display: DisplayInfo) {
        settingsStore.update { settings in
            if let entry {
                settings.activeLUTByDisplayID[display.stableIdentity] = entry.id
            } else {
                settings.activeLUTByDisplayID.removeValue(forKey: display.stableIdentity)
            }
        }
        let filter = displayAppearanceManager.activeFilter[display.stableIdentity] ?? .standard
        let lut = entry.flatMap { lutManager.gammaTables(for: $0) }
        displayAppearanceManager.applyFilter(filter, lutTables: lut, to: display)
    }

    /// Returns the cached LUT gamma tables for the active LUT on the given display, if any.
    func activeLUTTables(for display: DisplayInfo) -> ([Float], [Float], [Float])? {
        guard let lutID = settingsStore.settings.activeLUTByDisplayID[display.stableIdentity],
              let entry = lutManager.library.first(where: { $0.id == lutID }) else { return nil }
        return lutManager.gammaTables(for: entry)
    }

    /// Applies explicit user intent for a display power state and persists it as the restore source of truth.
    func applyUserPowerState(_ state: PersistedMonitorPowerState, to display: DisplayInfo) {
        let settings = settingsStore.settings
        switch state {
        case .visible:
            wake(display: display)
        case .standby:
            standby(display: display)
        case .blackout:
            automaticRestoreSuppressedUntilByDisplayID.removeValue(forKey: display.stableIdentity)
            if display.isBuiltin {
                applyBuiltinBlackout(display, animated: settings.fadeOutAnimationEnabled, persistState: true)
            } else {
                blackoutManager.blackout(display, animated: settings.fadeOutAnimationEnabled)
                persistPowerState(.blackout, for: display.stableIdentity, reason: "userBlackout")
            }
        }
    }

    /// Removes all stored state for a monitor, as if it was never seen.
    func forgetMonitor(id: String) {
        settingsStore.update { settings in
            settings.monitorBrightnessByDisplayID.removeValue(forKey: id)
            settings.monitorPowerStateByDisplayID.removeValue(forKey: id)
            settings.displayAliases.removeValue(forKey: id)
            settings.overlayOnlyDisplayIDs.removeAll { $0 == id }
            settings.menuBarExcludedDisplayIDs.removeAll { $0 == id }
            settings.menuBarIncludedInternalDisplayIDs.removeAll { $0 == id }
            settings.externalDisplayOrder.removeAll { $0 == id }
            settings.internalDisplayOrder.removeAll { $0 == id }
            settings.mergedDisplayOrder.removeAll { $0 == id }
            settings.brightnessPanelExpandedDisplayIDs.removeAll { $0 == id }
            settings.monitorLastSeenAtByDisplayID.removeValue(forKey: id)
        }
    }

    /// Releases hotkeys and removes overlays before app termination.
    func cleanupBeforeExit() {
        DiagnosticsLogger.shared.log("Cleanup before exit", category: "engine")
        launcherHotkeyManager.deactivate()
        hotkeyManagers.values.forEach { $0.deactivate() }
        blackoutManager.cleanupBeforeExit()
    }

    /// Prepares for termination, fading out active overlays when requested.
    func prepareForExit(animated: Bool, completion: @escaping () -> Void) {
        DiagnosticsLogger.shared.log("Prepare for exit", category: "engine")
        launcherHotkeyManager.deactivate()
        hotkeyManagers.values.forEach { $0.deactivate() }
        blackoutManager.fadeOutAllAndClose(animated: animated, completion: completion)
    }

    // MARK: - Private

    /// Re-applies settings-dependent behaviors (currently hotkeys).
    private func apply(settings: DimlySettings) {
        launcherHotkeyManager.activate()
        updateHotkeys(settings.hotkeyBindings)
        panicHotkeyManager.activate()
        blackoutManager.transitionSpeedMultiplier = settings.transitionSpeed.multiplier
    }

    /// Registers all configured hotkeys and de-duplicates by descriptor.
    private func updateHotkeys(_ bindings: [HotkeyBinding]) {
        hotkeyManagers.values.forEach { $0.deactivate() }
        hotkeyManagers.removeAll()

        var registeredDescriptors = Set<HotkeyDescriptor>()
        for binding in bindings {
            guard let descriptor = binding.descriptor else { continue }
            guard registeredDescriptors.contains(descriptor) == false else {
                DiagnosticsLogger.shared.log("Skipped duplicate hotkey registration", category: "engine")
                continue
            }
            registeredDescriptors.insert(descriptor)
            let manager = HotkeyManager(descriptor: descriptor)
            manager.onHotkeyPressed = { [weak self] in
                self?.performHotkeyAction(binding.action, target: binding.target)
            }
            _ = manager.activate()
            hotkeyManagers[binding.id] = manager
        }
    }

    /// Hotkey routing for blackout actions.
    private func toggleBlackout(target: HotkeyTarget) {
        switch target {
        case .allExternalDisplays:
            logger.notice("Hotkey triggered external blackout toggle")
            DiagnosticsLogger.shared.log("Hotkey toggled external blackout", category: "engine")
            toggleExternalBlackout()
        case .display(let id):
            guard let display = displayManager.displays.first(where: { $0.stableIdentity == id }) else { return }
            toggleDisplayBlackout(display: display)
            DiagnosticsLogger.shared.log("Hotkey toggled blackout for \(id)", category: "engine")
        }
    }

    /// Hotkey routing for sleep/wake actions.
    private func toggleSleepWake(target: HotkeyTarget) {
        switch target {
        case .allExternalDisplays:
            toggleExternalSleepWake()
        case .display(let id):
            guard let display = displayManager.displays.first(where: { $0.stableIdentity == id }) else { return }
            if isDisplayAsleep(display) {
                DiagnosticsLogger.shared.log("Hotkey waking display \(id)", category: "engine")
                wake(display: display)
            } else {
                DiagnosticsLogger.shared.log("Hotkey sleeping display \(id)", category: "engine")
                standby(display: display)
            }
        }
    }

    /// Indicates whether a display is blacked out or in DDC standby.
    private func isDisplayAsleep(_ display: DisplayInfo) -> Bool {
        if isDisplayBlackoutActive(display) {
            return true
        }
        return ddcManager.states[display.stableIdentity]?.lastCommand == .standby
    }

    /// Installs passive listeners for system brightness keys so user intent can supersede blackout state.
    private func installBrightnessMediaKeyMonitors() {
        brightnessMediaKeyGlobalMonitorToken = NSEvent.addGlobalMonitorForEvents(matching: [.systemDefined]) { [weak self] event in
            guard let mediaKey = HotkeyDescriptor.mediaKey(from: event) else { return }
            guard mediaKey == .brightnessUp || mediaKey == .brightnessDown else { return }
            Task { @MainActor [weak self] in
                self?.handleBrightnessMediaKeyCommand(mediaKey)
            }
        }
        brightnessMediaKeyLocalMonitorToken = NSEvent.addLocalMonitorForEvents(matching: [.systemDefined]) { [weak self] event in
            guard let mediaKey = HotkeyDescriptor.mediaKey(from: event) else { return event }
            guard mediaKey == .brightnessUp || mediaKey == .brightnessDown else { return event }
            Task { @MainActor [weak self] in
                self?.handleBrightnessMediaKeyCommand(mediaKey)
            }
            return event
        }
    }

    /// Handles user brightness key presses and clears stale builtin blackout state.
    private func handleBrightnessMediaKeyCommand(_ mediaKey: MediaKey) {
        guard let display = primaryBuiltinDisplay() else { return }
        let id = display.stableIdentity
        DiagnosticsLogger.shared.log(
            "User brightness key=\(mediaKey.displayName) id=\(id)",
            category: "engine"
        )
        let persistedPower = settingsStore.settings.monitorPowerStateByDisplayID[id] ?? .visible
        let hasRuntimeBuiltinBlackoutSnapshot = builtinRestoreBrightnessByDisplayID[id] != nil
        guard persistedPower != .visible || hasRuntimeBuiltinBlackoutSnapshot else {
            scheduleBuiltinBrightnessReconcile(for: display, source: .mediaKey)
            return
        }
        let restoreTarget = builtinRestoreBrightnessByDisplayID[id]
            ?? settingsStore.settings.monitorBrightnessByDisplayID[id]
            ?? 60
        noteUserOverride(ofAutomaticRestoreFor: id, reason: "brightnessKey[\(mediaKey.rawValue)]")
        builtinRestoreBrightnessByDisplayID.removeValue(forKey: id)
        persistPowerState(.visible, for: id, reason: "brightnessKey")
        if let liveBrightness = DisplayHardware.builtinDisplayBrightnessPercent(for: display.displayID), liveBrightness == 0 {
            setBuiltinBrightness(
                max(1, restoreTarget),
                for: display,
                animated: false,
                reason: "brightnessKeyWake"
            )
            persistBrightness(max(1, restoreTarget), for: id)
        }
        DiagnosticsLogger.shared.log(
            "User command override restore/fallback id=\(id) via=mediaKey",
            category: "engine"
        )
        scheduleBuiltinBrightnessReconcile(for: display, source: .mediaKey)
    }

    /// Returns the current primary built-in display, falling back to any built-in panel.
    private func primaryBuiltinDisplay() -> DisplayInfo? {
        let primaryDisplayID = CGMainDisplayID()
        if let primaryBuiltin = displayManager.displays.first(where: { $0.displayID == primaryDisplayID && $0.isBuiltin }) {
            return primaryBuiltin
        }
        return displayManager.displays.first(where: \.isBuiltin)
    }

    /// Schedules a short post-command reconcile to align persisted builtin brightness with the actual panel value.
    private func scheduleBuiltinBrightnessReconcile(for display: DisplayInfo, source: BrightnessChangeSource) {
        let id = display.stableIdentity
        builtinBrightnessReconcileTasks[id]?.cancel()
        builtinBrightnessReconcileTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard let self else { return }
            let previousBrightness = self.settingsStore.settings.monitorBrightnessByDisplayID[id]
            self.refreshBuiltinBrightnessSnapshot(for: display, persistToSettings: true)
            let liveBrightness = self.builtinBrightnessLevels[id]
                ?? self.settingsStore.settings.monitorBrightnessByDisplayID[id]
                ?? 100
            guard previousBrightness != liveBrightness else { return }
            DiagnosticsLogger.shared.log(
                "Reconciled builtin brightness id=\(id) source=\(source.rawValue) value=\(liveBrightness)",
                category: "engine"
            )
        }
    }

    /// Records that user intent should temporarily suppress automatic restore writes for a display.
    private func noteUserOverride(ofAutomaticRestoreFor id: String, reason: String) {
        let until = Date().addingTimeInterval(userOverrideAutomaticRestoreSuppressWindow)
        automaticRestoreSuppressedUntilByDisplayID[id] = until
        automaticRestoreBrightnessWriteRecordByDisplayID.removeValue(forKey: id)
        DiagnosticsLogger.shared.log(
            "User override id=\(id) reason=\(reason) suppressAutoRestoreFor=\(String(format: "%.1f", until.timeIntervalSinceNow))s",
            category: "engine"
        )
    }

    /// Returns whether automatic restore should be suppressed due to a recent user command.
    private func shouldSuppressAutomaticRestore(for id: String, reason: String) -> Bool {
        guard let until = automaticRestoreSuppressedUntilByDisplayID[id] else { return false }
        if Date() >= until {
            automaticRestoreSuppressedUntilByDisplayID.removeValue(forKey: id)
            return false
        }
        DiagnosticsLogger.shared.log(
            "Suppress automatic restore id=\(id) reason=userOverride passReason=\(reason)",
            category: "engine"
        )
        return true
    }

    /// Clears builtin blackout state when a user directly requests brightness.
    private func handleExplicitBuiltinBrightnessIntent(_ clamped: Int, for display: DisplayInfo, source: BrightnessChangeSource) {
        let id = display.stableIdentity
        guard clamped > 0 else {
            DiagnosticsLogger.shared.log(
                "Suppress builtin blackout override id=\(id) reason=nonPositiveBrightness target=\(clamped)",
                category: "engine"
            )
            return
        }
        let persistedPower = settingsStore.settings.monitorPowerStateByDisplayID[id] ?? .visible
        let hadRuntimeBuiltinBlackoutSnapshot = builtinRestoreBrightnessByDisplayID[id] != nil
        noteUserOverride(ofAutomaticRestoreFor: id, reason: "userBrightness[\(source.rawValue)]")
        guard persistedPower != .visible || hadRuntimeBuiltinBlackoutSnapshot else { return }
        builtinRestoreBrightnessByDisplayID.removeValue(forKey: id)
        persistPowerState(.visible, for: id, reason: "userBrightness[\(source.rawValue)]")
        DiagnosticsLogger.shared.log(
            "User command override restore/fallback id=\(id) via=brightness[\(source.rawValue)]",
            category: "engine"
        )
    }

    /// Subscribes to display/overlay changes to keep persisted monitor state in sync.
    private func observeMonitorState() {
        displayManager.$displays
            .removeDuplicates()
            .sink { [weak self] displays in
                guard let self else { return }
                self.refreshBuiltinBrightnessSnapshots(
                    reason: "displayChange",
                    persistToSettings: false,
                    displays: displays
                )
                self.recordDisplayTopologyChange(displays: displays)
                self.trackMonitorLastSeenAndPruneStaleState(displays)
                self.schedulePersistedMonitorStateRestore(
                    reason: "displayChange",
                    remainingAttempts: 5,
                    initialDelayNanoseconds: self.effectiveDisplayChangeRestoreDelayNanoseconds()
                )
                for display in displays {
                    self.displayModeManager.loadModes(for: display)
                    self.colorProfileManager.loadProfiles(for: display)
                }
                self.trueToneManager.refresh(for: displays)
                self.displayAppearanceManager.restoreAll(for: displays, lutProvider: self.activeLUTTables(for:))
            }
            .store(in: &stateCancellables)

        ddcManager.$states
            .sink { [weak self] states in
                self?.handleDDCStateChanges(states)
            }
            .store(in: &stateCancellables)
    }

    /// Tracks lock/unlock session state and defers wake restore until interaction resumes.
    private func updateSessionInteractivity(isInteractive: Bool, source: String) {
        let changed = self.isSessionInteractive != isInteractive
        self.isSessionInteractive = isInteractive
        DiagnosticsLogger.shared.log(
            "Session interactivity source=\(source) interactive=\(isInteractive) changed=\(changed)",
            category: "engine"
        )
        if !isInteractive {
            monitorRestoreTask?.cancel()
            monitorRestoreTask = nil
            activeRestoreCycleGeneration = nil
            deferredRestoreReasonsAfterSessionUnlock.insert("resumeAfterUnlock")
            return
        }
        refreshBuiltinBrightnessSnapshots(reason: source, persistToSettings: false)
        flushDeferredRestoreAfterSessionUnlock(triggerSource: source)
    }

    /// Runs a deferred wake/display restore pass after screen unlock/session resume.
    private func flushDeferredRestoreAfterSessionUnlock(triggerSource: String) {
        guard isSessionInteractive else { return }
        guard !deferredRestoreReasonsAfterSessionUnlock.isEmpty else { return }
        let mergedReasons = deferredRestoreReasonsAfterSessionUnlock.sorted().joined(separator: ",")
        deferredRestoreReasonsAfterSessionUnlock.removeAll()
        DiagnosticsLogger.shared.log(
            "Flush deferred restore after unlock trigger=\(triggerSource) reasons=\(mergedReasons)",
            category: "engine"
        )
        beginTopologySettleGraceWindow(reason: "sessionUnlock")
        schedulePersistedMonitorStateRestore(
            reason: "sessionUnlocked[\(mergedReasons)]",
            remainingAttempts: 6,
            initialDelayNanoseconds: postSessionUnlockRestoreDelayNanoseconds
        )
    }

    /// Starts a short grace window to let wake/startup display topology settle.
    private func beginTopologySettleGraceWindow(reason: String) {
        let now = Date()
        let minSettleSeconds = Double(topologySettleGraceWindowNanoseconds) / 1_000_000_000
        let maxSettleSeconds = Double(wakeSettleMaximumWindowNanoseconds) / 1_000_000_000
        topologySettleDeadline = now.addingTimeInterval(minSettleSeconds)
        wakeSettleHardDeadline = now.addingTimeInterval(maxSettleSeconds)
        lastDisplayTopologyChangeAt = now
        automaticRestoreBrightnessWriteRecordByDisplayID.removeAll()
        didLogWakeStabilizationEnd = false
        DiagnosticsLogger.shared.log(
            "Begin topology settle reason=\(reason) min=\(String(format: "%.2f", minSettleSeconds))s max=\(String(format: "%.2f", maxSettleSeconds))s",
            category: "engine"
        )
        DiagnosticsLogger.shared.log("Wake lifecycle start reason=\(reason)", category: "wake")
    }

    /// Tracks display inventory transitions and extends settle while wake topology is still churning.
    private func recordDisplayTopologyChange(displays: [DisplayInfo]) {
        let now = Date()
        lastDisplayTopologyChangeAt = now
        let liveIDs = Set(displays.map(\.stableIdentity))
        automaticRestoreBrightnessWriteRecordByDisplayID.keys
            .filter { !liveIDs.contains($0) }
            .forEach { automaticRestoreBrightnessWriteRecordByDisplayID.removeValue(forKey: $0) }
        automaticRestoreSuppressedUntilByDisplayID.keys
            .filter { !liveIDs.contains($0) }
            .forEach { automaticRestoreSuppressedUntilByDisplayID.removeValue(forKey: $0) }

        let primaryDisplayID = CGMainDisplayID()
        let primaryStableID = displays.first(where: { $0.displayID == primaryDisplayID })?.stableIdentity
        if primaryStableID != lastKnownPrimaryDisplayStableID {
            DiagnosticsLogger.shared.log(
                "Primary display changed previous=\(lastKnownPrimaryDisplayStableID ?? "nil") current=\(primaryStableID ?? "nil")",
                category: "wake"
            )
            lastKnownPrimaryDisplayStableID = primaryStableID
        }

        guard let hardDeadline = wakeSettleHardDeadline, now < hardDeadline else { return }
        let quietWindowSeconds = Double(topologyQuietWindowNanoseconds) / 1_000_000_000
        let quietDeadline = now.addingTimeInterval(quietWindowSeconds)
        let bounded = min(quietDeadline, hardDeadline)
        if let current = topologySettleDeadline {
            topologySettleDeadline = max(current, bounded)
        } else {
            topologySettleDeadline = bounded
        }
    }

    /// Returns whether startup/wake topology settling is still in progress.
    private func isInTopologySettleGraceWindow() -> Bool {
        let now = Date()
        if let hardDeadline = wakeSettleHardDeadline, now >= hardDeadline {
            return false
        }
        guard let topologySettleDeadline else { return false }
        return now < topologySettleDeadline
    }

    /// Returns whether the maximum wake stabilization window has already elapsed.
    private func hasWakeSettleHardDeadlineElapsed() -> Bool {
        guard let wakeSettleHardDeadline else { return false }
        return Date() >= wakeSettleHardDeadline
    }

    /// Returns whether post-wake restore decisions should still be deferred.
    private func isAutomaticRestoreStabilizationInProgress(settings: DimlySettings, displays: [DisplayInfo]) -> Bool {
        if hasWakeSettleHardDeadlineElapsed() {
            return false
        }
        if isInTopologySettleGraceWindow() {
            return true
        }
        // Keep waiting while external DDC capability is unresolved for displays expected to be visible.
        return displays.contains { display in
            guard display.isExternal else { return false }
            let id = display.stableIdentity
            if settings.overlayOnlyDisplayIDs.contains(id) {
                return false
            }
            let persistedPower = settings.monitorPowerStateByDisplayID[id] ?? .visible
            guard persistedPower == .visible else { return false }
            let status = ddcManager.states[id]?.status
            return status == .unknown || status == nil
        }
    }

    /// Returns how many attempts are required to keep a restore cycle alive until wake stabilization expires.
    private func restoreAttemptsNeededToCoverWakeStabilization(
        initialDelayNanoseconds: UInt64,
        retryDelayNanoseconds: UInt64
    ) -> Int {
        guard let wakeSettleHardDeadline else { return 0 }
        let retryDelaySeconds = Double(retryDelayNanoseconds) / 1_000_000_000
        guard retryDelaySeconds > 0 else { return 0 }
        let initialDelaySeconds = Double(initialDelayNanoseconds) / 1_000_000_000
        let remainingSeconds = wakeSettleHardDeadline.timeIntervalSinceNow - initialDelaySeconds
        guard remainingSeconds > 0 else { return 1 }
        return Int(ceil(remainingSeconds / retryDelaySeconds)) + 1
    }

    /// Emits a one-shot wake stabilization completion marker.
    private func recordWakeStabilizationProgressIfNeeded(settleInProgress: Bool, reason: String) {
        guard !settleInProgress else {
            didLogWakeStabilizationEnd = false
            return
        }
        guard !didLogWakeStabilizationEnd else { return }
        didLogWakeStabilizationEnd = true
        DiagnosticsLogger.shared.log("Wake stabilization end reason=\(reason)", category: "wake")
    }

    /// Extends display-change restore delay while topology is still settling.
    private func effectiveDisplayChangeRestoreDelayNanoseconds() -> UInt64 {
        guard let topologySettleDeadline else { return displayChangeRestoreDelayNanoseconds }
        if let hardDeadline = wakeSettleHardDeadline, Date() >= hardDeadline {
            return displayChangeRestoreDelayNanoseconds
        }
        let remainingSeconds = topologySettleDeadline.timeIntervalSinceNow
        guard remainingSeconds > 0 else { return displayChangeRestoreDelayNanoseconds }
        let remainingNanoseconds = UInt64(remainingSeconds * 1_000_000_000)
        return max(displayChangeRestoreDelayNanoseconds, remainingNanoseconds)
    }

    /// Coalesces persisted-state restores to avoid repeated wake-time brightness thrashing.
    private func schedulePersistedMonitorStateRestore(
        reason: String,
        remainingAttempts: Int,
        initialDelayNanoseconds: UInt64 = 0
    ) {
        if !isSessionInteractive {
            deferredRestoreReasonsAfterSessionUnlock.insert(reason)
            DiagnosticsLogger.shared.log(
                "Defer restore while session inactive reason=\(reason)",
                category: "engine"
            )
            return
        }
        if monitorRestoreTask != nil {
            DiagnosticsLogger.shared.log(
                "Restore cycle superseded reason=\(reason) previousGeneration=\(activeRestoreCycleGeneration ?? 0)",
                category: "engine"
            )
        }
        monitorRestoreTask?.cancel()
        monitorRestoreGeneration &+= 1
        let generation = monitorRestoreGeneration
        activeRestoreCycleGeneration = generation
        let retryDelay = monitorStateRestoreRetryDelayNanoseconds
        let attempts = max(
            max(1, remainingAttempts),
            restoreAttemptsNeededToCoverWakeStabilization(
                initialDelayNanoseconds: initialDelayNanoseconds,
                retryDelayNanoseconds: retryDelay
            )
        )
        DiagnosticsLogger.shared.log(
            "Schedule restore cycle generation=\(generation) reason=\(reason) attempts=\(attempts) requestedAttempts=\(remainingAttempts) initialDelayMs=\(initialDelayNanoseconds / 1_000_000)",
            category: "engine"
        )
        DiagnosticsLogger.shared.log(
            "Restore cycle begin generation=\(generation) reason=\(reason)",
            category: "engine"
        )
        monitorRestoreTask = Task { @MainActor [weak self] in
            guard let self else { return }
            guard self.monitorRestoreGeneration == generation else { return }
            if initialDelayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: initialDelayNanoseconds)
                if Task.isCancelled || self.monitorRestoreGeneration != generation {
                    DiagnosticsLogger.shared.log(
                        "Restore cycle end generation=\(generation) reason=\(reason) status=cancelled-before-attempt",
                        category: "engine"
                    )
                    return
                }
            }
            var restrictedIDs: Set<String>? = nil
            var lastPending: Set<String> = []
            for attempt in 0..<attempts {
                if Task.isCancelled || self.monitorRestoreGeneration != generation {
                    DiagnosticsLogger.shared.log(
                        "Restore cycle end generation=\(generation) reason=\(reason) status=cancelled-attempt-\(attempt + 1)",
                        category: "engine"
                    )
                    return
                }
                let attemptReason = attempt == 0 ? reason : "\(reason)-retry-\(attempt)"
                let pending = self.restorePersistedMonitorStatePass(
                    reason: attemptReason,
                    restrictedToDisplayIDs: restrictedIDs
                )
                lastPending = pending
                DiagnosticsLogger.shared.log(
                    "Restore cycle generation=\(generation) attempt=\(attempt + 1)/\(attempts) pending=\(pending.count) reason=\(attemptReason)",
                    category: "engine"
                )
                guard !pending.isEmpty else {
                    if self.monitorRestoreGeneration == generation {
                        self.monitorRestoreTask = nil
                        self.activeRestoreCycleGeneration = nil
                    }
                    DiagnosticsLogger.shared.log(
                        "Restore cycle end generation=\(generation) reason=\(reason) status=completed",
                        category: "engine"
                    )
                    return
                }
                restrictedIDs = pending
                guard attempt < (attempts - 1) else { break }
                try? await Task.sleep(nanoseconds: retryDelay)
            }
            if !Task.isCancelled, self.monitorRestoreGeneration == generation {
                self.monitorRestoreTask = nil
                self.activeRestoreCycleGeneration = nil
            }
            DiagnosticsLogger.shared.log(
                "Restore cycle end generation=\(generation) reason=\(reason) status=exhausted pending=\(lastPending.count)",
                category: "engine"
            )
        }
    }

    /// Applies one persisted-state restore pass and returns any displays that still need retry.
    private func restorePersistedMonitorStatePass(reason: String, restrictedToDisplayIDs: Set<String>? = nil) -> Set<String> {
        let settings = settingsStore.settings
        let displays = displayManager.displays
        let primaryDisplayID = CGMainDisplayID()
        let primaryDisplay = displays.first { $0.displayID == primaryDisplayID }
        let settleInProgress = isAutomaticRestoreStabilizationInProgress(settings: settings, displays: displays)
        recordWakeStabilizationProgressIfNeeded(settleInProgress: settleInProgress, reason: reason)
        let shouldForcePrimaryVisible = !settleInProgress && shouldForcePrimaryVisibleAfterSettle(
            settings: settings,
            primaryDisplay: primaryDisplay
        )
        var pendingIDs: Set<String> = []

        let internals = displays.filter(\.isBuiltin)
        for display in internals {
            let id = display.stableIdentity
            if let restrictedToDisplayIDs, !restrictedToDisplayIDs.contains(id) {
                continue
            }
            if shouldSuppressAutomaticRestore(for: id, reason: reason) {
                continue
            }
            let power = settings.monitorPowerStateByDisplayID[id] ?? .visible
            let runtimeBuiltinBlackoutActive = builtinRestoreBrightnessByDisplayID[id] != nil
            let isPrimary = display.displayID == primaryDisplayID

            if isPrimary && shouldForcePrimaryVisible {
                DiagnosticsLogger.shared.log(
                    "Restore reason=\(reason) primarySafetyVisible id=\(id) kind=builtin",
                    category: "engine"
                )
                applyBuiltinVisible(display, animated: false, persistState: false)
                continue
            }

            if power == .blackout || power == .standby {
                if isPrimary && settleInProgress {
                    pendingIDs.insert(id)
                    continue
                }
                if runtimeBuiltinBlackoutActive {
                    // Keep the panel dark without overwriting the saved pre-blackout brightness snapshot.
                    setBuiltinBrightness(0, for: display, animated: false, reason: "restoreKeepBuiltinDark[\(reason)]")
                    continue
                }
                applyBuiltinBlackout(display, animated: false, persistState: false)
                continue
            }

            applyBuiltinVisible(display, animated: false, persistState: false)
        }

        let externals = displays.filter(\.isExternal)

        if let restrictedToDisplayIDs {
            DiagnosticsLogger.shared.log(
                "Restore persisted monitor state cycle=\(activeRestoreCycleGeneration ?? 0) reason=\(reason) displays=\(externals.count) scope=pending(\(restrictedToDisplayIDs.count)) settle=\(settleInProgress)",
                category: "engine"
            )
        } else {
            DiagnosticsLogger.shared.log(
                "Restore persisted monitor state cycle=\(activeRestoreCycleGeneration ?? 0) reason=\(reason) displays=\(externals.count) scope=all settle=\(settleInProgress)",
                category: "engine"
            )
        }
        for display in externals {
            let id = display.stableIdentity
            if let restrictedToDisplayIDs, !restrictedToDisplayIDs.contains(id) {
                continue
            }
            if shouldSuppressAutomaticRestore(for: id, reason: reason) {
                continue
            }
            let power = settings.monitorPowerStateByDisplayID[id] ?? .visible
            let isPrimary = display.displayID == primaryDisplayID
            let runtimeBlackoutActive = blackoutManager.activeDisplayIDs.contains(id)
            let runtimeStandbyActive = ddcManager.states[id]?.lastCommand == .standby

            if isPrimary && shouldForcePrimaryVisible {
                DiagnosticsLogger.shared.log(
                    "Restore reason=\(reason) primarySafetyVisible id=\(id) kind=external",
                    category: "engine"
                )
                if power == .standby || runtimeStandbyActive {
                    wake(display: display)
                } else if runtimeBlackoutActive {
                    blackoutManager.unblackout(display, animated: settings.fadeInAnimationEnabled)
                }
                if blackoutManager.fallbackBrightnessLevels[id] != nil {
                    blackoutManager.clearBrightnessFallback(for: display, animated: false)
                }
                continue
            }

            if power == .visible {
                if runtimeBlackoutActive {
                    blackoutManager.unblackout(display, animated: settings.fadeInAnimationEnabled)
                }
                if runtimeStandbyActive {
                    wake(display: display)
                }

                if let brightness = settings.monitorBrightnessByDisplayID[id] {
                    if settleInProgress {
                        pendingIDs.insert(id)
                    } else if shouldApplyPersistedBrightnessOnAutomaticRestore(for: display, settings: settings) {
                        applyAutomaticRestoreBrightnessIfNeeded(
                            brightness,
                            for: display,
                            reason: reason
                        )
                    } else if blackoutManager.fallbackBrightnessLevels[id] != nil {
                        blackoutManager.clearBrightnessFallback(for: display, animated: false)
                    }
                } else if !settleInProgress && blackoutManager.fallbackBrightnessLevels[id] != nil {
                    blackoutManager.clearBrightnessFallback(for: display, animated: false)
                }
                continue
            }

            if power == .blackout {
                if blackoutManager.fallbackBrightnessLevels[id] != nil {
                    blackoutManager.clearBrightnessFallback(for: display, animated: false)
                }
                if settleInProgress {
                    pendingIDs.insert(id)
                    continue
                }
                if runtimeBlackoutActive == false {
                    blackoutManager.blackout(display, animated: false)
                }
                continue
            }

            if blackoutManager.fallbackBrightnessLevels[id] != nil {
                blackoutManager.clearBrightnessFallback(for: display, animated: false)
            }
            if settleInProgress {
                pendingIDs.insert(id)
                continue
            }
            if runtimeStandbyActive == false {
                standby(display: display)
            }
        }
        return pendingIDs
    }

    /// Forces the primary display visible only when no secondary display appears usable.
    private func shouldForcePrimaryVisibleAfterSettle(settings: DimlySettings, primaryDisplay: DisplayInfo?) -> Bool {
        guard isSessionInteractive else {
            DiagnosticsLogger.shared.log("Primary safety decision skipped: session inactive", category: "engine")
            return false
        }
        guard let primaryDisplay else { return false }
        let primaryID = primaryDisplay.stableIdentity
        let primaryPower = settings.monitorPowerStateByDisplayID[primaryID] ?? .visible
        let primaryRuntimeBlackoutActive = blackoutManager.activeDisplayIDs.contains(primaryID)
        let primaryRuntimeBuiltinBlackoutActive = builtinRestoreBrightnessByDisplayID[primaryID] != nil
        let primaryIsDark: Bool
        if primaryDisplay.isBuiltin {
            primaryIsDark = primaryPower == .blackout || primaryRuntimeBuiltinBlackoutActive
        } else {
            primaryIsDark = primaryPower != .visible || primaryRuntimeBlackoutActive
        }
        guard primaryIsDark else { return false }

        let hasVisibleSecondary = displayManager.displays.contains { candidate in
            guard candidate.displayID != primaryDisplay.displayID else { return false }
            return isDisplayLikelyVisibleAsSecondary(candidate, settings: settings)
        }
        DiagnosticsLogger.shared.log(
            "Primary safety decision primary=\(primaryID) dark=\(primaryIsDark) hasVisibleSecondary=\(hasVisibleSecondary)",
            category: "engine"
        )
        return !hasVisibleSecondary
    }

    /// Visibility heuristic used by the primary-display safety override when runtime state is incomplete.
    private func isDisplayLikelyVisibleAsSecondary(_ display: DisplayInfo, settings: DimlySettings) -> Bool {
        let id = display.stableIdentity
        let persistedPower = settings.monitorPowerStateByDisplayID[id] ?? .visible
        if display.isBuiltin {
            let runtimeBuiltinBlackoutActive = builtinRestoreBrightnessByDisplayID[id] != nil
            return persistedPower == .visible && !runtimeBuiltinBlackoutActive
        }
        if blackoutManager.activeDisplayIDs.contains(id) {
            return false
        }
        if ddcManager.states[id]?.lastCommand == .standby {
            return false
        }
        if persistedPower == .visible {
            return true
        }
        // If an external display is physically present and runtime signals do not indicate
        // blackout/standby, treat it as potentially usable and avoid forcing the primary.
        return true
    }

    /// Decides whether automatic startup/wake restore should actively push brightness for this display.
    private func shouldApplyPersistedBrightnessOnAutomaticRestore(for display: DisplayInfo, settings: DimlySettings) -> Bool {
        let id = display.stableIdentity
        if settings.overlayOnlyDisplayIDs.contains(id) {
            return true
        }
        let ddcStatus = ddcManager.states[id]?.status
        if ddcStatus == .supported || ddcStatus == .notSupported {
            return true
        }
        // Once the wake settle deadline expires, prefer restoring intent via fallback instead
        // of indefinitely waiting for DDC capability to resolve again.
        return hasWakeSettleHardDeadlineElapsed()
    }

    /// Applies restore brightness only when it actually changes intent, suppressing duplicate writes.
    private func applyAutomaticRestoreBrightnessIfNeeded(_ percent: Int, for display: DisplayInfo, reason: String) {
        let id = display.stableIdentity
        let clamped = max(0, min(100, percent))
        if shouldSuppressAutomaticRestore(for: id, reason: reason) {
            DiagnosticsLogger.shared.log(
                "Suppress brightness write id=\(id) target=\(clamped) reason=userOverride restoreReason=\(reason)",
                category: "engine"
            )
            return
        }
        let now = Date()
        if let record = automaticRestoreBrightnessWriteRecordByDisplayID[id],
           record.percent == clamped,
           now.timeIntervalSince(record.writtenAt) < duplicateAutomaticRestoreSuppressWindow {
            DiagnosticsLogger.shared.log(
                "Skip duplicate restore brightness id=\(id) percent=\(clamped) reason=\(reason) previousReason=\(record.reason)",
                category: "engine"
            )
            return
        }
        let current = brightnessPercent(for: display)
        if abs(current - clamped) <= 1 {
            DiagnosticsLogger.shared.log(
                "Skip noop restore brightness id=\(id) current=\(current) target=\(clamped) reason=\(reason)",
                category: "engine"
            )
            automaticRestoreBrightnessWriteRecordByDisplayID[id] = RestoreBrightnessWriteRecord(
                percent: clamped,
                writtenAt: now,
                reason: reason
            )
            return
        }
        DiagnosticsLogger.shared.log(
            "Apply restore brightness id=\(id) current=\(current) target=\(clamped) reason=\(reason)",
            category: "engine"
        )
        automaticRestoreBrightnessWriteRecordByDisplayID[id] = RestoreBrightnessWriteRecord(
            percent: clamped,
            writtenAt: now,
            reason: reason
        )
        setBrightness(clamped, for: display, source: .automaticRestore)
    }

    /// Tracks monitor presence and prunes stale monitor-specific state after a retention window.
    private func trackMonitorLastSeenAndPruneStaleState(_ displays: [DisplayInfo]) {
        let liveIDs = Set(displays.map(\.stableIdentity))
        let now = Date()
        let cutoff = now.addingTimeInterval(-TimeInterval(monitorStateRetentionDays * 24 * 60 * 60))

        settingsStore.update { settings in
            for id in liveIDs {
                settings.monitorLastSeenAtByDisplayID[id] = now
            }
        }

        let staleIDs = settingsStore.settings.monitorLastSeenAtByDisplayID.compactMap { id, seenAt -> String? in
            guard liveIDs.contains(id) == false else { return nil }
            return seenAt < cutoff ? id : nil
        }
        for id in staleIDs {
            forgetMonitor(id: id)
        }
    }

    /// Re-runs persisted-state restore once DDC capability resolves past "unknown".
    private func handleDDCStateChanges(_ states: [String: DDCState]) {
        let currentSupport = states.mapValues(\.status)
        let allIDs = Set(lastObservedDDCSupportByDisplayID.keys).union(currentSupport.keys)
        var resolvedIDs: [String] = []
        for id in allIDs {
            let previous = lastObservedDDCSupportByDisplayID[id]
            let current = currentSupport[id]
            guard previous != current else { continue }
            if current == .supported || current == .notSupported {
                resolvedIDs.append(id)
            }
        }
        lastObservedDDCSupportByDisplayID = currentSupport
        guard !resolvedIDs.isEmpty else { return }
        reapplyPendingBrightnessForResolvedDisplays(resolvedIDs)
        DiagnosticsLogger.shared.log("DDC support resolved for \(resolvedIDs.count) displays; reapplying persisted monitor state", category: "engine")
        schedulePersistedMonitorStateRestore(
            reason: "ddcSupportResolved",
            remainingAttempts: 3,
            initialDelayNanoseconds: ddcResolvedRestoreDelayNanoseconds
        )
    }

    /// Replays deferred brightness targets after DDC support transitions out of "unknown".
    private func reapplyPendingBrightnessForResolvedDisplays(_ resolvedIDs: [String]) {
        guard !resolvedIDs.isEmpty else { return }
        let displayByID = Dictionary(uniqueKeysWithValues: displayManager.displays.map { ($0.stableIdentity, $0) })
        for id in resolvedIDs {
            guard let target = pendingBrightnessByDisplayID[id], let display = displayByID[id] else { continue }
            guard display.isExternal else {
                pendingBrightnessByDisplayID.removeValue(forKey: id)
                continue
            }
            let status = ddcManager.states[id]?.status
            if status == .supported {
                applyExternalBrightness(target, for: display, persist: true, fallbackAnimated: false)
                continue
            }
            if status == .notSupported {
                blackoutManager.setBrightnessFallback(Double(target), for: display, animated: false)
                pendingBrightnessByDisplayID.removeValue(forKey: id)
            }
        }
    }

    /// Persists monitor power state for one display.
    private func persistPowerState(_ state: PersistedMonitorPowerState, for id: String, reason: String = "unspecified") {
        var previous: PersistedMonitorPowerState?
        settingsStore.update { settings in
            previous = settings.monitorPowerStateByDisplayID[id] ?? .visible
            settings.monitorPowerStateByDisplayID[id] = state
        }
        if previous != state {
            DiagnosticsLogger.shared.log(
                "Power state transition id=\(id) from=\(previous?.rawValue ?? PersistedMonitorPowerState.visible.rawValue) to=\(state.rawValue) reason=\(reason)",
                category: "engine"
            )
        }
    }

    /// Persists monitor brightness for one display.
    private func persistBrightness(_ brightness: Int, for id: String) {
        let clamped = max(0, min(100, brightness))
        settingsStore.update { settings in
            settings.monitorBrightnessByDisplayID[id] = clamped
        }
    }

    /// Applies blackout mode for built-in displays by fading brightness to 0.
    private func applyBuiltinBlackout(_ display: DisplayInfo, animated: Bool, persistState: Bool) {
        let id = display.stableIdentity
        automaticRestoreSuppressedUntilByDisplayID.removeValue(forKey: id)
        let restoreTarget = builtinRestoreBrightnessByDisplayID[id]
            ?? DisplayHardware.builtinDisplayBrightnessPercent(for: display.displayID)
            ?? settingsStore.settings.monitorBrightnessByDisplayID[id]
            ?? 100
        builtinRestoreBrightnessByDisplayID[id] = restoreTarget
        persistBrightness(restoreTarget, for: id)
        setBuiltinBrightness(0, for: display, animated: animated, reason: "builtinBlackout")
        if persistState {
            persistPowerState(.blackout, for: id, reason: "builtinBlackout")
        }
    }

    /// Restores built-in display brightness from the saved pre-blackout level.
    private func applyBuiltinVisible(_ display: DisplayInfo, animated: Bool, persistState: Bool) {
        let id = display.stableIdentity
        let target = builtinRestoreBrightnessByDisplayID.removeValue(forKey: id)
            ?? settingsStore.settings.monitorBrightnessByDisplayID[id]
            ?? 100
        setBuiltinBrightness(target, for: display, animated: animated, reason: "builtinVisible")
        persistBrightness(target, for: id)
        if persistState {
            persistPowerState(.visible, for: id, reason: "builtinVisible")
        }
    }

    /// Sets built-in panel brightness, optionally animating the transition.
    private func setBuiltinBrightness(_ percent: Int, for display: DisplayInfo, animated: Bool, reason: String = "unspecified") {
        let id = display.stableIdentity
        let target = max(0, min(100, percent))
        animationDriver.cancel(id: "builtin:\(id)")

        let applyTarget = {
            let success = DisplayHardware.setBuiltinDisplayBrightnessPercent(target, for: display.displayID)
            if success {
                self.updateBuiltinBrightnessSnapshot(target, for: id)
            }
            DiagnosticsLogger.shared.log(
                "Builtin brightness apply id=\(id) target=\(target) animated=\(animated) reason=\(reason) success=\(success)",
                category: "engine"
            )
        }

        guard animated else {
            applyTarget()
            return
        }

        let current = DisplayHardware.builtinDisplayBrightnessPercent(for: display.displayID)
            ?? settingsStore.settings.monitorBrightnessByDisplayID[id]
            ?? target
        guard current != target else {
            applyTarget()
            return
        }

        let delta = target - current
        let transitionMultiplier = settingsStore.settings.transitionSpeed.multiplier
        guard transitionMultiplier > 0 else {
            applyTarget()
            return
        }
        let totalDuration = 0.28 * transitionMultiplier
        animationDriver.start(id: "builtin:\(id)", screen: animationScreen(for: display), duration: totalDuration) { [weak self] progress in
            guard let self else { return }
            let exact = Double(current) + Double(delta) * progress
            self.preciseBrightnessLevels[id] = exact
            let value = Int(exact.rounded())
            if DisplayHardware.setBuiltinDisplayBrightnessPercent(value, for: display.displayID) {
                self.updateBuiltinBrightnessSnapshot(value, for: id)
            }
        } onComplete: { [weak self] in
            guard let self else { return }
            self.preciseBrightnessLevels.removeValue(forKey: id)
            if DisplayHardware.setBuiltinDisplayBrightnessPercent(target, for: display.displayID) {
                self.updateBuiltinBrightnessSnapshot(target, for: id)
            }
            DiagnosticsLogger.shared.log(
                "Builtin brightness apply id=\(id) target=\(target) animated=true reason=\(reason)",
                category: "engine"
            )
        }
    }

    /// Updates the built-in brightness snapshot only when the effective value changed.
    private func updateBuiltinBrightnessSnapshot(_ brightness: Int, for id: String) {
        let clamped = max(0, min(100, brightness))
        guard builtinBrightnessLevels[id] != clamped else { return }
        builtinBrightnessLevels[id] = clamped
    }

    /// Migrates legacy persistence keys into settings-backed monitor state.
    private func migrateLegacyMonitorStatePersistenceIfNeeded() {
        if !settingsStore.settings.monitorPowerStateByDisplayID.isEmpty {
            return
        }

        let persistedSleep = UserDefaults.standard.array(forKey: legacySleepPersistenceKey) as? [String] ?? []
        let persistedBlackout = UserDefaults.standard.array(forKey: legacyBlackoutPersistenceKey) as? [String] ?? []
        guard !persistedSleep.isEmpty || !persistedBlackout.isEmpty else { return }

        settingsStore.update { settings in
            var updated = settings.monitorPowerStateByDisplayID
            for id in persistedBlackout {
                updated[id] = .blackout
            }
            for id in persistedSleep {
                updated[id] = .standby
            }
            settings.monitorPowerStateByDisplayID = updated
        }

        UserDefaults.standard.set([], forKey: legacySleepPersistenceKey)
    }
}
