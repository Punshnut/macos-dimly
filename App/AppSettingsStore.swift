// MARK: - Settings Store
// Centralizes persistence and side effects for user preferences so SwiftUI views
// can bind to a single observable source of truth.
import AppKit
import Combine
import OSLog

/// Observable wrapper around `DimlySettings` so SwiftUI views can react to changes.
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

    // MARK: - Private

    /// Persists settings asynchronously to avoid blocking UI.
    private func persist(_ settings: DimlySettings) {
        let snapshot = settings
        Self.persistenceQueue.async {
            DimlySettingsStore.save(snapshot)
        }
    }

    /// Apply non-UI side effects so that toggles immediately change system behavior.
    private func applySideEffects(for settings: DimlySettings) {
        // Avoid redundant system calls (e.g., failing SMAppService requests) when nothing changed.
        if lastAppliedSettings?.launchAtLogin != settings.launchAtLogin {
            LaunchAtLoginManager.setEnabled(settings.launchAtLogin)
        }
        if lastAppliedSettings?.hideDockIcon != settings.hideDockIcon {
            applyDockIconVisibility(hidden: settings.hideDockIcon)
        }
        lastAppliedSettings = settings
        logger.debug("Settings applied: launchAtLogin=\(settings.launchAtLogin, privacy: .public) showMenuBarIcon=\(settings.showMenuBarIcon, privacy: .public) hideDockIcon=\(settings.hideDockIcon, privacy: .public)")
    }

    /// Updates app activation policy to show or hide the Dock icon.
    private func applyDockIconVisibility(hidden: Bool) {
        let policy: NSApplication.ActivationPolicy = hidden ? .accessory : .regular
        let app = NSApplication.shared
        if app.activationPolicy() != policy {
            _ = app.setActivationPolicy(policy)
        }
    }
}
