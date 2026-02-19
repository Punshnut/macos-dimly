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

/// Core, non-UI engine that owns hotkeys and display actions.
@MainActor
final class DimlyEngine {
    private let settingsStore: AppSettingsStore
    private let launcherHotkeyManager: HotkeyManager
    private let panicHotkeyManager: HotkeyManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "Engine")
    private var settingsCancellable: AnyCancellable?
    private var stateCancellables: Set<AnyCancellable> = []
    private var pendingBrightnessByDisplayID: [String: Int] = [:]
    private var brightnessRequestRevisionByDisplayID: [String: Int] = [:]
    private var lastObservedBlackoutActiveIDs: Set<String> = []
    private var lastObservedDDCSupportByDisplayID: [String: DDCSupportStatus] = [:]
    private var hotkeyManagers: [UUID: HotkeyManager] = [:]
    private let legacySleepPersistenceKey = "Sleep.activeDisplayIDs"
    private let legacyBlackoutPersistenceKey = "Blackout.activeDisplayIDs"
    private var workspaceWakeToken: NSObjectProtocol?
    private var workspaceScreensWakeToken: NSObjectProtocol?
    let displayManager: DisplayManager
    let blackoutManager: BlackoutManager
    let ddcManager: DDCManager
    let profileManager: ProfileManager
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
            ddcManager: ddcManager
        )
        self.lastObservedBlackoutActiveIDs = blackoutManager.activeDisplayIDs
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
        restorePersistedMonitorState(reason: "startup", remainingAttempts: 5)

        workspaceWakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restorePersistedMonitorState(reason: "workspaceDidWake", remainingAttempts: 5)
            }
        }
        workspaceScreensWakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restorePersistedMonitorState(reason: "workspaceScreensDidWake", remainingAttempts: 5)
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
        if let workspaceWakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceWakeToken)
        }
        if let workspaceScreensWakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceScreensWakeToken)
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
        let settings = settingsStore.settings
        blackoutManager.toggleAllExternal(
            displays: displayManager.displays,
            fadeOut: settings.fadeOutAnimationEnabled,
            fadeIn: settings.fadeInAnimationEnabled
        )
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
    }

    /// Sets brightness for a display, preferring DDC and falling back to dim overlay.
    func setBrightness(_ percent: Int, for display: DisplayInfo) {
        let clamped = max(0, min(100, percent))
        guard display.isExternal else { return }
        persistBrightness(clamped, for: display.stableIdentity)
        pendingBrightnessByDisplayID[display.stableIdentity] = clamped
        let revision = (brightnessRequestRevisionByDisplayID[display.stableIdentity] ?? 0) + 1
        brightnessRequestRevisionByDisplayID[display.stableIdentity] = revision
        let settings = settingsStore.settings
        let overlayOnly = settings.overlayOnlyDisplayIDs.contains(display.stableIdentity)
        let ddcStatus = ddcManager.states[display.stableIdentity]?.status
        let canAttemptDDC = !overlayOnly && ddcStatus != .notSupported
        if overlayOnly {
            blackoutManager.setBrightnessFallback(
                clamped,
                for: display,
                animated: settings.fadeOutAnimationEnabled
            )
            pendingBrightnessByDisplayID.removeValue(forKey: display.stableIdentity)
            return
        }
        if ddcStatus == .unknown || ddcStatus == nil {
            blackoutManager.setBrightnessFallback(
                clamped,
                for: display,
                animated: settings.fadeOutAnimationEnabled
            )
            pendingBrightnessByDisplayID.removeValue(forKey: display.stableIdentity)
            return
        }
        if canAttemptDDC {
            ddcManager.setBrightness(clamped, for: display) { [weak self] success in
                guard let self else { return }
                guard self.brightnessRequestRevisionByDisplayID[display.stableIdentity] == revision else { return }
                if success {
                    self.blackoutManager.clearBrightnessFallback(for: display)
                    self.pendingBrightnessByDisplayID.removeValue(forKey: display.stableIdentity)
                    return
                }
                self.blackoutManager.setBrightnessFallback(
                    clamped,
                    for: display,
                    animated: settings.fadeOutAnimationEnabled
                )
                self.pendingBrightnessByDisplayID.removeValue(forKey: display.stableIdentity)
            }
            return
        }
        blackoutManager.setBrightnessFallback(
            clamped,
            for: display,
            animated: settings.fadeOutAnimationEnabled
        )
        pendingBrightnessByDisplayID.removeValue(forKey: display.stableIdentity)
    }

    /// Returns current brightness value used for UI (0-100).
    func brightnessPercent(for display: DisplayInfo) -> Int {
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
        let overlayOnly = settings.overlayOnlyDisplayIDs.contains(display.stableIdentity)
        let fadeOut = settings.fadeOutAnimationEnabled
        let ddcSupported = ddcManager.states[display.stableIdentity]?.status == .supported

        if overlayOnly || !ddcSupported {
            if !ddcSupported {
                logger.info("DDC standby unsupported; using blackout fallback for \(display.stableIdentity, privacy: .public)")
            }
            blackoutManager.blackout(display, animated: fadeOut)
            persistPowerState(.blackout, for: display.stableIdentity)
            DiagnosticsLogger.shared.log("Standby fallback to blackout for \(display.stableIdentity)", category: "engine")
            return
        }

        if blackoutManager.hasPersistentOverlay(for: display) {
            if ddcManager.standby(display) {
                persistPowerState(.standby, for: display.stableIdentity)
            } else {
                persistPowerState(.blackout, for: display.stableIdentity)
            }
            return
        }

        blackoutManager.showTransitionOverlay(for: display, animated: fadeOut) { [weak self] in
            guard let self else { return }
            if self.ddcManager.standby(display) == false {
                self.logger.info("DDC standby failed; using blackout fallback for \(display.stableIdentity, privacy: .public)")
                self.blackoutManager.promoteTransitionToPersistent(display: display)
                self.persistPowerState(.blackout, for: display.stableIdentity)
                DiagnosticsLogger.shared.log("Standby failed, fallback to blackout for \(display.stableIdentity)", category: "engine")
                return
            }
            self.persistPowerState(.standby, for: display.stableIdentity)
        }
    }

    /// Wakes a display via DDC or removes blackout fallback.
    func wake(display: DisplayInfo) {
        let settings = settingsStore.settings
        let overlayOnly = settings.overlayOnlyDisplayIDs.contains(display.stableIdentity)
        let fadeIn = settings.fadeInAnimationEnabled
        let ddcSupported = ddcManager.states[display.stableIdentity]?.status == .supported
        let wasDDCAsleep = ddcManager.states[display.stableIdentity]?.lastCommand == .standby

        if overlayOnly || !ddcSupported {
            if !ddcSupported {
                logger.info("DDC wake unsupported; clearing blackout fallback for \(display.stableIdentity, privacy: .public)")
            }
            blackoutManager.unblackout(display, animated: fadeIn)
            persistPowerState(.visible, for: display.stableIdentity)
            DiagnosticsLogger.shared.log("Wake fallback to unblackout for \(display.stableIdentity)", category: "engine")
            return
        }

        if ddcManager.wake(display) == false {
            logger.info("DDC wake failed; clearing blackout fallback for \(display.stableIdentity, privacy: .public)")
            blackoutManager.unblackout(display, animated: fadeIn)
            persistPowerState(.visible, for: display.stableIdentity)
            DiagnosticsLogger.shared.log("Wake failed, fallback to unblackout for \(display.stableIdentity)", category: "engine")
            return
        }

        if blackoutManager.hasPersistentOverlay(for: display) {
            blackoutManager.unblackout(display, animated: fadeIn)
        }

        let delaySeconds: TimeInterval = (fadeIn && wasDDCAsleep) ? 2.0 : 0.0
        blackoutManager.hideTransitionOverlay(for: display, animated: fadeIn, delay: delaySeconds)
        persistPowerState(.visible, for: display.stableIdentity)
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
            let settings = settingsStore.settings
            blackoutManager.toggle(display: display, fadeOut: settings.fadeOutAnimationEnabled, fadeIn: settings.fadeInAnimationEnabled)
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

    /// Returns true when a display is blacked out or in DDC standby.
    private func isDisplayAsleep(_ display: DisplayInfo) -> Bool {
        if blackoutManager.activeDisplayIDs.contains(display.stableIdentity) {
            return true
        }
        return ddcManager.states[display.stableIdentity]?.lastCommand == .standby
    }

    /// Subscribes to display/overlay changes to keep persisted monitor state in sync.
    private func observeMonitorState() {
        displayManager.$displays
            .sink { [weak self] _ in
                self?.restorePersistedMonitorState(reason: "displayChange", remainingAttempts: 5)
            }
            .store(in: &stateCancellables)

        blackoutManager.$activeDisplayIDs
            .sink { [weak self] activeIDs in
                self?.syncPersistedPowerStatesFromBlackoutActiveIDs(activeIDs)
            }
            .store(in: &stateCancellables)

        ddcManager.$states
            .sink { [weak self] states in
                self?.handleDDCStateChanges(states)
            }
            .store(in: &stateCancellables)
    }

    /// Applies persisted power + brightness state to currently connected displays.
    private func restorePersistedMonitorState(reason: String, remainingAttempts: Int) {
        let settings = settingsStore.settings
        let externals = displayManager.displays.filter(\.isExternal)
        guard !externals.isEmpty else { return }

        DiagnosticsLogger.shared.log("Restore persisted monitor state reason=\(reason) displays=\(externals.count)", category: "engine")
        var pending: [DisplayInfo] = []

        for display in externals {
            let id = display.stableIdentity
            let power = settings.monitorPowerStateByDisplayID[id] ?? .visible

            if power != .standby, let brightness = settings.monitorBrightnessByDisplayID[id] {
                setBrightness(brightness, for: display)
            }

            switch power {
            case .visible:
                if blackoutManager.activeDisplayIDs.contains(id) {
                    blackoutManager.unblackout(display, animated: settings.fadeInAnimationEnabled)
                }
            case .blackout:
                blackoutManager.blackout(display, animated: settings.fadeOutAnimationEnabled)
            case .standby:
                if settings.overlayOnlyDisplayIDs.contains(id) {
                    blackoutManager.blackout(display, animated: settings.fadeOutAnimationEnabled)
                    persistPowerState(.blackout, for: id)
                    continue
                }
                guard let status = ddcManager.states[id]?.status else {
                    pending.append(display)
                    continue
                }
                switch status {
                case .supported:
                    standby(display: display)
                case .notSupported:
                    blackoutManager.blackout(display, animated: settings.fadeOutAnimationEnabled)
                    persistPowerState(.blackout, for: id)
                case .unknown:
                    pending.append(display)
                }
            }
        }

        guard remainingAttempts > 0, !pending.isEmpty else { return }
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            self?.restorePersistedMonitorState(
                reason: "\(reason)-retry",
                remainingAttempts: remainingAttempts - 1
            )
        }
    }

    /// Mirrors active blackout overlays into persisted monitor power states.
    private func syncPersistedPowerStatesFromBlackoutActiveIDs(_ activeIDs: Set<String>) {
        let added = activeIDs.subtracting(lastObservedBlackoutActiveIDs)
        let removed = lastObservedBlackoutActiveIDs.subtracting(activeIDs)
        lastObservedBlackoutActiveIDs = activeIDs
        guard !added.isEmpty || !removed.isEmpty else { return }

        settingsStore.update { settings in
            var updated = settings.monitorPowerStateByDisplayID
            for id in added where settings.monitorPowerStateByDisplayID[id] != .standby {
                updated[id] = .blackout
            }
            for id in removed where settings.monitorPowerStateByDisplayID[id] == .blackout {
                updated[id] = .visible
            }
            settings.monitorPowerStateByDisplayID = updated
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
        DiagnosticsLogger.shared.log("DDC support resolved for \(resolvedIDs.count) displays; reapplying persisted monitor state", category: "engine")
        restorePersistedMonitorState(reason: "ddcSupportResolved", remainingAttempts: 3)
    }

    /// Persists monitor power state for one display.
    private func persistPowerState(_ state: PersistedMonitorPowerState, for id: String) {
        settingsStore.update { settings in
            settings.monitorPowerStateByDisplayID[id] = state
        }
    }

    /// Persists monitor brightness for one display.
    private func persistBrightness(_ brightness: Int, for id: String) {
        let clamped = max(0, min(100, brightness))
        settingsStore.update { settings in
            settings.monitorBrightnessByDisplayID[id] = clamped
        }
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
