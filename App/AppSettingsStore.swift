// MARK: - Settings Store
// Central store for persisted settings and their app-level side effects.
import AppKit
import Combine
import OSLog
import SwiftUI

/// Observable settings store used across the app.
@MainActor
final class AppSettingsStore: ObservableObject {
    @Published var settings: DimlySettings {
        didSet {
            persist(settings)
            applySideEffects(for: settings)
        }
    }

    /// The concrete color scheme currently in effect. Always a definite value — never nil —
    /// so SwiftUI views can bind directly and receive instant updates via @Published.
    @Published private(set) var effectiveColorScheme: ColorScheme = .light

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "Settings")
    private var lastAppliedSettings: DimlySettings?
    private static let persistenceQueue = DispatchQueue(label: "com.punshnut.dimly.settings.persist", qos: .utility)
    private var systemAppearanceObserver: NSObjectProtocol?

    /// Loads persisted settings and applies side effects immediately.
    init(initial: DimlySettings = DimlySettingsStore.load()) {
        self.settings = initial
        applySideEffects(for: initial)
    }

    /// Applies a mutation block while coalescing no-op updates.
    func update(_ edit: (inout DimlySettings) -> Void) {
        var copy = settings
        edit(&copy)
        guard copy != settings else { return } // Skip identical writes to avoid unnecessary preference churn.
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
        // Avoid repeating system-level operations when the effective setting has not changed.
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

    /// Updates AppKit appearance and effectiveColorScheme for the selected preference.
    private func applyAppAppearance(_ preference: AppAppearancePreference) {
        if let observer = systemAppearanceObserver {
            DistributedNotificationCenter.default().removeObserver(observer)
            systemAppearanceObserver = nil
        }

        switch preference {
        case .system:
            applySystemAppearanceNow()
            // Keep effectiveColorScheme in sync whenever macOS changes its theme.
            systemAppearanceObserver = DistributedNotificationCenter.default().addObserver(
                forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.settings.appAppearancePreference == .system else { return }
                    self.applySystemAppearanceNow()
                }
            }
        case .light:
            effectiveColorScheme = .light
            NSApplication.shared.appearance = NSAppearance(named: .aqua)
        case .dark:
            effectiveColorScheme = .dark
            NSApplication.shared.appearance = NSAppearance(named: .darkAqua)
        }
    }

    /// Resolves and applies the current OS appearance, updating both NSApp and effectiveColorScheme.
    private func applySystemAppearanceNow() {
        let isDark = UserDefaults.standard.string(forKey: "AppleInterfaceStyle") == "Dark"
        effectiveColorScheme = isDark ? .dark : .light
        NSApplication.shared.appearance = NSAppearance(named: isDark ? .darkAqua : .aqua)
    }
}
