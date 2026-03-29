// MARK: - Blackout Manager
// Lifecycle manager for external-display blackout overlays.
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
    private var brightnessFallbackOverlays: [String: DimOverlayWindow] = [:]
    @Published private(set) var activeDisplayIDs: Set<String> = []
    @Published private(set) var fallbackBrightnessLevels: [String: Int] = [:] // stableIdentity -> percent (0...99)
    private var persistenceToken: AnyCancellable?
    private var displayChangeToken: AnyCancellable?
    private let persistenceKey = "Blackout.activeDisplayIDs"
    private let startupRestoreAnimated: Bool
    private var hasPerformedStartupRestore = false
    private let startupFadeDelay: TimeInterval = 0.12
    private var didReplayStartupFade = false

    /// Initializes the manager and restores persisted blackout state.
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

    /// Indicates whether any blackout or transition overlay is visible.
    var hasAnyOverlays: Bool {
        !overlays.isEmpty || !transitionOverlays.isEmpty || !brightnessFallbackOverlays.isEmpty
    }

    /// Toggles blackout for a single display.
    func toggle(display: DisplayInfo, fadeOut: Bool, fadeIn: Bool) {
        if activeDisplayIDs.contains(display.stableIdentity) {
            unblackout(display, animated: fadeIn)
        } else {
            blackout(display, animated: fadeOut)
        }
    }

    /// Applies blackout to a display by showing a fullscreen overlay.
    func blackout(_ display: DisplayInfo, animated: Bool, delay: TimeInterval = 0, deferShow: Bool = false) {
        guard display.isExternal else {
            logger.info("Refusing to blackout non-external display \(display.stableIdentity, privacy: .public)")
            DiagnosticsLogger.shared.log("Skip blackout for non-external \(display.stableIdentity)", category: "blackout")
            return
        }
        if let window = overlays[display.stableIdentity] {
            if let screen = screen(for: display.displayID) {
                window.update(screen: screen)
            }
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

    /// Clears all blackout and transition overlays immediately.
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
        brightnessFallbackOverlays.values.forEach { window in
            window.hide(animated: animated) {
                window.close()
            }
        }
        transitionOverlays.removeAll()
        brightnessFallbackOverlays.removeAll()
        fallbackBrightnessLevels.removeAll()
        activeDisplayIDs.removeAll()
        persistState()
        logger.notice("Panic invoked: cleared all blackout overlays")
        DiagnosticsLogger.shared.log("Panic cleared overlays", category: "blackout")
    }

    /// Closes all overlay windows during app shutdown.
    func cleanupBeforeExit() {
        overlays.values.forEach { window in
            window.hide(animated: false)
            window.close()
        }
        transitionOverlays.values.forEach { window in
            window.hide(animated: false)
            window.close()
        }
        brightnessFallbackOverlays.values.forEach { window in
            window.hide(animated: false)
            window.close()
        }
        overlays.removeAll()
        transitionOverlays.removeAll()
        brightnessFallbackOverlays.removeAll()
        fallbackBrightnessLevels.removeAll()
        activeDisplayIDs.removeAll()
        persistState()
    }

    /// Fades out and closes all overlays before exit.
    func fadeOutAllAndClose(animated: Bool, completion: @escaping () -> Void) {
        let blackoutWindows = Array(overlays.values) + Array(transitionOverlays.values)
        let brightnessWindows = Array(brightnessFallbackOverlays.values)
        let totalWindowCount = blackoutWindows.count + brightnessWindows.count
        guard totalWindowCount > 0 else {
            persistState()
            completion()
            return
        }
        overlays.removeAll()
        transitionOverlays.removeAll()
        brightnessFallbackOverlays.removeAll()
        fallbackBrightnessLevels.removeAll()
        activeDisplayIDs.removeAll()
        persistState()
        var remaining = totalWindowCount
        let finish: () -> Void = {
            remaining -= 1
            if remaining == 0 {
                completion()
            }
        }
        blackoutWindows.forEach { window in
            window.hide(animated: animated) {
                window.close()
                finish()
            }
        }
        brightnessWindows.forEach { window in
            window.hide(animated: animated) {
                window.close()
                finish()
            }
        }
    }

    /// Applies non-blocking brightness fallback via black overlay opacity.
    func setBrightnessFallback(_ percent: Int, for display: DisplayInfo, animated: Bool) {
        guard display.isExternal else { return }
        let clamped = max(0, min(100, percent))
        guard clamped < 100 else {
            clearBrightnessFallback(for: display, animated: animated)
            return
        }
        guard let screen = screen(for: display.displayID) else { return }

        let opacity = fallbackOpacity(forBrightnessPercent: clamped)
        let window: DimOverlayWindow
        let previousLevel = fallbackBrightnessLevels[display.stableIdentity]
        if let existing = brightnessFallbackOverlays[display.stableIdentity] {
            window = existing
            window.update(screen: screen)
        } else {
            let created = DimOverlayWindow(screen: screen)
            brightnessFallbackOverlays[display.stableIdentity] = created
            window = created
        }
        guard previousLevel != clamped || brightnessFallbackOverlays[display.stableIdentity] == nil else { return }
        window.setOpacity(opacity, animated: animated)
        fallbackBrightnessLevels[display.stableIdentity] = clamped
    }

    /// Clears a non-blocking brightness fallback overlay for a display.
    func clearBrightnessFallback(for display: DisplayInfo, animated: Bool = false) {
        guard let window = brightnessFallbackOverlays[display.stableIdentity] else {
            fallbackBrightnessLevels.removeValue(forKey: display.stableIdentity)
            return
        }
        window.hide(animated: animated) { [weak self] in
            window.close()
            self?.brightnessFallbackOverlays.removeValue(forKey: display.stableIdentity)
        }
        fallbackBrightnessLevels.removeValue(forKey: display.stableIdentity)
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
        let staleBrightnessOverlays = brightnessFallbackOverlays.keys.filter { !liveIDs.contains($0) }
        for key in staleBrightnessOverlays {
            if let window = brightnessFallbackOverlays[key] {
                window.hide(animated: false)
                window.close()
            }
            brightnessFallbackOverlays.removeValue(forKey: key)
            fallbackBrightnessLevels.removeValue(forKey: key)
        }
        rebindWindows(to: displays)

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

    /// Rebinds persistent/transition overlays to the latest NSScreen geometry.
    private func rebindWindows(to displays: [DisplayInfo]) {
        var byIdentity: [String: DisplayInfo] = [:]
        for display in displays {
            byIdentity[display.stableIdentity] = display
        }

        for (id, window) in overlays {
            guard let display = byIdentity[id] else { continue }
            guard let screen = screen(for: display.displayID) else {
                if activeDisplayIDs.contains(id) {
                    window.hide(animated: false)
                    DiagnosticsLogger.shared.log("Hid overlay due to missing screen for \(id)", category: "blackout")
                }
                continue
            }
            window.update(screen: screen)
            if activeDisplayIDs.contains(id) {
                window.show(animated: false)
            } else {
                window.hide(animated: false)
            }
        }

        for (id, window) in transitionOverlays {
            guard let display = byIdentity[id], let screen = screen(for: display.displayID) else { continue }
            window.update(screen: screen)
        }

        for (id, window) in brightnessFallbackOverlays {
            guard let display = byIdentity[id], let screen = screen(for: display.displayID) else { continue }
            window.update(screen: screen)
            let level = fallbackBrightnessLevels[id] ?? 100
            if level < 100 {
                let opacity = fallbackOpacity(forBrightnessPercent: level)
                window.setOpacity(opacity, animated: false)
            } else {
                window.hide(animated: false)
            }
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

    /// Presents an overlay, optionally after a delay.
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

    /// Converts brightness percentage into black-overlay opacity.
    private func fallbackOpacity(forBrightnessPercent percent: Int) -> CGFloat {
        let clamped = max(0, min(100, percent))
        return CGFloat((100 - clamped)) / 100.0
    }

    // MARK: - Transition overlays

    /// Indicates whether a persistent overlay exists for the display.
    func hasPersistentOverlay(for display: DisplayInfo) -> Bool {
        overlays[display.stableIdentity] != nil
    }

    /// Presents a temporary overlay during DDC transitions.
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
            if let screen = screen(for: display.displayID) {
                window.update(screen: screen)
            }
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

/// Borderless black window pinned to a display.
final class BlackoutWindow: NSWindow {
    private enum Animation {
        static let duration: TimeInterval = 0.45
    }

    /// Backing view that paints black.
    private final class BlackoutView: NSView {
        override var wantsUpdateLayer: Bool { true }

        /// Keeps the backing layer solid black without requiring a custom draw pass.
        override func updateLayer() {
            layer?.backgroundColor = NSColor.black.cgColor
        }
    }

    private let blackoutView = BlackoutView()
    private var animationToken: Int = 0
    private var pendingCompletions: [Int: () -> Void] = [:]

    /// Initializes a borderless overlay window for a screen.
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
        ignoresMouseEvents = false // Intentionally intercepts clicks so the blackout behaves like a true cover layer.
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        blackoutView.wantsLayer = true
        blackoutView.layer?.opacity = 1
        blackoutView.autoresizingMask = [.width, .height]
        contentView = blackoutView
        update(screen: screen)
    }

    /// Repositions and resizes the overlay to match the target screen.
    func update(screen: NSScreen) {
        setFrame(screen.frame, display: true)
        blackoutView.frame = CGRect(origin: .zero, size: screen.frame.size)
    }

    /// Presents the overlay, optionally with a fade animation.
    func show(animated: Bool, completion: (() -> Void)? = nil) {
        animationToken += 1
        let token = animationToken
        guard animated else {
            alphaValue = 1
            orderFrontRegardless()
            completion?()
            return
        }
        enqueueCompletion(completion, token: token)
        orderFrontRegardless()
        alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Animation.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 1
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.completeAnimation(token: token, shouldOrderOut: false)
            }
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
        enqueueCompletion(completion, token: token)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Animation.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.completeAnimation(token: token, shouldOrderOut: true)
            }
        }
    }

    /// Queues an animation completion tied to the current animation token.
    private func enqueueCompletion(_ completion: (() -> Void)?, token: Int) {
        guard let completion else { return }
        pendingCompletions[token] = completion
    }

    /// Completes the current blackout animation if the token still matches.
    @MainActor private func completeAnimation(token: Int, shouldOrderOut: Bool) {
        guard animationToken == token else {
            pendingCompletions.removeValue(forKey: token)
            return
        }
        if shouldOrderOut {
            self.orderOut(nil)
        }
        let completion = pendingCompletions.removeValue(forKey: token)
        completion?()
    }
}

/// Borderless, non-interactive black overlay used for fallback brightness dimming.
final class DimOverlayWindow: NSWindow {
    private enum Animation {
        static let duration: TimeInterval = 0.2
    }

    private final class DimOverlayView: NSView {
        override var wantsUpdateLayer: Bool { true }

        /// Keeps the fallback dimming layer solid black while opacity is animated on the window.
        override func updateLayer() {
            layer?.backgroundColor = NSColor.black.cgColor
        }
    }

    private let overlayView = DimOverlayView()
    private var animationToken: Int = 0
    private var pendingCompletions: [Int: () -> Void] = [:]

    /// Initializes a borderless dimming overlay for a screen.
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
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlayView.wantsLayer = true
        overlayView.autoresizingMask = [.width, .height]
        contentView = overlayView
        update(screen: screen)
    }

    /// Repositions and resizes the overlay to match the target screen.
    func update(screen: NSScreen) {
        setFrame(screen.frame, display: true)
        overlayView.frame = CGRect(origin: .zero, size: screen.frame.size)
    }

    /// Sets the overlay alpha (0-1) and ensures visibility when non-zero.
    func setOpacity(_ opacity: CGFloat, animated: Bool) {
        let clamped = max(0, min(1, opacity))
        guard clamped > 0 else {
            hide(animated: animated)
            return
        }
        if abs(alphaValue - clamped) <= 0.001, isVisible {
            return
        }
        orderFrontRegardless()
        guard animated else {
            alphaValue = clamped
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Animation.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = clamped
        }
    }

    /// Hides the overlay.
    func hide(animated: Bool, completion: (() -> Void)? = nil) {
        animationToken += 1
        let token = animationToken
        guard animated else {
            alphaValue = 0
            orderOut(nil)
            completion?()
            return
        }
        enqueueCompletion(completion, token: token)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Animation.duration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.completeAnimation(token: token)
            }
        }
    }

    /// Queues an animation completion tied to the current animation token.
    private func enqueueCompletion(_ completion: (() -> Void)?, token: Int) {
        guard let completion else { return }
        pendingCompletions[token] = completion
    }

    /// Completes the current dim-overlay animation if the token still matches.
    @MainActor private func completeAnimation(token: Int) {
        guard animationToken == token else {
            pendingCompletions.removeValue(forKey: token)
            return
        }
        orderOut(nil)
        let completion = pendingCompletions.removeValue(forKey: token)
        completion?()
    }
}
