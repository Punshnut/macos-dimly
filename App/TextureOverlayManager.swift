// MARK: - Texture Overlay Manager
// Lifecycle manager for per-display texture overlay windows. Mirrors BlackoutManager's
// window pattern (see BlackoutWindow/DimOverlayWindow) but paints a tiled, relief-shaded
// material pattern instead of solid black, and is independent of blackout/dim state.
import AppKit
import QuartzCore
import Combine
import OSLog

/// Borderless, non-interactive overlay window that paints a tiled texture pattern.
final class TextureOverlayWindow: NSWindow {
    var animationDuration: TimeInterval = 0.2

    private final class TextureOverlayView: NSView {
        var patternImage: NSImage? {
            didSet { needsDisplay = true; layer?.setNeedsDisplay() }
        }
        override var wantsUpdateLayer: Bool { true }
        override func updateLayer() {
            layer?.backgroundColor = patternImage.map { NSColor(patternImage: $0).cgColor } ?? nil
        }
    }

    private let overlayView = TextureOverlayView()
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
        alphaValue = 1
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        overlayView.wantsLayer = true
        overlayView.layer?.opacity = 0
        overlayView.autoresizingMask = [.width, .height]
        contentView = overlayView
        update(screen: screen)
    }

    func update(screen: NSScreen) {
        setFrame(screen.frame, display: true)
        overlayView.frame = CGRect(origin: .zero, size: screen.frame.size)
    }

    /// Sets the tiled texture pattern shown by this overlay. Passing `nil` clears it.
    func setPattern(_ image: NSImage?) {
        overlayView.patternImage = image
        overlayView.needsDisplay = true
    }

    /// Sets the CALayer compositing filter name used to blend with what's underneath
    /// (e.g. "multiplyBlendMode"), or `nil` for normal compositing.
    func setBlendMode(_ compositingFilterName: String?) {
        overlayView.layer?.compositingFilter = compositingFilterName
    }

    /// Sets the overlay opacity (0-1), matching DimOverlayWindow's vsync-committed technique.
    func setOpacity(_ opacity: CGFloat, animated: Bool) {
        let clamped = max(0, min(1, opacity))
        guard clamped > 0 else {
            hide(animated: animated)
            return
        }
        orderFrontRegardless()
        guard animated && animationDuration > 0 else {
            overlayView.layer?.opacity = Float(clamped)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlayView.animator().alphaValue = clamped
        }
    }

    func hide(animated: Bool) {
        animationToken += 1
        guard animated && animationDuration > 0 else {
            overlayView.layer?.opacity = 0
            orderOut(nil)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = animationDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            overlayView.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                self?.orderOut(nil)
            }
        }
    }
}

/// Manages per-display texture overlay windows, independent of blackout/dim state.
@MainActor
final class TextureOverlayManager: ObservableObject {
    private let displayManager: DisplayManager
    private let textureManager: TextureManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "TextureOverlay")
    private var windows: [String: TextureOverlayWindow] = [:] // keyed by stableIdentity
    private var activeState: [String: (entryID: UUID, opacity: Double, blendMode: TextureBlendMode, tileScale: Double)] = [:]
    private var displayChangeToken: AnyCancellable?

    var transitionSpeedMultiplier: Double = 1.0 {
        didSet {
            windows.values.forEach { $0.animationDuration = 0.2 * transitionSpeedMultiplier }
        }
    }

    init(displayManager: DisplayManager, textureManager: TextureManager) {
        self.displayManager = displayManager
        self.textureManager = textureManager
        displayChangeToken = displayManager.$displays.sink { [weak self] displays in
            self?.reconcileDisplays(displays)
        }
    }

    /// Applies (or clears, when `entry` is nil) a texture overlay for the given display.
    func applyTexture(_ entry: TextureEntry?, opacity: Double, blendMode: TextureBlendMode, tileScale: Double, to display: DisplayInfo) {
        guard let entry else {
            activeState.removeValue(forKey: display.stableIdentity)
            windows[display.stableIdentity]?.hide(animated: true)
            return
        }
        activeState[display.stableIdentity] = (entry.id, opacity, blendMode, tileScale)
        render(entry: entry, opacity: opacity, blendMode: blendMode, tileScale: tileScale, for: display)
    }

    /// Cheap path for opacity-only changes (e.g. slider drags) - doesn't re-render the tile.
    func setOpacity(_ opacity: Double, for display: DisplayInfo) {
        guard var state = activeState[display.stableIdentity] else { return }
        state.opacity = opacity
        activeState[display.stableIdentity] = state
        windows[display.stableIdentity]?.setOpacity(CGFloat(opacity), animated: false)
    }

    /// Cheap path for blend-mode-only changes - applies via CALayer.compositingFilter.
    func setBlendMode(_ blendMode: TextureBlendMode, for display: DisplayInfo) {
        guard var state = activeState[display.stableIdentity] else { return }
        state.blendMode = blendMode
        activeState[display.stableIdentity] = state
        windows[display.stableIdentity]?.setBlendMode(blendMode.ciCompositingFilterName)
    }

    /// Live visual-only tile-scale preview during a slider drag - re-renders the tile (cheap,
    /// since `TextureRenderer` no longer re-shades for a scale change) but does **not** write
    /// `activeState`, so it never gets persisted; the caller commits separately on gesture end.
    func previewTileScale(_ tileScale: Double, entry: TextureEntry, opacity: Double, blendMode: TextureBlendMode, for display: DisplayInfo) {
        render(entry: entry, opacity: opacity, blendMode: blendMode, tileScale: tileScale, for: display)
    }

    private func render(entry: TextureEntry, opacity: Double, blendMode: TextureBlendMode, tileScale: Double, for display: DisplayInfo) {
        guard let screen = screen(for: display.displayID) else { return }
        let window = window(for: display, screen: screen)
        let backingScale = screen.backingScaleFactor
        let tile = TextureRenderer.tileImage(for: entry, manager: textureManager, tileScale: tileScale, backingScale: backingScale)
        window.setPattern(tile)
        window.setBlendMode(blendMode.ciCompositingFilterName)
        window.setOpacity(CGFloat(opacity), animated: true)
    }

    /// Shows a raw, not-yet-saved image (e.g. a Texture Playground compile result) on every
    /// given display without touching `activeState`/persisted settings - purely visual, for
    /// live-previewing a shader while it's being written. The normal way back to real state
    /// is `applyTexture(...)` per display (e.g. via `DimlyEngine.restoreAllTextureOverlays()`),
    /// which overwrites whatever preview pattern is currently showing.
    func previewImage(_ image: CGImage?, opacity: Double, blendMode: TextureBlendMode, tileScale: Double, on displays: [DisplayInfo]) {
        for display in displays {
            guard let screen = screen(for: display.displayID) else { continue }
            let window = window(for: display, screen: screen)
            guard let image else {
                window.hide(animated: false)
                continue
            }
            let backingScale = screen.backingScaleFactor
            let targetWidth = max(1, CGFloat(image.width) * CGFloat(tileScale))
            let targetHeight = max(1, CGFloat(image.height) * CGFloat(tileScale))
            let tile = NSImage(size: NSSize(width: targetWidth / backingScale, height: targetHeight / backingScale))
            tile.addRepresentation(NSBitmapImageRep(cgImage: image))
            window.setPattern(tile)
            window.setBlendMode(blendMode.ciCompositingFilterName)
            window.setOpacity(CGFloat(opacity), animated: false)
        }
    }

    /// Gets or creates the overlay window for a display, bound to its current `NSScreen`.
    private func window(for display: DisplayInfo, screen: NSScreen) -> TextureOverlayWindow {
        let window = windows[display.stableIdentity] ?? {
            let newWindow = TextureOverlayWindow(screen: screen)
            newWindow.animationDuration = 0.2 * transitionSpeedMultiplier
            windows[display.stableIdentity] = newWindow
            return newWindow
        }()
        window.update(screen: screen)
        return window
    }

    private func reconcileDisplays(_ displays: [DisplayInfo]) {
        let liveIDs = Set(displays.map(\.stableIdentity))
        let stale = windows.keys.filter { !liveIDs.contains($0) }
        for key in stale {
            windows[key]?.hide(animated: false)
            windows[key]?.close()
            windows.removeValue(forKey: key)
        }

        var byIdentity: [String: DisplayInfo] = [:]
        for display in displays { byIdentity[display.stableIdentity] = display }
        for (identity, state) in activeState {
            guard let display = byIdentity[identity],
                  let entry = textureManager.library.first(where: { $0.id == state.entryID }) else { continue }
            render(entry: entry, opacity: state.opacity, blendMode: state.blendMode, tileScale: state.tileScale, for: display)
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
}
