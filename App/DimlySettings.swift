// MARK: - Settings Model
// Codable representation of persisted user preferences for Dimly.
import Foundation

/// Persisted desired monitor power behavior for a display.
enum PersistedMonitorPowerState: String, Codable, Equatable {
    case visible
    case blackout
    case standby
}

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
    var menuBarExcludedDisplayIDs: [String]
    var externalDisplayOrder: [String]
    var menuBarSimpleMode: Bool
    var brightnessPanelExpandedDisplayIDs: [String]
    var monitorBrightnessByDisplayID: [String: Int]
    var monitorPowerStateByDisplayID: [String: PersistedMonitorPowerState]

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
        case menuBarExcludedDisplayIDs
        case externalDisplayOrder
        case menuBarSimpleMode
        case brightnessPanelExpandedDisplayIDs
        case monitorBrightnessByDisplayID
        case monitorPowerStateByDisplayID
    }

    /// Default settings used on first launch or when decoding fails.
    static let `default` = DimlySettings(
        launchAtLogin: false,
        showMenuBarIcon: true,
        hideDockIcon: true,
        hotkeyBindings: [
            HotkeyBinding(
                action: .toggleWindow,
                target: .allExternalDisplays,
                descriptor: .toggleLauncher
            )
        ],
        showDisplayNumbers: false,
        displayAliases: [:],
        fadeOutAnimationEnabled: true,
        fadeInAnimationEnabled: true,
        overlayOnlyDisplayIDs: [],
        menuBarExcludedDisplayIDs: [],
        externalDisplayOrder: [],
        menuBarSimpleMode: false,
        brightnessPanelExpandedDisplayIDs: [],
        monitorBrightnessByDisplayID: [:],
        monitorPowerStateByDisplayID: [:]
    )

    /// Memberwise initializer used by the default factory and decoder.
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
        menuBarExcludedDisplayIDs: [String],
        externalDisplayOrder: [String],
        menuBarSimpleMode: Bool,
        brightnessPanelExpandedDisplayIDs: [String],
        monitorBrightnessByDisplayID: [String: Int],
        monitorPowerStateByDisplayID: [String: PersistedMonitorPowerState]
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
        self.menuBarExcludedDisplayIDs = menuBarExcludedDisplayIDs
        self.externalDisplayOrder = externalDisplayOrder
        self.menuBarSimpleMode = menuBarSimpleMode
        self.brightnessPanelExpandedDisplayIDs = brightnessPanelExpandedDisplayIDs
        self.monitorBrightnessByDisplayID = monitorBrightnessByDisplayID
        self.monitorPowerStateByDisplayID = monitorPowerStateByDisplayID
    }

    /// Custom decoder that also handles legacy single-hotkey migration.
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
        let menuBarExcludedDisplayIDs = try container.decodeIfPresent([String].self, forKey: .menuBarExcludedDisplayIDs) ?? DimlySettings.default.menuBarExcludedDisplayIDs
        let externalDisplayOrder = try container.decodeIfPresent([String].self, forKey: .externalDisplayOrder) ?? DimlySettings.default.externalDisplayOrder
        let menuBarSimpleMode = try container.decodeIfPresent(Bool.self, forKey: .menuBarSimpleMode) ?? DimlySettings.default.menuBarSimpleMode
        let brightnessPanelExpandedDisplayIDs = try container.decodeIfPresent([String].self, forKey: .brightnessPanelExpandedDisplayIDs) ?? DimlySettings.default.brightnessPanelExpandedDisplayIDs
        let monitorBrightnessByDisplayID = try container.decodeIfPresent([String: Int].self, forKey: .monitorBrightnessByDisplayID) ?? DimlySettings.default.monitorBrightnessByDisplayID
        let monitorPowerStateByDisplayID = try container.decodeIfPresent([String: PersistedMonitorPowerState].self, forKey: .monitorPowerStateByDisplayID) ?? DimlySettings.default.monitorPowerStateByDisplayID
        var resolvedBindings: [HotkeyBinding]
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

        if resolvedBindings.count == 1,
           resolvedBindings[0].action == .toggleBlackout,
           resolvedBindings[0].descriptor == .toggleLauncher {
            resolvedBindings[0].action = .toggleWindow
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
            menuBarExcludedDisplayIDs: menuBarExcludedDisplayIDs,
            externalDisplayOrder: externalDisplayOrder,
            menuBarSimpleMode: menuBarSimpleMode,
            brightnessPanelExpandedDisplayIDs: brightnessPanelExpandedDisplayIDs,
            monitorBrightnessByDisplayID: monitorBrightnessByDisplayID,
            monitorPowerStateByDisplayID: monitorPowerStateByDisplayID
        )
    }

    /// Encodes current settings for persistence.
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
        try container.encode(menuBarExcludedDisplayIDs, forKey: .menuBarExcludedDisplayIDs)
        try container.encode(externalDisplayOrder, forKey: .externalDisplayOrder)
        try container.encode(menuBarSimpleMode, forKey: .menuBarSimpleMode)
        try container.encode(brightnessPanelExpandedDisplayIDs, forKey: .brightnessPanelExpandedDisplayIDs)
        try container.encode(monitorBrightnessByDisplayID, forKey: .monitorBrightnessByDisplayID)
        try container.encode(monitorPowerStateByDisplayID, forKey: .monitorPowerStateByDisplayID)
    }
}

/// Lightweight persistence layer for `DimlySettings` backed by `UserDefaults`.
enum DimlySettingsStore {
    private static let settingsKey = "DimlySettings.v1"

    /// Loads settings from `UserDefaults` or falls back to defaults.
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

    /// Persists settings to `UserDefaults`.
    static func save(_ settings: DimlySettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: settingsKey)
        } catch {
            // Swallow persistence errors for now; logging happens in the caller.
        }
    }
}
