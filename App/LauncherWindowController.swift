// MARK: - Launcher Window
// Hosts the main Dimly controls in a standalone window for global hotkey access.
import AppKit
import SwiftUI

@MainActor
final class LauncherWindowController: NSWindowController, NSWindowDelegate {
    private let settingsStore: AppSettingsStore
    private let displayManager: DisplayManager
    private let engine: DimlyEngine
    private let updaterController: UpdaterController

    /// Builds the standalone launcher window that mirrors the menu bar content for hotkey-driven access.
    init(
        settingsStore: AppSettingsStore,
        displayManager: DisplayManager,
        engine: DimlyEngine,
        updaterController: UpdaterController
    ) {
        self.settingsStore = settingsStore
        self.displayManager = displayManager
        self.engine = engine
        self.updaterController = updaterController

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = String(localized: "AppName")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.center()
        window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])

        let rootView = MenuBarContentView(
            settingsStore: settingsStore,
            displayManager: displayManager,
            blackoutManager: engine.blackoutManager,
            ddcManager: engine.ddcManager,
            profileManager: engine.profileManager,
            engine: engine,
            nightShiftManager: engine.nightShiftManager,
            trueToneManager: engine.trueToneManager,
            updaterController: updaterController,
            presentation: .window
        )
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = window.contentView?.bounds ?? .zero
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView

        super.init(window: window)
        window.delegate = self
    }

    /// Storyboard/coder construction is unsupported because the launcher window is assembled in code.
    required init?(coder: NSCoder) {
        nil
    }

    /// Toggles the standalone launcher window visibility.
    func toggle() {
        guard let window else { return }
        if window.isVisible {
            window.orderOut(nil)
        } else {
            showLauncherWindow()
        }
    }

    /// Shows and activates the launcher window.
    func showLauncherWindow() {
        guard let window else { return }
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
