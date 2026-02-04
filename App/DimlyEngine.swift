// MARK: - Core Engine
// Central hub for hotkeys, blackout control, DDC actions, and profile coordination.
import AppKit
import Combine
import OSLog

/// Core, non-UI engine that owns hotkeys and display actions.
@MainActor
final class DimlyEngine {
    private let settingsStore: AppSettingsStore
    private let panicHotkeyManager: HotkeyManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "Engine")
    private var settingsCancellable: AnyCancellable?
    private var hotkeyManagers: [UUID: HotkeyManager] = [:]
    private let sleepPersistenceKey = "Sleep.activeDisplayIDs"
    let displayManager: DisplayManager
    let blackoutManager: BlackoutManager
    let ddcManager: DDCManager
    let profileManager: ProfileManager
    var onToggleWindow: (() -> Void)?

    /// Builds all managers and binds settings/hotkeys.
    init(settingsStore: AppSettingsStore, displayManager: DisplayManager = DisplayManager()) {
        self.settingsStore = settingsStore
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
        DiagnosticsLogger.shared.log("Engine init: managers constructed", category: "engine")
        self.panicHotkeyManager.onHotkeyPressed = { [weak self] in
            self?.blackoutManager.panic(animated: false)
        }

        apply(settings: settingsStore.settings)

        settingsCancellable = settingsStore.$settings
            .removeDuplicates()
            .sink { [weak self] newSettings in
                DiagnosticsLogger.shared.log("Settings changed: updating hotkeys", category: "engine")
                self?.apply(settings: newSettings)
            }

        profileManager.engine = self
        restoreStartupSleepState()

        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.blackoutManager.replayStartupFadeIfNeeded()
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
            removeSleepPersistence(for: display.stableIdentity)
            DiagnosticsLogger.shared.log("Standby fallback to blackout for \(display.stableIdentity)", category: "engine")
            return
        }

        if blackoutManager.hasPersistentOverlay(for: display) {
            if ddcManager.standby(display) {
                addSleepPersistence(for: display.stableIdentity)
            } else {
                removeSleepPersistence(for: display.stableIdentity)
            }
            return
        }

        blackoutManager.showTransitionOverlay(for: display, animated: fadeOut) { [weak self] in
            guard let self else { return }
            if self.ddcManager.standby(display) == false {
                self.logger.info("DDC standby failed; using blackout fallback for \(display.stableIdentity, privacy: .public)")
                self.blackoutManager.promoteTransitionToPersistent(display: display)
                self.removeSleepPersistence(for: display.stableIdentity)
                DiagnosticsLogger.shared.log("Standby failed, fallback to blackout for \(display.stableIdentity)", category: "engine")
                return
            }
            self.addSleepPersistence(for: display.stableIdentity)
        }
    }

    /// Wakes a display via DDC or removes blackout fallback.
    func wake(display: DisplayInfo) {
        removeSleepPersistence(for: display.stableIdentity)
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
            DiagnosticsLogger.shared.log("Wake fallback to unblackout for \(display.stableIdentity)", category: "engine")
            return
        }

        if ddcManager.wake(display) == false {
            logger.info("DDC wake failed; clearing blackout fallback for \(display.stableIdentity, privacy: .public)")
            blackoutManager.unblackout(display, animated: fadeIn)
            DiagnosticsLogger.shared.log("Wake failed, fallback to unblackout for \(display.stableIdentity)", category: "engine")
            return
        }

        if blackoutManager.hasPersistentOverlay(for: display) {
            blackoutManager.unblackout(display, animated: fadeIn)
        }

        let delaySeconds: TimeInterval = (fadeIn && wasDDCAsleep) ? 2.0 : 0.0
        blackoutManager.hideTransitionOverlay(for: display, animated: fadeIn, delay: delaySeconds)
    }

    /// Releases hotkeys and removes overlays before app termination.
    func cleanupBeforeExit() {
        DiagnosticsLogger.shared.log("Cleanup before exit", category: "engine")
        hotkeyManagers.values.forEach { $0.deactivate() }
        blackoutManager.cleanupBeforeExit()
    }

    // MARK: - Private

    /// Re-applies settings-dependent behaviors (currently hotkeys).
    private func apply(settings: DimlySettings) {
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

    // Placeholder notification removed in favor of direct display actions.

    /// Restores any persisted sleep state from the last run.
    private func restoreStartupSleepState() {
        let persisted = loadSleepPersistence()
        guard !persisted.isEmpty else { return }

        let displays = displayManager.displays.filter { persisted.contains($0.stableIdentity) }
        guard !displays.isEmpty else { return }

        attemptSleepRestore(for: displays, remainingAttempts: 5)
    }

    /// Retries sleep restoration while DDC probing is still resolving.
    private func attemptSleepRestore(for displays: [DisplayInfo], remainingAttempts: Int) {
        let settings = settingsStore.settings
        var pending: [DisplayInfo] = []

        for display in displays {
            let id = display.stableIdentity
            if settings.overlayOnlyDisplayIDs.contains(id) {
                blackoutManager.blackout(display, animated: settings.fadeOutAnimationEnabled)
                removeSleepPersistence(for: id)
                continue
            }

            guard let state = ddcManager.states[id]?.status else {
                pending.append(display)
                continue
            }

            switch state {
            case .supported:
                standby(display: display)
            case .notSupported:
                removeSleepPersistence(for: id)
            case .unknown:
                pending.append(display)
            }
        }

        guard remainingAttempts > 0, !pending.isEmpty else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 400_000_000)
            attemptSleepRestore(for: pending, remainingAttempts: remainingAttempts - 1)
        }
    }

    /// Loads persisted sleep IDs from UserDefaults.
    private func loadSleepPersistence() -> Set<String> {
        let stored = UserDefaults.standard.array(forKey: sleepPersistenceKey) as? [String] ?? []
        return Set(stored)
    }

    /// Persists that a display was requested to sleep.
    private func addSleepPersistence(for id: String) {
        var stored = loadSleepPersistence()
        stored.insert(id)
        UserDefaults.standard.set(Array(stored), forKey: sleepPersistenceKey)
    }

    /// Clears a display from the persisted sleep list.
    private func removeSleepPersistence(for id: String) {
        var stored = loadSleepPersistence()
        guard stored.remove(id) != nil else { return }
        UserDefaults.standard.set(Array(stored), forKey: sleepPersistenceKey)
    }
}
