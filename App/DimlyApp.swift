// MARK: - Dimly Application Entry
// App entry and scene wiring.
import SwiftUI
import AppKit
import OSLog

extension Notification.Name {
    static let dimlyOpenSettingsWindow = Notification.Name("DimlyOpenSettingsWindow")
}

/// Main app entry point.
@main
struct DimlyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var settingsStore: AppSettingsStore
    private let engine: DimlyEngine
    private let displayManager: DisplayManager
    private let displayLabelManager: DisplayLabelManager

    /// Builds the shared app graph early so SwiftUI scenes and AppKit delegates share one engine instance.
    init() {
        DiagnosticsLogger.shared.log("App init starting", category: "app")
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
        ) { [engine, store] _ in
            DiagnosticsLogger.shared.log("App will terminate", category: "app")
            Task { @MainActor in
                engine.cleanupBeforeExit()
                store.flushPendingPersistence()
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
        // Keep the scene structure stable and drive visibility through binding updates instead.
        let showMenuBarBinding = Binding(
            get: { settingsStore.settings.showMenuBarIcon },
            set: { newValue in settingsStore.update { $0.showMenuBarIcon = newValue } }
        )

        return MenuBarExtra(
            String(localized: "AppName"),
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
                nightShiftManager: engine.nightShiftManager,
                trueToneManager: engine.trueToneManager,
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
                engine: engine,
                scheduleManager: engine.scheduleManager,
                nightShiftManager: engine.nightShiftManager,
                trueToneManager: engine.trueToneManager,
                displayModeManager: engine.displayModeManager,
                colorProfileManager: engine.colorProfileManager,
                displayAppearanceManager: engine.displayAppearanceManager,
                lutManager: engine.lutManager
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
        NotificationCenter.default.addObserver(
            forName: .dimlyOpenSettingsWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.showSettingsWindow(nil)
            }
        }
    }

    /// Delays termination until overlay teardown completes.
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

    /// Initializes the standalone launcher controller and binds engine callbacks.
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

    /// Stores shared dependencies used later when opening the settings window.
    func configureSettings(
        settingsStore: AppSettingsStore,
        displayManager: DisplayManager,
        engine: DimlyEngine
    ) {
        self.settingsStore = settingsStore
        self.displayManager = displayManager
        self.settingsEngine = engine
    }



    /// Opens the intro window on first launch.
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
        guard let settingsStore, let displayManager else { return }
        UserDefaults.standard.set(true, forKey: Self.introShownKey)
        let controller = IntroWindowController(
            settingsStore: settingsStore,
            displayManager: displayManager
        ) { [weak self] in
            self?.introWindowController = nil
        }
        introWindowController = controller
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Configures the app menu (About, Settings, Updates, Quit).
    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        appMenuItem.title = String(localized: "AppName")
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let aboutTitle = String(localized: "AppAboutMenuTitle")
        let aboutItem = NSMenuItem(
            title: aboutTitle,
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())

        let settingsTitle = String(localized: "MenuSettingsItem")
        let settingsItem = NSMenuItem(
            title: settingsTitle,
            action: NSSelectorFromString("showSettingsWindow:"),
            keyEquivalent: ","
        )
        settingsItem.target = self
        appMenu.addItem(settingsItem)

        let updatesItem = NSMenuItem(
            title: String(localized: "MenuCheckUpdatesItem"),
            action: #selector(UpdaterController.checkForUpdates(_:)),
            keyEquivalent: ""
        )
        updatesItem.target = updaterController
        appMenu.addItem(updatesItem)

        appMenu.addItem(.separator())

        let quitTitle = String(localized: "MenuQuitItem")
        let quitItem = NSMenuItem(
            title: quitTitle,
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        appMenu.addItem(quitItem)

        NSApp.mainMenu = mainMenu
    }

    /// Lazily constructs and presents the singleton settings window.
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
                engine: settingsEngine,
                scheduleManager: settingsEngine.scheduleManager,
                nightShiftManager: settingsEngine.nightShiftManager,
                trueToneManager: settingsEngine.trueToneManager,
                displayModeManager: settingsEngine.displayModeManager,
                colorProfileManager: settingsEngine.colorProfileManager,
                displayAppearanceManager: settingsEngine.displayAppearanceManager,
                lutManager: settingsEngine.lutManager
            )
            let hostingView = NSHostingView(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 900, height: 580),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = String(localized: "AppSettingsTitle")
            window.titlebarAppearsTransparent = true
            window.titlebarSeparatorStyle = .none
            window.toolbarStyle = .unifiedCompact
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
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

    /// Centers a window on the screen under the pointer (or main screen fallback).
    private func center(window: NSWindow) {
        let mouseLocation = NSEvent.mouseLocation
        let screen = targetScreen(for: mouseLocation) ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = NSPoint(
            x: frame.midX - window.frame.width / 2,
            y: frame.midY - window.frame.height / 2
        )
        window.setFrameOrigin(origin)
    }

    /// Resolves the best screen for settings presentation, including cursor positions near display edges.
    private func targetScreen(for cursorLocation: NSPoint) -> NSScreen? {
        if let containing = NSScreen.screens.first(where: { screen in
            screen.frame.insetBy(dx: -1, dy: -1).contains(cursorLocation)
        }) {
            return containing
        }
        return NSScreen.screens.min { lhs, rhs in
            distanceSquared(from: cursorLocation, to: lhs.frame) < distanceSquared(from: cursorLocation, to: rhs.frame)
        }
    }

    /// Squared distance between a point and the nearest point in a rectangle.
    private func distanceSquared(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return (dx * dx) + (dy * dy)
    }

    /// Nudges traffic lights to match the custom titlebar spacing used by the app.
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

    /// Opens/closes the MenuBarExtra window via SwiftUI's own status item button so that
    /// SwiftUI's internal state stays in sync (avoids ghost highlights, double-open flashes,
    /// and missed onAppear/onDisappear lifecycle calls).
    @discardableResult
    private func toggleMenuBarWindowIfPossible() -> Bool {
        guard settingsStore?.settings.showMenuBarIcon == true else { return false }
        guard dimlyMenuBarWindow() != nil else { return false }
        NSApp.activate(ignoringOtherApps: true)
        if let button = dimlyStatusBarButton() {
            button.performClick(nil)
        } else {
            // Fallback: direct AppKit toggle when the button can't be located.
            if let w = dimlyMenuBarWindow(), w.isVisible {
                w.orderOut(nil)
            } else {
                dimlyMenuBarWindow()?.makeKeyAndOrderFront(nil)
            }
        }
        return true
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

    /// Locates the NSStatusBarButton owned by our MenuBarExtra so we can perform
    /// programmatic clicks that keep SwiftUI's MenuBarExtra state in sync.
    private func dimlyStatusBarButton() -> NSStatusBarButton? {
        for window in NSApp.windows {
            let cls = NSStringFromClass(type(of: window))
            guard cls.localizedCaseInsensitiveContains("StatusBar"),
                  !cls.localizedCaseInsensitiveContains("MenuBarExtra") else { continue }
            if let button = firstStatusBarButton(in: window.contentView) { return button }
        }
        return nil
    }

    private func firstStatusBarButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let b = view as? NSStatusBarButton { return b }
        for sub in view.subviews {
            if let b = firstStatusBarButton(in: sub) { return b }
        }
        return nil
    }

}
