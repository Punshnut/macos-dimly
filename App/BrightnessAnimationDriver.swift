import QuartzCore
import AppKit

/// Drives brightness animations synchronized to each display's own refresh rate.
///
/// Each animation is tied to an NSScreen. A separate CADisplayLink is created per
/// unique screen so a 90 Hz display gets 90 ticks/s while a 60 Hz display gets 60,
/// preventing the hold-step pattern that appears when one global link runs at the
/// lowest common refresh rate.
@MainActor
final class BrightnessAnimationDriver {

    struct Animation {
        let screenKey: ObjectIdentifier   // which display link drives this animation
        let startTime: CFTimeInterval
        let duration: CFTimeInterval
        let onUpdate: (Double) -> Void    // receives eased progress 0...1
        let onComplete: () -> Void
    }

    private var animations: [String: Animation] = [:]
    private var displayLinks: [ObjectIdentifier: CADisplayLink] = [:]
    // Keep bridges alive — CADisplayLink holds a weak reference to its target.
    private var bridges: [ObjectIdentifier: DisplayLinkBridge] = [:]

    // MARK: - Public API

    func start(
        id: String,
        screen: NSScreen?,
        duration: CFTimeInterval,
        onUpdate: @escaping @MainActor (Double) -> Void,
        onComplete: @escaping @MainActor () -> Void
    ) {
        let targetScreen = screen ?? NSScreen.main
        let screenKey = targetScreen.map(ObjectIdentifier.init) ?? ObjectIdentifier(NSScreen.self)

        animations[id] = Animation(
            screenKey: screenKey,
            startTime: CACurrentMediaTime(),
            duration: duration,
            onUpdate: onUpdate,
            onComplete: onComplete
        )

        if displayLinks[screenKey] == nil {
            if let s = targetScreen {
                let bridge = DisplayLinkBridge(driver: self, screenKey: screenKey)
                let link = s.displayLink(target: bridge, selector: #selector(DisplayLinkBridge.tick(_:)))
                link.add(to: RunLoop.main, forMode: RunLoop.Mode.common)
                displayLinks[screenKey] = link
                bridges[screenKey] = bridge
            } else {
                // No screen — flush immediately.
                flushAnimations(for: screenKey)
            }
        }
    }

    func cancel(id: String) {
        guard let anim = animations.removeValue(forKey: id) else { return }
        stopLinkIfIdleForScreen(anim.screenKey)
    }

    func cancelAll() {
        animations.removeAll()
        displayLinks.values.forEach { $0.invalidate() }
        displayLinks.removeAll()
        bridges.removeAll()
    }

    // MARK: - Internal tick (called by DisplayLinkBridge)

    fileprivate func tick(timestamp: CFTimeInterval, screenKey: ObjectIdentifier) {
        let snapshot = animations.filter { $0.value.screenKey == screenKey }
        for (id, anim) in snapshot {
            let raw = anim.duration > 0 ? min(1.0, (timestamp - anim.startTime) / anim.duration) : 1.0
            anim.onUpdate(easeInOut(raw))
            if raw >= 1.0 {
                animations.removeValue(forKey: id)
                anim.onComplete()
            }
        }
        stopLinkIfIdleForScreen(screenKey)
    }

    // MARK: - Private helpers

    private func flushAnimations(for screenKey: ObjectIdentifier) {
        let targets = animations.filter { $0.value.screenKey == screenKey }
        targets.keys.forEach { animations.removeValue(forKey: $0) }
        targets.values.forEach { anim in
            anim.onUpdate(1.0)
            anim.onComplete()
        }
    }

    private func stopLinkIfIdleForScreen(_ key: ObjectIdentifier) {
        guard animations.values.allSatisfy({ $0.screenKey != key }) else { return }
        displayLinks[key]?.invalidate()
        displayLinks.removeValue(forKey: key)
        bridges.removeValue(forKey: key)
    }

    /// Cubic easeInOut — smooth acceleration and deceleration.
    private func easeInOut(_ t: Double) -> Double {
        t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}

// MARK: - DisplayLinkBridge

// NSScreen.displayLink(target:selector:) requires an NSObject target.
// Uses MainActor.assumeIsolated — the link fires on RunLoop.main so we are
// already on the main thread; no Task queuing burst is introduced.
private final class DisplayLinkBridge: NSObject, @unchecked Sendable {
    private weak var driver: BrightnessAnimationDriver?
    private let screenKey: ObjectIdentifier

    init(driver: BrightnessAnimationDriver, screenKey: ObjectIdentifier) {
        self.driver = driver
        self.screenKey = screenKey
    }

    @objc func tick(_ link: CADisplayLink) {
        guard let driver else { link.invalidate(); return }
        let timestamp = link.targetTimestamp
        let key = screenKey
        MainActor.assumeIsolated { driver.tick(timestamp: timestamp, screenKey: key) }
    }
}
