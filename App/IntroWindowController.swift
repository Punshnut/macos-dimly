// MARK: - Intro Window Controller
// AppKit host for the intro window.
import AppKit
import SwiftUI
import Combine

/// Window controller that hosts `IntroWindowView`.
@MainActor
final class IntroWindowController: NSWindowController, NSWindowDelegate {
    private let onDismiss: () -> Void
    private weak var settingsStore: AppSettingsStore?
    private weak var displayManager: DisplayManager?
    /// Mirror of the SwiftUI toggle — updated via Binding before windowWillClose fires.
    private var pendingIncludeInternal: Bool = true
    /// Weak ref to the hosting view so we can query fittingSize after displays load.
    private weak var hostingView: NSView?
    /// Cancelled in windowWillClose so the resize never fires after the window is gone.
    private var displaysCancellable: AnyCancellable?

    private static let contentWidth: CGFloat = 520

    /// Creates the intro window, sets up glass background, and wires the internal-monitor toggle.
    init(
        settingsStore: AppSettingsStore,
        displayManager: DisplayManager,
        initialPage: IntroPage = .welcome,
        whatsNewFeatures: [WhatsNewFeature] = [],
        onDismiss: @escaping () -> Void
    ) {
        self.onDismiss = onDismiss
        self.settingsStore = settingsStore
        self.displayManager = displayManager

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 100),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear

        // Glass background behind the SwiftUI content
        let visualEffect = NSVisualEffectView()
        visualEffect.material = .underWindowBackground
        visualEffect.blendingMode = .behindWindow
        visualEffect.state = .active
        window.contentView = visualEffect

        super.init(window: window)
        window.delegate = self

        let includeBinding = Binding<Bool>(
            get: { [weak self] in self?.pendingIncludeInternal ?? true },
            set: { [weak self] value in self?.pendingIncludeInternal = value }
        )

        let rootView = IntroWindowView(
            onDismiss: { [weak window] in window?.close() },
            displayManager: displayManager,
            includeInternalMonitor: includeBinding,
            initialPage: initialPage,
            whatsNewFeatures: whatsNewFeatures,
            onPageChange: { [weak self] in
                Task { @MainActor [weak self] in
                    self?.resizeToFitContent()
                }
            }
        )
        .frame(width: Self.contentWidth)

        // Plain NSHostingView — no sizingOptions. Combining sizingOptions = .preferredContentSize
        // with autoresizingMask = [.width, .height] creates a constraint loop that crashes.
        let hv = NSHostingView(rootView: rootView)
        self.hostingView = hv
        hv.frame = visualEffect.bounds
        hv.autoresizingMask = [.width, .height]
        visualEffect.addSubview(hv)

        // Size the window to the SwiftUI ideal size before it appears.
        visualEffect.layoutSubtreeIfNeeded()
        let initialSize = hv.fittingSize
        window.setContentSize(initialSize.height > 0 ? initialSize : CGSize(width: Self.contentWidth, height: 450))
        window.center()

        // Display metadata loads off-thread; watch for the first time a built-in display appears
        // and smoothly expand the window to accommodate the internal-monitor card.
        displaysCancellable = displayManager.$displays
            .dropFirst()
            .filter { $0.contains(where: { $0.isBuiltin }) }
            .prefix(1)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.resizeToFitContent()
                }
            }
    }

    required init?(coder: NSCoder) { return nil }

    /// Re-measures the SwiftUI content and smoothly resizes the window to fit — used both when
    /// the built-in display card appears and when the user switches between intro pages.
    private func resizeToFitContent() {
        guard let win = window, win.isVisible, let hv = hostingView else { return }
        let newSize = hv.fittingSize
        guard newSize.height > 0,
              abs(newSize.height - (win.contentView?.bounds.height ?? 0)) > 1 else { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            win.animator().setContentSize(newSize)
        }
    }

    /// Writes the toggle choice to settings when the window closes (either Get Started or the X button).
    func windowWillClose(_ notification: Notification) {
        displaysCancellable = nil
        if pendingIncludeInternal, let displayManager {
            let ids = displayManager.displays
                .filter { $0.isBuiltin }
                .map { $0.stableIdentity }
            settingsStore?.update { settings in
                for id in ids where !settings.menuBarIncludedInternalDisplayIDs.contains(id) {
                    settings.menuBarIncludedInternalDisplayIDs.append(id)
                }
            }
        }
        onDismiss()
    }
}
