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
                updaterController: appDelegate.updaterController
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

}
