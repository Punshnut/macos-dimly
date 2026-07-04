// MARK: - What's New Content
// Static list of recently added features shown in the intro window's "What's New" mode.
import SwiftUI

/// Settings sidebar tab a What's New feature's location caption links to.
enum SettingsNavigationTarget: String {
    case luts
    case displays
}

/// Carries a pending Settings-tab navigation request from the What's New card to the Settings
/// window. A plain notification would race the Settings window's own creation on a cold start
/// (the window isn't created, and its view isn't yet subscribed, until the notification that
/// opens it is handled) — this survives until whichever `SettingsRootView` instance appears
/// (new or already-open) is ready to consume it.
@MainActor
final class SettingsNavigationCoordinator: ObservableObject {
    static let shared = SettingsNavigationCoordinator()
    @Published var pendingTarget: SettingsNavigationTarget?
    private init() {}
}

struct WhatsNewFeature: Identifiable {
    let id: String
    let symbol: String
    let color: Color
    let titleKey: String
    let descriptionKey: String
    let locationKey: String
    let settingsTarget: SettingsNavigationTarget
    let introducedInRevision: Int
}

/// Bump `currentRevision` whenever a new entry is added so returning users see only the delta.
enum WhatsNewContent {
    static let currentRevision = 1

    static let features: [WhatsNewFeature] = [
        WhatsNewFeature(
            id: "lutLibrary",
            symbol: "cube.transparent",
            color: .purple,
            titleKey: "WhatsNewLUTLibraryTitle",
            descriptionKey: "WhatsNewLUTLibraryDescription",
            locationKey: "WhatsNewLUTLibraryLocation",
            settingsTarget: .luts,
            introducedInRevision: 1
        ),
        WhatsNewFeature(
            id: "displaySettingsOverhaul",
            symbol: "slider.horizontal.3",
            color: .blue,
            titleKey: "WhatsNewDisplaySettingsTitle",
            descriptionKey: "WhatsNewDisplaySettingsDescription",
            locationKey: "WhatsNewDisplaySettingsLocation",
            settingsTarget: .displays,
            introducedInRevision: 1
        )
    ]
}
