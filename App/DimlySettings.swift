// MARK: - Settings Model
// Codable representation of persisted user preferences for Dimly.
import Foundation

/// Persisted desired monitor power behavior for a display.
enum PersistedMonitorPowerState: String, Codable, Equatable {
    case visible
    case blackout
    case standby
}

/// Persisted app appearance preference.
enum AppAppearancePreference: String, Codable, Equatable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }
}

/// Persisted user-configurable settings for Dimly.
struct DimlySettings: Codable, Equatable {
    enum MenuBarLayoutMode: String, Codable, Equatable {
        case simple
        case advanced
        case short
    }

    enum FastActionsVisibilityMode: String, Codable, Equatable, CaseIterable, Identifiable {
        case hideInCompact
        case advancedOnly
        case showEverywhere

        var id: String { rawValue }
    }

    var launchAtLogin: Bool
    var showMenuBarIcon: Bool
    var hideDockIcon: Bool
    var appAppearancePreference: AppAppearancePreference
    var hotkeyBindings: [HotkeyBinding]
    var showDisplayNumbers: Bool
    var displayAliases: [String: String]
    var fadeOutAnimationEnabled: Bool
    var fadeInAnimationEnabled: Bool
    var overlayOnlyDisplayIDs: [String]
    var menuBarExcludedDisplayIDs: [String]
    var menuBarIncludedInternalDisplayIDs: [String]
    var mergeInternalAndExternalDisplays: Bool
    var externalDisplayOrder: [String]
    var internalDisplayOrder: [String]
    var mergedDisplayOrder: [String]
    var menuBarSimpleMode: Bool
    var menuBarQuickActionsMode: Bool
    var fastActionsVisibilityMode: FastActionsVisibilityMode
    var menuBarSmartButtonsLimit: Int
    var menuBarSmartButtonsColorlessMode: Bool
    var brightnessPanelExpandedDisplayIDs: [String]
    var monitorBrightnessByDisplayID: [String: Int]
    var monitorPowerStateByDisplayID: [String: PersistedMonitorPowerState]
    var monitorLastSeenAtByDisplayID: [String: Date]

    private enum CodingKeys: String, CodingKey {
        case launchAtLogin
        case showMenuBarIcon
        case hideDockIcon
        case appAppearancePreference
        case hotkeyBindings
        case primaryHotkey
        case showDisplayNumbers
        case displayAliases
        case fadeOutAnimationEnabled
        case fadeInAnimationEnabled
        case overlayOnlyDisplayIDs
        case menuBarExcludedDisplayIDs
        case menuBarIncludedInternalDisplayIDs
        case mergeInternalAndExternalDisplays
        case externalDisplayOrder
        case internalDisplayOrder
        case mergedDisplayOrder
        case menuBarSimpleMode
        case menuBarQuickActionsMode
        case menuBarLayoutMode
        case fastActionsVisibilityMode
        case menuBarSmartButtonsLimit
        case menuBarSmartButtonsColorlessMode
        case brightnessPanelExpandedDisplayIDs
        case monitorBrightnessByDisplayID
        case monitorPowerStateByDisplayID
        case monitorLastSeenAtByDisplayID
    }

    var menuBarLayoutMode: MenuBarLayoutMode {
        get {
            if menuBarQuickActionsMode {
                return .short
            }
            return menuBarSimpleMode ? .simple : .advanced
        }
        set {
            menuBarSimpleMode = (newValue == .simple)
            menuBarQuickActionsMode = (newValue == .short)
        }
    }

    /// Default settings used on first launch or when decoding fails.
    static let `default` = DimlySettings(
        launchAtLogin: false,
        showMenuBarIcon: true,
        hideDockIcon: true,
        appAppearancePreference: .system,
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
        menuBarIncludedInternalDisplayIDs: [],
        mergeInternalAndExternalDisplays: false,
        externalDisplayOrder: [],
        internalDisplayOrder: [],
        mergedDisplayOrder: [],
        menuBarSimpleMode: false,
        menuBarQuickActionsMode: false,
        fastActionsVisibilityMode: .advancedOnly,
        menuBarSmartButtonsLimit: 8,
        menuBarSmartButtonsColorlessMode: false,
        brightnessPanelExpandedDisplayIDs: [],
        monitorBrightnessByDisplayID: [:],
        monitorPowerStateByDisplayID: [:],
        monitorLastSeenAtByDisplayID: [:]
    )

    /// Memberwise initializer used by the default factory and decoder.
    init(
        launchAtLogin: Bool,
        showMenuBarIcon: Bool,
        hideDockIcon: Bool,
        appAppearancePreference: AppAppearancePreference,
        hotkeyBindings: [HotkeyBinding],
        showDisplayNumbers: Bool,
        displayAliases: [String: String],
        fadeOutAnimationEnabled: Bool,
        fadeInAnimationEnabled: Bool,
        overlayOnlyDisplayIDs: [String],
        menuBarExcludedDisplayIDs: [String],
        menuBarIncludedInternalDisplayIDs: [String],
        mergeInternalAndExternalDisplays: Bool,
        externalDisplayOrder: [String],
        internalDisplayOrder: [String],
        mergedDisplayOrder: [String],
        menuBarSimpleMode: Bool,
        menuBarQuickActionsMode: Bool,
        fastActionsVisibilityMode: FastActionsVisibilityMode,
        menuBarSmartButtonsLimit: Int,
        menuBarSmartButtonsColorlessMode: Bool,
        brightnessPanelExpandedDisplayIDs: [String],
        monitorBrightnessByDisplayID: [String: Int],
        monitorPowerStateByDisplayID: [String: PersistedMonitorPowerState],
        monitorLastSeenAtByDisplayID: [String: Date]
    ) {
        self.launchAtLogin = launchAtLogin
        self.showMenuBarIcon = showMenuBarIcon
        self.hideDockIcon = hideDockIcon
        self.appAppearancePreference = appAppearancePreference
        self.hotkeyBindings = hotkeyBindings
        self.showDisplayNumbers = showDisplayNumbers
        self.displayAliases = displayAliases
        self.fadeOutAnimationEnabled = fadeOutAnimationEnabled
        self.fadeInAnimationEnabled = fadeInAnimationEnabled
        self.overlayOnlyDisplayIDs = overlayOnlyDisplayIDs
        self.menuBarExcludedDisplayIDs = menuBarExcludedDisplayIDs
        self.menuBarIncludedInternalDisplayIDs = menuBarIncludedInternalDisplayIDs
        self.mergeInternalAndExternalDisplays = mergeInternalAndExternalDisplays
        self.externalDisplayOrder = externalDisplayOrder
        self.internalDisplayOrder = internalDisplayOrder
        self.mergedDisplayOrder = mergedDisplayOrder
        self.menuBarSimpleMode = menuBarSimpleMode
        self.menuBarQuickActionsMode = menuBarQuickActionsMode
        self.fastActionsVisibilityMode = fastActionsVisibilityMode
        self.menuBarSmartButtonsLimit = Self.normalizedSmartButtonsLimit(menuBarSmartButtonsLimit)
        self.menuBarSmartButtonsColorlessMode = menuBarSmartButtonsColorlessMode
        self.brightnessPanelExpandedDisplayIDs = brightnessPanelExpandedDisplayIDs
        self.monitorBrightnessByDisplayID = monitorBrightnessByDisplayID
        self.monitorPowerStateByDisplayID = monitorPowerStateByDisplayID
        self.monitorLastSeenAtByDisplayID = monitorLastSeenAtByDisplayID
    }

    /// Custom decoder that also handles legacy single-hotkey migration.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? DimlySettings.default.launchAtLogin
        let showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? DimlySettings.default.showMenuBarIcon
        let hideDockIcon = try container.decodeIfPresent(Bool.self, forKey: .hideDockIcon) ?? DimlySettings.default.hideDockIcon
        let appAppearancePreference = try container.decodeIfPresent(AppAppearancePreference.self, forKey: .appAppearancePreference) ?? DimlySettings.default.appAppearancePreference
        let hotkeyBindings = try container.decodeIfPresent([HotkeyBinding].self, forKey: .hotkeyBindings)
        let legacyPrimaryHotkey = try container.decodeIfPresent(HotkeyDescriptor.self, forKey: .primaryHotkey)
        let showDisplayNumbers = try container.decodeIfPresent(Bool.self, forKey: .showDisplayNumbers) ?? DimlySettings.default.showDisplayNumbers
        let displayAliases = try container.decodeIfPresent([String: String].self, forKey: .displayAliases) ?? DimlySettings.default.displayAliases
        let fadeOutAnimationEnabled = try container.decodeIfPresent(Bool.self, forKey: .fadeOutAnimationEnabled) ?? DimlySettings.default.fadeOutAnimationEnabled
        let fadeInAnimationEnabled = try container.decodeIfPresent(Bool.self, forKey: .fadeInAnimationEnabled) ?? DimlySettings.default.fadeInAnimationEnabled
        let overlayOnlyDisplayIDs = try container.decodeIfPresent([String].self, forKey: .overlayOnlyDisplayIDs) ?? DimlySettings.default.overlayOnlyDisplayIDs
        let menuBarExcludedDisplayIDs = try container.decodeIfPresent([String].self, forKey: .menuBarExcludedDisplayIDs) ?? DimlySettings.default.menuBarExcludedDisplayIDs
        let menuBarIncludedInternalDisplayIDs = try container.decodeIfPresent([String].self, forKey: .menuBarIncludedInternalDisplayIDs) ?? DimlySettings.default.menuBarIncludedInternalDisplayIDs
        let mergeInternalAndExternalDisplays = try container.decodeIfPresent(Bool.self, forKey: .mergeInternalAndExternalDisplays) ?? DimlySettings.default.mergeInternalAndExternalDisplays
        let externalDisplayOrder = try container.decodeIfPresent([String].self, forKey: .externalDisplayOrder) ?? DimlySettings.default.externalDisplayOrder
        let internalDisplayOrder = try container.decodeIfPresent([String].self, forKey: .internalDisplayOrder) ?? DimlySettings.default.internalDisplayOrder
        let mergedDisplayOrder = try container.decodeIfPresent([String].self, forKey: .mergedDisplayOrder) ?? DimlySettings.default.mergedDisplayOrder
        let decodedMenuBarLayoutMode = try container.decodeIfPresent(MenuBarLayoutMode.self, forKey: .menuBarLayoutMode)
        let legacyMenuBarSimpleMode = try container.decodeIfPresent(Bool.self, forKey: .menuBarSimpleMode) ?? DimlySettings.default.menuBarSimpleMode
        let legacyMenuBarQuickActionsMode = try container.decodeIfPresent(Bool.self, forKey: .menuBarQuickActionsMode) ?? DimlySettings.default.menuBarQuickActionsMode
        let resolvedMenuBarLayoutMode = decodedMenuBarLayoutMode
            ?? (legacyMenuBarQuickActionsMode ? .short : (legacyMenuBarSimpleMode ? .simple : .advanced))
        let menuBarSimpleMode = resolvedMenuBarLayoutMode == .simple
        let menuBarQuickActionsMode = resolvedMenuBarLayoutMode == .short
        let fastActionsVisibilityMode = try container.decodeIfPresent(FastActionsVisibilityMode.self, forKey: .fastActionsVisibilityMode)
            ?? DimlySettings.default.fastActionsVisibilityMode
        let menuBarSmartButtonsLimit = try container.decodeIfPresent(Int.self, forKey: .menuBarSmartButtonsLimit) ?? DimlySettings.default.menuBarSmartButtonsLimit
        let menuBarSmartButtonsColorlessMode = try container.decodeIfPresent(Bool.self, forKey: .menuBarSmartButtonsColorlessMode) ?? DimlySettings.default.menuBarSmartButtonsColorlessMode
        let brightnessPanelExpandedDisplayIDs = try container.decodeIfPresent([String].self, forKey: .brightnessPanelExpandedDisplayIDs) ?? DimlySettings.default.brightnessPanelExpandedDisplayIDs
        let monitorBrightnessByDisplayID = try container.decodeIfPresent([String: Int].self, forKey: .monitorBrightnessByDisplayID) ?? DimlySettings.default.monitorBrightnessByDisplayID
        let monitorPowerStateByDisplayID = try container.decodeIfPresent([String: PersistedMonitorPowerState].self, forKey: .monitorPowerStateByDisplayID) ?? DimlySettings.default.monitorPowerStateByDisplayID
        let monitorLastSeenAtByDisplayID = try container.decodeIfPresent([String: Date].self, forKey: .monitorLastSeenAtByDisplayID) ?? DimlySettings.default.monitorLastSeenAtByDisplayID
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
            appAppearancePreference: appAppearancePreference,
            hotkeyBindings: resolvedBindings,
            showDisplayNumbers: showDisplayNumbers,
            displayAliases: displayAliases,
            fadeOutAnimationEnabled: fadeOutAnimationEnabled,
            fadeInAnimationEnabled: fadeInAnimationEnabled,
            overlayOnlyDisplayIDs: overlayOnlyDisplayIDs,
            menuBarExcludedDisplayIDs: menuBarExcludedDisplayIDs,
            menuBarIncludedInternalDisplayIDs: menuBarIncludedInternalDisplayIDs,
            mergeInternalAndExternalDisplays: mergeInternalAndExternalDisplays,
            externalDisplayOrder: externalDisplayOrder,
            internalDisplayOrder: internalDisplayOrder,
            mergedDisplayOrder: mergedDisplayOrder,
            menuBarSimpleMode: menuBarSimpleMode,
            menuBarQuickActionsMode: menuBarQuickActionsMode,
            fastActionsVisibilityMode: fastActionsVisibilityMode,
            menuBarSmartButtonsLimit: menuBarSmartButtonsLimit,
            menuBarSmartButtonsColorlessMode: menuBarSmartButtonsColorlessMode,
            brightnessPanelExpandedDisplayIDs: brightnessPanelExpandedDisplayIDs,
            monitorBrightnessByDisplayID: monitorBrightnessByDisplayID,
            monitorPowerStateByDisplayID: monitorPowerStateByDisplayID,
            monitorLastSeenAtByDisplayID: monitorLastSeenAtByDisplayID
        )
    }

    /// Encodes current settings for persistence.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(launchAtLogin, forKey: .launchAtLogin)
        try container.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try container.encode(hideDockIcon, forKey: .hideDockIcon)
        try container.encode(appAppearancePreference, forKey: .appAppearancePreference)
        try container.encode(hotkeyBindings, forKey: .hotkeyBindings)
        try container.encode(showDisplayNumbers, forKey: .showDisplayNumbers)
        try container.encode(displayAliases, forKey: .displayAliases)
        try container.encode(fadeOutAnimationEnabled, forKey: .fadeOutAnimationEnabled)
        try container.encode(fadeInAnimationEnabled, forKey: .fadeInAnimationEnabled)
        try container.encode(overlayOnlyDisplayIDs, forKey: .overlayOnlyDisplayIDs)
        try container.encode(menuBarExcludedDisplayIDs, forKey: .menuBarExcludedDisplayIDs)
        try container.encode(menuBarIncludedInternalDisplayIDs, forKey: .menuBarIncludedInternalDisplayIDs)
        try container.encode(mergeInternalAndExternalDisplays, forKey: .mergeInternalAndExternalDisplays)
        try container.encode(externalDisplayOrder, forKey: .externalDisplayOrder)
        try container.encode(internalDisplayOrder, forKey: .internalDisplayOrder)
        try container.encode(mergedDisplayOrder, forKey: .mergedDisplayOrder)
        try container.encode(menuBarSimpleMode, forKey: .menuBarSimpleMode)
        try container.encode(menuBarQuickActionsMode, forKey: .menuBarQuickActionsMode)
        try container.encode(menuBarLayoutMode, forKey: .menuBarLayoutMode)
        try container.encode(fastActionsVisibilityMode, forKey: .fastActionsVisibilityMode)
        try container.encode(Self.normalizedSmartButtonsLimit(menuBarSmartButtonsLimit), forKey: .menuBarSmartButtonsLimit)
        try container.encode(menuBarSmartButtonsColorlessMode, forKey: .menuBarSmartButtonsColorlessMode)
        try container.encode(brightnessPanelExpandedDisplayIDs, forKey: .brightnessPanelExpandedDisplayIDs)
        try container.encode(monitorBrightnessByDisplayID, forKey: .monitorBrightnessByDisplayID)
        try container.encode(monitorPowerStateByDisplayID, forKey: .monitorPowerStateByDisplayID)
        try container.encode(monitorLastSeenAtByDisplayID, forKey: .monitorLastSeenAtByDisplayID)
    }

    /// Clamps smart-button row limits to the supported range.
    private static func normalizedSmartButtonsLimit(_ value: Int) -> Int {
        max(4, min(16, value))
    }
}

extension DimlySettings.FastActionsVisibilityMode {
    var localizedTitle: String {
        switch self {
        case .hideInCompact:
            return String(localized: "Hide in compact")
        case .advancedOnly:
            return String(localized: "Only in advanced")
        case .showEverywhere:
            return String(localized: "Show on every screen")
        }
    }
}

/// `UserDefaults`-backed persistence layer for `DimlySettings`.
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
            // Fall back to defaults if a stored payload no longer decodes cleanly.
            return .default
        }
    }

    /// Persists settings to `UserDefaults`.
    static func save(_ settings: DimlySettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: settingsKey)
        } catch {
            // Ignore write failures here because higher layers already handle diagnostics.
        }
    }
}
