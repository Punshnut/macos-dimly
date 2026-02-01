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

    func toggle(display: DisplayInfo, fadeOut: Bool, fadeIn: Bool) {
        if activeDisplayIDs.contains(display.stableIdentity) {
            unblackout(display, animated: fadeIn)
        } else {
            blackout(display, animated: fadeOut)
        }
    }

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

    func unblackout(_ display: DisplayInfo, animated: Bool) {
        guard let window = overlays[display.stableIdentity] else { return }
        window.hide(animated: animated)
        activeDisplayIDs.remove(display.stableIdentity)
        persistState()
        logger.notice("Blackout OFF for \(display.stableIdentity, privacy: .public)")
        DiagnosticsLogger.shared.log("Blackout OFF for \(display.stableIdentity)", category: "blackout")
    }

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

    // MARK: - Private helpers

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
        let deferShow = animateRestore && startupRestoreAnimated
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

    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == displayID
        }
    }

    private func persistState() {
        UserDefaults.standard.set(Array(activeDisplayIDs), forKey: persistenceKey)
    }

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

    private func persistedIdentities() -> Set<String> {
        let stored = UserDefaults.standard.array(forKey: persistenceKey) as? [String] ?? []
        return Set(stored)
    }

    // MARK: - Transition overlays

    func hasPersistentOverlay(for display: DisplayInfo) -> Bool {
        overlays[display.stableIdentity] != nil
    }

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
        static let overlayAlpha: Float = 0.35
        static let totalDuration: TimeInterval = 0.55
    }

    private final class BlackoutView: NSView {
        override var wantsUpdateLayer: Bool { true }

        override func updateLayer() {
            layer?.backgroundColor = NSColor.black.cgColor
        }
    }

    private let blackoutView = BlackoutView()
    private var animationToken: Int = 0

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
        hasShadow = false
        ignoresMouseEvents = false // blocks clicks; panic hotkey still works
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        blackoutView.frame = screen.frame
        blackoutView.wantsLayer = true
        blackoutView.layer?.opacity = 0
        contentView = blackoutView
        setFrame(screen.frame, display: true)
    }

    func show(animated: Bool, completion: (() -> Void)? = nil) {
        orderFrontRegardless()
        animationToken += 1
        let token = animationToken
        guard let layer = blackoutView.layer else {
            completion?()
            return
        }
        layer.removeAllAnimations()
        guard animated else {
            layer.opacity = 1
            completion?()
            return
        }
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [
            NSNumber(value: 0.0),
            NSNumber(value: Double(Animation.overlayAlpha)),
            NSNumber(value: 1.0)
        ]
        animation.keyTimes = [
            NSNumber(value: 0.0),
            NSNumber(value: 0.55),
            NSNumber(value: 1.0)
        ]
        animation.duration = Animation.totalDuration
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        layer.opacity = 1
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.animationToken == token else { return }
            completion?()
        }
        layer.add(animation, forKey: "opacityFadeIn")
        CATransaction.commit()
    }

    func hide(animated: Bool, completion: (() -> Void)? = nil) {
        animationToken += 1
        let token = animationToken
        guard let layer = blackoutView.layer else {
            orderOut(nil)
            completion?()
            return
        }
        layer.removeAllAnimations()
        guard animated else {
            layer.opacity = 0
            orderOut(nil)
            completion?()
            return
        }
        let animation = CAKeyframeAnimation(keyPath: "opacity")
        animation.values = [
            NSNumber(value: 1.0),
            NSNumber(value: Double(Animation.overlayAlpha)),
            NSNumber(value: 0.0)
        ]
        animation.keyTimes = [
            NSNumber(value: 0.0),
            NSNumber(value: 0.45),
            NSNumber(value: 1.0)
        ]
        animation.duration = Animation.totalDuration
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .easeInEaseOut)
        ]
        layer.opacity = 0
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            guard let self, self.animationToken == token else { return }
            self.orderOut(nil)
            completion?()
        }
        layer.add(animation, forKey: "opacityFadeOut")
        CATransaction.commit()
    }
}
