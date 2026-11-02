// MARK: - Menu Bar Support Views
// Window anchoring, press-and-hold buttons and glass helpers used by the menu bar popover.
import AppKit
import SwiftUI

struct MenuBarWindowAnchorLock: NSViewRepresentable {
    let isEnabled: Bool
    let targetContentSize: CGSize

    /// Creates a coordinator that keeps the menu bar window pinned to its original top edge while resizing.
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    /// Installs an invisible AppKit hook so SwiftUI can react to the hosting window's resize lifecycle.
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.postsFrameChangedNotifications = true
        MainActor.assumeIsolated {
            context.coordinator.attach(
                view: view,
                to: Self.findMenuBarExtraWindow(from: view.window),
                isEnabled: isEnabled,
                targetContentSize: targetContentSize
            )
        }
        return view
    }

    /// Reattaches the coordinator whenever SwiftUI moves this representable into a different window.
    func updateNSView(_ nsView: NSView, context: Context) {
        MainActor.assumeIsolated {
            context.coordinator.attach(
                view: nsView,
                to: Self.findMenuBarExtraWindow(from: nsView.window),
                isEnabled: isEnabled,
                targetContentSize: targetContentSize
            )
        }
    }

    /// Resolves the real MenuBarExtra window instead of transient SwiftUI hosting windows.
    private static func findMenuBarExtraWindow(from candidate: NSWindow?) -> NSWindow? {
        if let candidate, isMenuBarExtraWindow(candidate) {
            return candidate
        }
        return NSApp.windows.first(where: isMenuBarExtraWindow)
    }

    private static func isMenuBarExtraWindow(_ window: NSWindow) -> Bool {
        let className = NSStringFromClass(type(of: window))
        guard className.localizedCaseInsensitiveContains("MenuBarExtra") else {
            return false
        }
        return window.level == .statusBar || window.level == .popUpMenu
    }

    /// Removes AppKit observers when SwiftUI tears down the backing view.
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        private weak var anchorView: NSView?
        private weak var window: NSWindow?
        private var isEnabled = false
        private var lockedTopY: CGFloat?
        private var lockedScreen: NSScreen?
        private var targetContentSize: CGSize = .zero
        private var isSyncingWindowFrame = false

        /// Starts observing the current hosting window and captures the top edge to preserve menu bar anchoring.
        func attach(
            view: NSView,
            to window: NSWindow?,
            isEnabled: Bool,
            targetContentSize: CGSize
        ) {
            let wasEnabled = self.isEnabled
            let previousLockedTopY = lockedTopY
            let previousLockedScreen = lockedScreen
            if anchorView !== view {
                unregisterViewObservers()
                anchorView = view
                registerViewObservers(for: view)
            }
            guard let window else { return }

            if self.window !== window {
                unregisterWindowObservers()
                self.window = window
                registerWindowObservers(for: window)

                if let previousLockedTopY,
                   let previousLockedScreen,
                   window.screen === previousLockedScreen {
                    lockedTopY = previousLockedTopY
                    lockedScreen = previousLockedScreen
                } else {
                    lockedTopY = nil
                    lockedScreen = nil
                }
            }

            self.isEnabled = isEnabled
            self.targetContentSize = targetContentSize

            if isEnabled {
                // Re-capture when first enabled, after a reset, or when the panel has moved to a
                // different screen (e.g. opened on a fullscreen monitor after being on another screen).
                // Never re-capture on repeat calls for the same screen - later SwiftUI animation
                // frames may fire updateNSView after macOS has already drifted the window upward.
                if !wasEnabled || lockedTopY == nil || window.screen !== lockedScreen {
                    lockedTopY = window.frame.maxY
                    lockedScreen = window.screen
                }
                syncWindowFrame(force: true)
            } else {
                lockedTopY = nil
                lockedScreen = nil
            }
        }

        /// Stops observing the current window and clears any cached anchor state.
        func detach() {
            unregisterWindowObservers()
            unregisterViewObservers()
            anchorView = nil
            window = nil
            lockedTopY = nil
            lockedScreen = nil
            isEnabled = false
            targetContentSize = .zero
        }

        @objc
        private func handleResizeNotification(_ notification: Notification) {
            syncWindowFrame()
        }

        @objc
        private func handleViewFrameDidChange(_ notification: Notification) {
            syncWindowFrame()
        }

        private func registerWindowObservers(for window: NSWindow) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleResizeNotification(_:)),
                name: NSWindow.didResizeNotification,
                object: window
            )
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleResizeNotification(_:)),
                name: NSWindow.didMoveNotification,
                object: window
            )
        }

        private func unregisterWindowObservers() {
            guard let window else { return }
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didResizeNotification,
                object: window
            )
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didMoveNotification,
                object: window
            )
        }

        private func registerViewObservers(for view: NSView) {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleViewFrameDidChange(_:)),
                name: NSView.frameDidChangeNotification,
                object: view
            )
        }

        private func unregisterViewObservers() {
            guard let anchorView else { return }
            NotificationCenter.default.removeObserver(
                self,
                name: NSView.frameDidChangeNotification,
                object: anchorView
            )
        }

        /// Keeps the menu bar window frame in sync with the measured SwiftUI content size.
        private func syncWindowFrame(force: Bool = false) {
            guard !isSyncingWindowFrame else { return }
            isSyncingWindowFrame = true
            defer { isSyncingWindowFrame = false }

            guard isEnabled, let window else { return }
            guard let targetContentSize = resolvedTargetContentSize(in: window) else { return }

            // If the window moved to a different screen the stored anchor belongs to the old
            // screen. Adopt the current position as the new anchor and skip any correction so
            // the panel stays where macOS placed it on the new screen.
            if window.screen !== lockedScreen {
                lockedTopY = window.frame.maxY
                lockedScreen = window.screen
                return
            }

            let topY = lockedTopY ?? window.frame.maxY
            lockedTopY = topY

            let currentFrame = window.frame
            let currentContentRect = window.contentRect(forFrameRect: currentFrame)
            let desiredContentRect = CGRect(origin: .zero, size: targetContentSize)
            let desiredFrameSize = window.frameRect(forContentRect: desiredContentRect).size
            let targetY = topY - desiredFrameSize.height

            let widthDelta = abs(currentContentRect.width - targetContentSize.width)
            let heightDelta = abs(currentContentRect.height - targetContentSize.height)
            let yDelta = abs(currentFrame.origin.y - targetY)
            guard force || widthDelta > 0.5 || heightDelta > 0.5 || yDelta > 0.5 else { return }

            var frame = currentFrame
            frame.size = desiredFrameSize
            frame.origin.y = targetY
            let isGrowing = desiredFrameSize.width > currentFrame.width + 0.5 || desiredFrameSize.height > currentFrame.height + 0.5
            window.setFrame(frame, display: isGrowing, animate: false)
            if isGrowing {
                window.contentView?.needsLayout = true
                window.contentView?.layoutSubtreeIfNeeded()
                window.contentView?.displayIfNeeded()
            }
        }

        private func resolvedTargetContentSize(in window: NSWindow) -> CGSize? {
            if let fittingSubviewSize = window.contentView?.subviews.first?.fittingSize,
               fittingSubviewSize.width > 0.5,
               fittingSubviewSize.height > 0.5 {
                return fittingSubviewSize
            }

            if let fittingContentViewSize = window.contentView?.fittingSize,
               fittingContentViewSize.width > 0.5,
               fittingContentViewSize.height > 0.5 {
                return fittingContentViewSize
            }

            let measured = targetContentSize
            if measured.width > 0.5, measured.height > 0.5 {
                return measured
            }

            if let anchorView {
                let boundsSize = anchorView.bounds.size
                if boundsSize.width > 0.5, boundsSize.height > 0.5 {
                    return boundsSize
                }

                if let superviewSize = anchorView.superview?.bounds.size,
                   superviewSize.width > 0.5,
                   superviewSize.height > 0.5 {
                    return superviewSize
                }
            }

            return nil
        }
    }
}

/// Tap fires once via a real `Button` (so it's always hit-tested reliably, even inside the
/// menu bar's `NSPopover`); holding repeats after 1 s at 0.12 s intervals, driven by a
/// `simultaneousGesture` so it never gates or delays the primary tap.
struct BrightnessHoldButton<Label: View>: View {
    let action: () -> Void
    let label: () -> Label

    @State private var repeatTask: Task<Void, Never>?
    @State private var isHeld = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(action: @escaping () -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.action = action
        self.label = label
    }

    private func beginHold() {
        guard repeatTask == nil else { return }
        isHeld = true
        repeatTask = Task {
            do {
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 s before repeat
                while !Task.isCancelled {
                    action()
                    try await Task.sleep(nanoseconds: 120_000_000) // ~8 steps/s
                }
            } catch {}
        }
    }

    private func endHold() {
        isHeld = false
        repeatTask?.cancel()
        repeatTask = nil
    }

    var body: some View {
        Button(action: action) {
            label()
        }
        .buttonStyle(.plain)
        .scaleEffect(isHeld && !reduceMotion ? 0.8 : 1)
        .opacity(isHeld ? 0.78 : 1)
        .animation(reduceMotion ? nil : DimlyMotion.poppySpring, value: isHeld)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in beginHold() }
                .onEnded { _ in endHold() }
        )
    }
}

/// Button style that keeps icon colors stable during pressed state (no accent flash).
struct StaticIconButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Applies press feedback without changing icon tint semantics.
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.84 : 1)
            .animation(reduceMotion ? nil : DimlyMotion.quickSpring, value: configuration.isPressed)
    }
}


/// Applies the legacy popover backdrop only where the system does not provide glass chrome.
struct MenuBarPanelBackgroundModifier: ViewModifier {
    let isMenuBar: Bool

    func body(content: Content) -> some View {
        if isMenuBar {
            content.dimlyPanelBackground()
        } else {
            content
        }
    }
}


/// Glass track behind the mode switch (macOS 26+); older systems keep the tinted capsule fill.
struct ModeSwitchTrackGlass: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.dimlyGlassSurface(cornerRadius: 100, interactive: false)
        } else {
            content
        }
    }
}

/// Edge treatment for smart-button tiles: a soft specular rim on macOS 26+, a hairline before.
struct DimlySmartTileEdge: View {
    let cornerRadius: CGFloat
    let fallbackStroke: Color
    let dark: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26, *), !reduceTransparency {
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(dark ? 0.38 : 0.55), Color.white.opacity(0.04)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
        } else {
            shape.stroke(fallbackStroke, lineWidth: 1)
        }
    }
}
