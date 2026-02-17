// MARK: - Intro Window Controller
// Hosts the first-launch introduction window.
import AppKit
import SwiftUI

/// Hosts the first-launch intro SwiftUI view inside an AppKit window.
final class IntroWindowController: NSWindowController, NSWindowDelegate {
    private let onDismiss: () -> Void
    private static let contentWidth: CGFloat = 520

    /// Creates the intro window and wires a dismissal callback.
    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 100),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true

        let rootView = IntroWindowView { [weak window] in
            window?.close()
        }
        .frame(width: Self.contentWidth)
        let hostingView = NSHostingView(rootView: rootView)
        let fittingSize = hostingView.fittingSize

        window.setContentSize(fittingSize)
        window.center()
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) {
        return nil
    }

    /// NSWindowDelegate hook used to notify the owner when the window closes.
    func windowWillClose(_ notification: Notification) {
        onDismiss()
    }
}
