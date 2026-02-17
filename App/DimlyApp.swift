// MARK: - Dimly Application Entry
// Wires the SwiftUI scenes, settings store, and background engine together.
import SwiftUI
import AppKit
import OSLog

/// Dimly entry point. Wires the settings store, engine, menu bar presence, and settings window.
@main
struct DimlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore: AppSettingsStore
    private let engine: DimlyEngine
    private let displayManager: DisplayManager
    private let displayLabelManager: DisplayLabelManager

    init() {
        DiagnosticsLogger.shared.log("App init starting", category: "app")
        DiagnosticsLogger.shared.startHeartbeat()
        DispatchQueue.main.async {
            DiagnosticsLogger.shared.log("Main queue async checkpoint", category: "app")
        }
        let store = AppSettingsStore()
        _settingsStore = StateObject(wrappedValue: store)
        let displayManager = DisplayManager()
        self.displayManager = displayManager
        self.engine = DimlyEngine(settingsStore: store, displayManager: displayManager)
        self.displayLabelManager = DisplayLabelManager(settingsStore: store, displayManager: displayManager)
        appDelegate.configureLauncher(
            settingsStore: store,
            displayManager: displayManager,
            engine: engine
        )
        appDelegate.configureSettings(
            settingsStore: store,
            displayManager: displayManager,
            engine: engine
        )
        DiagnosticsLogger.shared.log("Engine constructed", category: "app")
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: nil
        ) { [engine] _ in
            DiagnosticsLogger.shared.log("App will terminate", category: "app")
            Task { @MainActor in
                engine.cleanupBeforeExit()
            }
        }
    }

    /// Defines the menu bar and settings scenes.
    var body: some Scene {
        menuBarScene
        settingsScene
    }

    /// Menu bar extra hosting the main popover UI.
    private var menuBarScene: some Scene {
        // Show/hide without conditional SceneBuilder to avoid compiler crash.
        let showMenuBarBinding = Binding(
            get: { settingsStore.settings.showMenuBarIcon },
            set: { newValue in settingsStore.update { $0.showMenuBarIcon = newValue } }
        )

        return MenuBarExtra(
            String(localized: "Dimly"),
            systemImage: "display",
            isInserted: showMenuBarBinding
        ) {
            MenuBarContentView(
                settingsStore: settingsStore,
                displayManager: displayManager,
                blackoutManager: engine.blackoutManager,
                ddcManager: engine.ddcManager,
                profileManager: engine.profileManager,
                engine: engine,
                updaterController: appDelegate.updaterController,
                presentation: .menuBar
            )
        }
        .menuBarExtraStyle(.window)
    }

    /// Settings window scene.
    private var settingsScene: some Scene {
        Settings {
            SettingsRootView(
                settingsStore: settingsStore,
                displayManager: displayManager,
                profileManager: engine.profileManager,
                ddcManager: engine.ddcManager,
                blackoutManager: engine.blackoutManager,
                engine: engine
            )
        }
    }
}

/// AppKit delegate for main menu wiring and first-launch intro.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let updaterController = UpdaterController()
    static let introShownKey = "DimlyHasShownIntro.v1"
    private var introWindowController: IntroWindowController?
    private var launcherWindowController: LauncherWindowController?
    private var settingsWindowController: NSWindowController?
    private weak var settingsStore: AppSettingsStore?
    private weak var displayManager: DisplayManager?
    private weak var settingsEngine: DimlyEngine?
    private var isHandlingTermination = false

    /// Establishes the main menu and shows the intro if needed.
    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        showIntroIfNeeded()
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.configureMainMenu()
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let settingsEngine else {
            return .terminateNow
        }
        if isHandlingTermination {
            return .terminateLater
        }
        let fadeInEnabled = settingsStore?.settings.fadeInAnimationEnabled ?? true
        guard settingsEngine.blackoutManager.hasAnyOverlays else {
            return .terminateNow
        }
        isHandlingTermination = true
        settingsEngine.prepareForExit(animated: fadeInEnabled) {
            DispatchQueue.main.async {
                sender.reply(toApplicationShouldTerminate: true)
            }
        }
        return .terminateLater
    }

    func configureLauncher(
        settingsStore: AppSettingsStore,
        displayManager: DisplayManager,
        engine: DimlyEngine
    ) {
        guard launcherWindowController == nil else { return }
        launcherWindowController = LauncherWindowController(
            settingsStore: settingsStore,
            displayManager: displayManager,
            engine: engine,
            updaterController: updaterController
        )
        engine.onShowWindow = { [weak self] in
            self?.togglePrimaryWindow()
        }
        engine.onToggleWindow = { [weak self] in
            self?.togglePrimaryWindow()
        }
    }

    func configureSettings(
        settingsStore: AppSettingsStore,
        displayManager: DisplayManager,
        engine: DimlyEngine
    ) {
        self.settingsStore = settingsStore
        self.displayManager = displayManager
        self.settingsEngine = engine
    }



    /// Shows the intro window on first launch.
    private func showIntroIfNeeded() {
        showIntro(force: false)
    }

    /// Resets the "shown" flag and forces the intro to appear.
    func resetAndShowIntro() {
        UserDefaults.standard.set(false, forKey: Self.introShownKey)
        showIntro(force: true)
    }

    /// Presents the intro window when forced or not yet shown.
    private func showIntro(force: Bool) {
        if UserDefaults.standard.bool(forKey: Self.introShownKey) {
            if !force {
                return
            }
        }
        UserDefaults.standard.set(true, forKey: Self.introShownKey)
        let controller = IntroWindowController { [weak self] in
            self?.introWindowController = nil
        }
        introWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Builds the application menu (About, Settings, Updates, Quit).
    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.title = String(localized: "Dimly")
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutTitle = String(localized: "About Dimly")
        let aboutItem = NSMenuItem(
            title: aboutTitle,
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let settingsTitle = String(localized: "Settings...")
        let settingsItem = NSMenuItem(
            title: settingsTitle,
            action: NSSelectorFromString("showSettingsWindow:"),
            keyEquivalent: ","
        )
        appMenu.addItem(settingsItem)

        let updatesItem = NSMenuItem(
            title: String(localized: "Check for Updates..."),
            action: #selector(UpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updatesItem.target = updaterController
        appMenu.addItem(updatesItem)

        appMenu.addItem(.separator())

        let quitTitle = String(localized: "Quit Dimly")
        let quitItem = NSMenuItem(
            title: quitTitle,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        NSApp.mainMenu = mainMenu
    }

    @objc func showSettingsWindow(_ sender: Any?) {
        guard
            let settingsStore,
            let displayManager,
            let settingsEngine
        else { return }

        if settingsWindowController == nil {
            let rootView = SettingsRootView(
                settingsStore: settingsStore,
                displayManager: displayManager,
                profileManager: settingsEngine.profileManager,
                ddcManager: settingsEngine.ddcManager,
                blackoutManager: settingsEngine.blackoutManager,
                engine: settingsEngine
            )
            let hostingView = NSHostingView(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "Settings")
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbarStyle = .unifiedCompact
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.toolbar = NSToolbar(identifier: "SettingsToolbar")
            window.contentView = hostingView
            settingsWindowController = NSWindowController(window: window)
        }

        guard let window = settingsWindowController?.window else { return }
        adjustTrafficLights(for: window)
        center(window: window)
        window.alphaValue = 0
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }
    }

    private func center(window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: frame.midX - window.frame.width / 2,
            y: frame.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
    }

    private func adjustTrafficLights(for window: NSWindow) {
        guard let button = window.standardWindowButton(.closeButton),
              let container = button.superview
        else { return }
        var frame = container.frame
        frame.origin.x += 6
        container.setFrameOrigin(frame.origin)
    }

    /// Toggles the menu bar popup when available, otherwise falls back to launcher window.
    private func togglePrimaryWindow() {
        if toggleMenuBarWindowIfPossible() {
            return
        }
        launcherWindowController?.toggle()
    }

    /// Opens/closes the MenuBarExtra window through the status item when the icon is shown.
    @discardableResult
    private func toggleMenuBarWindowIfPossible() -> Bool {
        guard settingsStore?.settings.showMenuBarIcon == true else { return false }
        if let menuWindow = dimlyMenuBarWindow(),
           menuWindow.isVisible {
            menuWindow.orderOut(nil)
            return true
        }

        if let menuWindow = dimlyMenuBarWindow() {
            NSApp.activate(ignoringOtherApps: true)
            menuWindow.makeKeyAndOrderFront(nil)
            menuWindow.orderFrontRegardless()
            return true
        }
        return false
    }

    /// Finds Dimly's menu bar extra window without relying on private status item APIs.
    private func dimlyMenuBarWindow() -> NSWindow? {
        NSApp.windows.first { window in
            let className = NSStringFromClass(type(of: window))
            guard className.localizedCaseInsensitiveContains("MenuBarExtra") else {
                return false
            }
            return window.level == .statusBar || window.level == .popUpMenu
        }
    }

}
