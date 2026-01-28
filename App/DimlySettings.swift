// MARK: - Settings Model
// Codable representation of persisted user preferences for Dimly.
import Foundation

/// Persisted user-configurable settings for Dimly.
struct DimlySettings: Codable, Equatable {
    var launchAtLogin: Bool
    var showMenuBarIcon: Bool
    var hideDockIcon: Bool
    var hotkeyBindings: [HotkeyBinding]
    var showDisplayNumbers: Bool
    var displayAliases: [String: String]
    var fadeOutAnimationEnabled: Bool
    var fadeInAnimationEnabled: Bool
    var overlayOnlyDisplayIDs: [String]
    var externalDisplayOrder: [String]

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case showMenuBarIcon
        case hideDockIcon
        case hotkeyBindings
        case primaryHotkey
        case showDisplayNumbers
        case displayAliases
        case fadeOutAnimationEnabled
        case fadeInAnimationEnabled
        case overlayOnlyDisplayIDs
        case externalDisplayOrder
    }

    static let `default` = DimlySettings(
        launchAtLogin: false,
        showMenuBarIcon: true,
        hideDockIcon: true,
        hotkeyBindings: [
            HotkeyBinding(
                action: .toggleBlackout,
                target: .allExternalDisplays,
                descriptor: .toggleLauncher
            )
        ],
        showDisplayNumbers: false,
        displayAliases: [:],
        fadeOutAnimationEnabled: true,
        fadeInAnimationEnabled: true,
        overlayOnlyDisplayIDs: [],
        externalDisplayOrder: []
    )

    init(
        launchAtLogin: Bool,
        showMenuBarIcon: Bool,
        hideDockIcon: Bool,
        hotkeyBindings: [HotkeyBinding],
        showDisplayNumbers: Bool,
        displayAliases: [String: String],
        fadeOutAnimationEnabled: Bool,
        fadeInAnimationEnabled: Bool,
        overlayOnlyDisplayIDs: [String],
        externalDisplayOrder: [String]
    ) {
        self.launchAtLogin = launchAtLogin
        self.showMenuBarIcon = showMenuBarIcon
        self.hideDockIcon = hideDockIcon
        self.hotkeyBindings = hotkeyBindings
        self.showDisplayNumbers = showDisplayNumbers
        self.displayAliases = displayAliases
        self.fadeOutAnimationEnabled = fadeOutAnimationEnabled
        self.fadeInAnimationEnabled = fadeInAnimationEnabled
        self.overlayOnlyDisplayIDs = overlayOnlyDisplayIDs
        self.externalDisplayOrder = externalDisplayOrder
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? DimlySettings.default.launchAtLogin
        let showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? DimlySettings.default.showMenuBarIcon
        let hideDockIcon = try container.decodeIfPresent(Bool.self, forKey: .hideDockIcon) ?? DimlySettings.default.hideDockIcon
        let hotkeyBindings = try container.decodeIfPresent([HotkeyBinding].self, forKey: .hotkeyBindings)
        let legacyPrimaryHotkey = try container.decodeIfPresent(HotkeyDescriptor.self, forKey: .primaryHotkey)
        let showDisplayNumbers = try container.decodeIfPresent(Bool.self, forKey: .showDisplayNumbers) ?? DimlySettings.default.showDisplayNumbers
        let displayAliases = try container.decodeIfPresent([String: String].self, forKey: .displayAliases) ?? DimlySettings.default.displayAliases
        let fadeOutAnimationEnabled = try container.decodeIfPresent(Bool.self, forKey: .fadeOutAnimationEnabled) ?? DimlySettings.default.fadeOutAnimationEnabled
        let fadeInAnimationEnabled = try container.decodeIfPresent(Bool.self, forKey: .fadeInAnimationEnabled) ?? DimlySettings.default.fadeInAnimationEnabled
        let overlayOnlyDisplayIDs = try container.decodeIfPresent([String].self, forKey: .overlayOnlyDisplayIDs) ?? DimlySettings.default.overlayOnlyDisplayIDs
        let externalDisplayOrder = try container.decodeIfPresent([String].self, forKey: .externalDisplayOrder) ?? DimlySettings.default.externalDisplayOrder
        let resolvedBindings: [HotkeyBinding]
        if let hotkeyBindings, !hotkeyBindings.isEmpty {
            resolvedBindings = hotkeyBindings
        } else if let legacyPrimaryHotkey {
            resolvedBindings = [
                HotkeyBinding(
                    action: .toggleBlackout,
                    target: .allExternalDisplays,
                    descriptor: legacyPrimaryHotkey
                )
            ]
        } else {
            resolvedBindings = DimlySettings.default.hotkeyBindings
        }
        self.init(
            launchAtLogin: launchAtLogin,
            showMenuBarIcon: showMenuBarIcon,
            hideDockIcon: hideDockIcon,
            hotkeyBindings: resolvedBindings,
            showDisplayNumbers: showDisplayNumbers,
            displayAliases: displayAliases,
            fadeOutAnimationEnabled: fadeOutAnimationEnabled,
            fadeInAnimationEnabled: fadeInAnimationEnabled,
            overlayOnlyDisplayIDs: overlayOnlyDisplayIDs,
            externalDisplayOrder: externalDisplayOrder
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try container.encode(hideDockIcon, forKey: .hideDockIcon)
        try container.encode(hotkeyBindings, forKey: .hotkeyBindings)
        try container.encode(showDisplayNumbers, forKey: .showDisplayNumbers)
        try container.encode(displayAliases, forKey: .displayAliases)
        try container.encode(fadeOutAnimationEnabled, forKey: .fadeOutAnimationEnabled)
        try container.encode(fadeInAnimationEnabled, forKey: .fadeInAnimationEnabled)
        try container.encode(overlayOnlyDisplayIDs, forKey: .overlayOnlyDisplayIDs)
        try container.encode(externalDisplayOrder, forKey: .externalDisplayOrder)
    }
}

/// Lightweight persistence layer for `DimlySettings` backed by `UserDefaults`.
enum DimlySettingsStore {
    private static let settingsKey = "DimlySettings.v1"

    static func load() -> DimlySettings {
        guard let data = UserDefaults.standard.data(forKey: settingsKey) else {
            return .default
        }
        do {
            let decoded = try JSONDecoder().decode(DimlySettings.self, from: data)
            return decoded
        } catch {
            // If decoding fails, fall back to defaults instead of crashing.
            return .default
        }
    }

    static func save(_ settings: DimlySettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: settingsKey)
        } catch {
            // Swallow persistence errors for now; logging happens in the caller.
        }
    }
}
