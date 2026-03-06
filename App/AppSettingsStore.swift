// MARK: - Settings Store
// Single source of truth for settings persistence and side effects.
import AppKit
import Combine
import OSLog

/// Observable settings store used across the app.
@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var settings: DimlySettings {
        didSet {
            persist(settings)
            applySideEffects(for: settings)
        }
    }

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "Settings")
    private var lastAppliedSettings: DimlySettings?
    private static let persistenceQueue = DispatchQueue(label: "com.punshnut.dimly.settings.persist", qos: .utility)

    /// Loads persisted settings and applies side effects immediately.
    init(initial: DimlySettings = DimlySettingsStore.load()) {
        self.settings = initial
        applySideEffects(for: initial)
    }

    /// Applies a mutation block while coalescing no-op updates.
    func update(_ edit: (inout DimlySettings) -> Void) {
        var copy = settings
        edit(&copy)
        guard copy != settings else { return } // avoid no-op writes that can spam cfprefsd
        settings = copy
    }

    /// Blocks until all queued async persistence work has completed.
    func flushPendingPersistence() {
        Self.persistenceQueue.sync {}
    }

    // MARK: - Private

    /// Persists settings asynchronously to avoid blocking UI.
    private func persist(_ settings: DimlySettings) {
        let snapshot = settings
        Self.persistenceQueue.async {
            DimlySettingsStore.save(snapshot)
        }
    }

    /// Applies system-side effects after settings updates.
    private func applySideEffects(for settings: DimlySettings) {
        // Avoid redundant system calls (e.g., failing SMAppService requests) when nothing changed.
        if lastAppliedSettings?.launchAtLogin != settings.launchAtLogin {
            LaunchAtLoginManager.setEnabled(settings.launchAtLogin)
        }
        if lastAppliedSettings?.hideDockIcon != settings.hideDockIcon {
            applyDockIconVisibility(hidden: settings.hideDockIcon)
        }
        if lastAppliedSettings?.appAppearancePreference != settings.appAppearancePreference {
            applyAppAppearance(settings.appAppearancePreference)
        }
        lastAppliedSettings = settings
        logger.debug("Settings applied: launchAtLogin=\(settings.launchAtLogin, privacy: .public) showMenuBarIcon=\(settings.showMenuBarIcon, privacy: .public) hideDockIcon=\(settings.hideDockIcon, privacy: .public) appearance=\(settings.appAppearancePreference.rawValue, privacy: .public)")
    }

    /// Updates app activation policy to show or hide the Dock icon.
    private func applyDockIconVisibility(hidden: Bool) {
        let policy: NSApplication.ActivationPolicy = hidden ? .accessory : .regular
        let app = NSApplication.shared
        if app.activationPolicy() != policy {
            _ = app.setActivationPolicy(policy)
        }
    }

    /// Updates AppKit appearance so non-SwiftUI surfaces match the selected mode.
    private func applyAppAppearance(_ preference: AppAppearancePreference) {
        let app = NSApplication.shared
        switch preference {
        case .system:
            app.appearance = NSAppearance(named: isSystemInDarkMode ? .darkAqua : .aqua)
        case .light:
            app.appearance = NSAppearance(named: .aqua)
        case .dark:
            app.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Reads the current system appearance preference from user defaults.
    private var isSystemInDarkMode: Bool {
        UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
    }
}
