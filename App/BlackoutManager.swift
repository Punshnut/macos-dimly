// MARK: - Blackout Manager
// Owns the lifecycle of fullscreen blackout overlays per external display,
// persisting state and reacting to hardware changes.
import AppKit
import QuartzCore
import Combine
import OSLog

/// Manages fullscreen blackout overlays per external display.
@MainActor
final class BlackoutManager: ObservableObject {
    private let displayManager: DisplayManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "Blackout")
    private var overlays: [String: BlackoutWindow] = [:] // keyed by stableIdentity
    private var transitionOverlays: [String: BlackoutWindow] = [:]
    @Published private(set) var activeDisplayIDs: Set<String> = []
    private var persistenceToken: AnyCancellable?
    private var displayChangeToken: AnyCancellable?
    private let persistenceKey = "Blackout.activeDisplayIDs"
    private let startupRestoreAnimated: Bool
    private var hasPerformedStartupRestore = false
    private let startupFadeDelay: TimeInterval = 0.12
    private var didReplayStartupFade = false

    /// Creates the manager and restores persisted blackout state.
    init(displayManager: DisplayManager, startupRestoreAnimated: Bool) {
        self.displayManager = displayManager
        self.startupRestoreAnimated = startupRestoreAnimated
        DiagnosticsLogger.shared.log("BlackoutManager init", category: "blackout")
        hasPerformedStartupRestore = restorePersistedState(animated: startupRestoreAnimated)
        displayChangeToken = displayManager.$displays.sink { [weak self] displays in
            self?.reconcileDisplays(displays)
        }
    }

    // MARK: - Public API

    /// Returns true when any blackout or transition overlay is visible.
    var hasAnyOverlays: Bool {
        !overlays.isEmpty || !transitionOverlays.isEmpty
    }

    /// Toggles blackout for a single display.
    func toggle(display: DisplayInfo, fadeOut: Bool, fadeIn: Bool) {
        if activeDisplayIDs.contains(display.stableIdentity) {
            unblackout(display, animated: fadeIn)
        } else {
            blackout(display, animated: fadeOut)
        }
    }

    /// Blackouts a display by showing a fullscreen overlay window.
    func blackout(_ display: DisplayInfo, animated: Bool, delay: TimeInterval = 0, deferShow: Bool = false) {
        guard display.isExternal else {
            logger.info("Refusing to blackout non-external display \(display.stableIdentity, privacy: .public)")
            DiagnosticsLogger.shared.log("Skip blackout for non-external \(display.stableIdentity)", category: "blackout")
            return
        }
        if let window = overlays[display.stableIdentity] {
            if !deferShow {
                show(window, animated: animated, delay: delay)
            }
            activeDisplayIDs.insert(display.stableIdentity)
            persistState()
            logger.notice("Blackout ON for \(display.stableIdentity, privacy: .public)")
            DiagnosticsLogger.shared.log("Blackout ON for \(display.stableIdentity)", category: "blackout")
            return
        }
        guard let screen = screen(for: display.displayID) else {
            logger.error("No NSScreen found for display \(display.stableIdentity, privacy: .public)")
            DiagnosticsLogger.shared.log("Missing NSScreen for \(display.stableIdentity)", category: "blackout")
            return
        }
        let window = BlackoutWindow(screen: screen)
        overlays[display.stableIdentity] = window
        if !deferShow {
            show(window, animated: animated, delay: delay)
        }
        activeDisplayIDs.insert(display.stableIdentity)
        persistState()
        logger.notice("Blackout ON for \(display.stableIdentity, privacy: .public)")
        DiagnosticsLogger.shared.log("Blackout ON for \(display.stableIdentity)", category: "blackout")
    }

    /// Removes blackout overlay for a display.
    func unblackout(_ display: DisplayInfo, animated: Bool) {
        guard let window = overlays[display.stableIdentity] else { return }
        window.hide(animated: animated)
        activeDisplayIDs.remove(display.stableIdentity)
        persistState()
        logger.notice("Blackout OFF for \(display.stableIdentity, privacy: .public)")
        DiagnosticsLogger.shared.log("Blackout OFF for \(display.stableIdentity)", category: "blackout")
    }

    /// Toggles blackout across all external displays.
    func toggleAllExternal(displays: [DisplayInfo], fadeOut: Bool, fadeIn: Bool) {
        let externals = displays.filter { $0.isExternal }
        let anyActive = externals.contains { activeDisplayIDs.contains($0.stableIdentity) }
        if anyActive {
            externals.forEach { unblackout($0, animated: fadeIn) }
        } else {
            externals.forEach { blackout($0, animated: fadeOut) }
        }
        DiagnosticsLogger.shared.log("Toggle all external blackout active=\(anyActive)", category: "blackout")
    }

    /// Panic: clear all overlays.
    func panic(animated: Bool) {
        overlays.values.forEach { $0.hide(animated: animated) }
        transitionOverlays.values.forEach { window in
            if animated {
                window.hide(animated: true) {
                    window.close()
                }
            } else {
                window.hide(animated: false)
                window.close()
            }
        }
        transitionOverlays.removeAll()
        activeDisplayIDs.removeAll()
        persistState()
        logger.notice("Panic invoked: cleared all blackout overlays")
        DiagnosticsLogger.shared.log("Panic cleared overlays", category: "blackout")
    }

    /// Ensure no windows stay around if the app is quitting.
    func cleanupBeforeExit() {
        overlays.values.forEach { window in
            window.hide(animated: false)
            window.close()
        }
        transitionOverlays.values.forEach { window in
            window.hide(animated: false)
            window.close()
        }
        overlays.removeAll()
        transitionOverlays.removeAll()
        activeDisplayIDs.removeAll()
    }

    /// Fades out all overlays before quitting, then closes them.
    func fadeOutAllAndClose(animated: Bool, completion: @escaping () -> Void) {
        let windows = Array(overlays.values) + Array(transitionOverlays.values)
        guard !windows.isEmpty else {
            completion()
            return
        }
        overlays.removeAll()
        transitionOverlays.removeAll()
        activeDisplayIDs.removeAll()
        var remaining = windows.count
        let finish: () -> Void = {
            remaining -= 1
            if remaining == 0 {
                completion()
            }
        }
        windows.forEach { window in
            window.hide(animated: animated) {
                window.close()
                finish()
            }
        }
    }

    // MARK: - Private helpers

    /// Reconciles overlays with the current display inventory.
    private func reconcileDisplays(_ displays: [DisplayInfo]) {
        // Remove overlays for displays that disappeared.
        let liveIDs = Set(displays.map(\.stableIdentity))
        let stale = overlays.keys.filter { !liveIDs.contains($0) }
        for key in stale {
            if let window = overlays[key] {
                window.hide(animated: false)
                window.close()
            }
            overlays.removeValue(forKey: key)
            activeDisplayIDs.remove(key)
            logger.notice("Removing blackout window for disconnected display \(key, privacy: .public)")
            DiagnosticsLogger.shared.log("Removed overlay for disconnected display \(key)", category: "blackout")
        }
        let staleTransitions = transitionOverlays.keys.filter { !liveIDs.contains($0) }
        for key in staleTransitions {
            if let window = transitionOverlays[key] {
                window.hide(animated: false)
                window.close()
            }
            transitionOverlays.removeValue(forKey: key)
        }

        // Restore blackout for any newly present display that was persisted.
        let persisted = persistedIdentities()
        let animateRestore = !hasPerformedStartupRestore
        let shouldDeferStartupShow = startupRestoreAnimated && !didReplayStartupFade
        let deferShow = animateRestore ? startupRestoreAnimated : shouldDeferStartupShow
        for display in displays where persisted.contains(display.stableIdentity) && !activeDisplayIDs.contains(display.stableIdentity) {
            blackout(display, animated: animateRestore ? startupRestoreAnimated : false, delay: 0, deferShow: deferShow)
        }
        if deferShow {
            replayStartupFadeIfNeeded()
        }
        if !hasPerformedStartupRestore {
            hasPerformedStartupRestore = true
        }
    }

    /// Resolves the NSScreen for a CoreGraphics display ID.
    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == displayID
        }
    }

    /// Persists the active blackout display IDs to UserDefaults.
    private func persistState() {
        UserDefaults.standard.set(Array(activeDisplayIDs), forKey: persistenceKey)
    }

    /// Restores blackout overlays from persisted state.
    @discardableResult
    private func restorePersistedState(animated: Bool) -> Bool {
        guard let stored = UserDefaults.standard.array(forKey: persistenceKey) as? [String] else {
            UserDefaults.standard.set([], forKey: persistenceKey)
            return false
        }
        let currentDisplays = displayManager.displays
        var restored = false
        let deferShow = animated && startupRestoreAnimated
        for display in currentDisplays where stored.contains(display.stableIdentity) {
            blackout(display, animated: animated, delay: 0, deferShow: deferShow)
            restored = true
        }
        return restored
    }

    /// Shows the overlay, optionally delayed.
    private func show(_ window: BlackoutWindow, animated: Bool, delay: TimeInterval) {
        guard delay > 0, animated else {
            window.show(animated: animated)
            return
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            window.show(animated: animated)
        }
    }

    /// Reads persisted blackout IDs from UserDefaults.
    private func persistedIdentities() -> Set<String> {
        let stored = UserDefaults.standard.array(forKey: persistenceKey) as? [String] ?? []
        return Set(stored)
    }

    // MARK: - Transition overlays

    /// Returns true when a persistent overlay exists for the display.
    func hasPersistentOverlay(for display: DisplayInfo) -> Bool {
        overlays[display.stableIdentity] != nil
    }

    /// Shows a temporary overlay during DDC transitions.
    func showTransitionOverlay(for display: DisplayInfo, animated: Bool, completion: (() -> Void)? = nil) {
        guard display.isExternal else {
            completion?()
            return
        }
        if overlays[display.stableIdentity] != nil {
            completion?()
            return
        }
        if let window = transitionOverlays[display.stableIdentity] {
            window.show(animated: animated, completion: completion)
            return
        }
        guard let screen = screen(for: display.displayID) else {
            completion?()
            return
        }
        let window = BlackoutWindow(screen: screen)
        transitionOverlays[display.stableIdentity] = window
        window.show(animated: animated, completion: completion)
    }

    /// Hides and disposes a transition overlay.
    func hideTransitionOverlay(for display: DisplayInfo, animated: Bool, delay: TimeInterval = 0) {
        guard let window = transitionOverlays[display.stableIdentity] else { return }
        if delay > 0 {
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                window.hide(animated: animated) { [weak self] in
                    window.close()
                    self?.transitionOverlays.removeValue(forKey: display.stableIdentity)
                }
            }
        } else {
            window.hide(animated: animated) { [weak self] in
                window.close()
                self?.transitionOverlays.removeValue(forKey: display.stableIdentity)
            }
        }
    }

    /// Promotes a transition overlay to a persistent blackout overlay.
    func promoteTransitionToPersistent(display: DisplayInfo) {
        guard let window = transitionOverlays.removeValue(forKey: display.stableIdentity) else {
            blackout(display, animated: false)
            return
        }
        overlays[display.stableIdentity] = window
        activeDisplayIDs.insert(display.stableIdentity)
        persistState()
        logger.notice("Promoted transition overlay to persistent for \(display.stableIdentity, privacy: .public)")
        DiagnosticsLogger.shared.log("Transition promoted for \(display.stableIdentity)", category: "blackout")
    }

    /// Replays the startup fade once after restoring persisted overlays.
    func replayStartupFadeIfNeeded() {
        guard startupRestoreAnimated, !didReplayStartupFade else { return }
        let windows = overlays.values
        let transitionWindows = transitionOverlays.values
        guard !windows.isEmpty || !transitionWindows.isEmpty else { return }
        didReplayStartupFade = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(startupFadeDelay * 1_000_000_000))
            windows.forEach { $0.show(animated: true) }
            transitionWindows.forEach { $0.show(animated: true) }
        }
    }
}

/// Simple borderless black window pinned to a display.
final class BlackoutWindow: NSWindow {
    private enum Animation {
        static let duration: TimeInterval = 0.45
    }

    /// Plain view that paints a black background.
    private final class BlackoutView: NSView {
        override var wantsUpdateLayer: Bool { true }

        override func updateLayer() {
            layer?.backgroundColor = NSColor.black.cgColor
        }
    }

    private let blackoutView = BlackoutView()
    private var animationToken: Int = 0

    /// Creates a borderless overlay window for the given screen.
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .screenSaver
        animationBehavior = .none
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        alphaValue = 0
        hasShadow = false
        ignoresMouseEvents = false // blocks clicks; panic hotkey still works
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        blackoutView.frame = screen.frame
        blackoutView.wantsLayer = true
        blackoutView.layer?.opacity = 1
        contentView = blackoutView
        setFrame(screen.frame, display: true)
    }

    /// Shows the overlay with an optional fade animation.
    func show(animated: Bool, completion: (() -> Void)? = nil) {
        animationToken += 1
        let token = animationToken
        guard animated else {
            alphaValue = 1
            orderFrontRegardless()
            completion?()
            return
        }
        orderFrontRegardless()
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Animation.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            guard let self, self.animationToken == token else { return }
            completion?()
        }
    }

    /// Hides the overlay with an optional fade animation.
    func hide(animated: Bool, completion: (() -> Void)? = nil) {
        animationToken += 1
        let token = animationToken
        guard animated else {
            alphaValue = 0
            orderOut(nil)
            completion?()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Animation.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.animationToken == token else { return }
            self.orderOut(nil)
            completion?()
        }
    }
}
