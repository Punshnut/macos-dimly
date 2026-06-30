import Foundation

enum SettingsBackupType: String, Codable {
    case general
    case monitor
    case generalAndMonitor

    /// Derives the export type from the user's section-selection toggles.
    init?(includeGeneral: Bool, includeMonitor: Bool) {
        switch (includeGeneral, includeMonitor) {
        case (true, true):
            self = .generalAndMonitor
        case (true, false):
            self = .general
        case (false, true):
            self = .monitor
        case (false, false):
            return nil
        }
    }

    var includesGeneral: Bool {
        self == .general || self == .generalAndMonitor
    }

    var includesMonitor: Bool {
        self == .monitor || self == .generalAndMonitor
    }

    var fileToken: String {
        switch self {
        case .general:
            return "General"
        case .monitor:
            return "Monitor"
        case .generalAndMonitor:
            return "GeneralAndMonitor"
        }
    }
}

enum SettingsBackupApplyError: Error {
    case missingGeneralSettings
    case missingMonitorSettings
}

/// A single LUT file embedded in a backup so it can be restored on another Mac.
struct LUTBackupEntry: Codable {
    let entry: LUTEntry
    let fileData: Data
}

struct DimlySettingsBackup: Codable {
    let version: Int
    let exportedAt: Date
    let type: SettingsBackupType
    let general: GeneralSettingsPayload?
    let monitor: MonitorSettingsPayload?
    let profileState: ProfileState?
    let lutLibrary: [LUTBackupEntry]?

    /// Captures the requested settings sections into a versioned backup payload.
    init(
        settings: DimlySettings,
        type: SettingsBackupType,
        exportedAt: Date = Date(),
        profileState: ProfileState? = nil,
        lutLibrary: [LUTBackupEntry]? = nil
    ) {
        self.version = 2
        self.exportedAt = exportedAt
        self.type = type
        self.general = type.includesGeneral ? GeneralSettingsPayload(from: settings) : nil
        self.monitor = type.includesMonitor ? MonitorSettingsPayload(from: settings) : nil
        self.profileState = type.includesMonitor ? profileState : nil
        self.lutLibrary = type.includesMonitor ? lutLibrary : nil
    }

    /// Applies selected backup sections to a live settings snapshot.
    func applying(
        to settings: DimlySettings,
        includeGeneral: Bool,
        includeMonitor: Bool
    ) throws -> DimlySettings {
        var updated = settings
        if includeGeneral {
            guard let general else {
                throw SettingsBackupApplyError.missingGeneralSettings
            }
            general.apply(to: &updated)
        }
        if includeMonitor {
            guard let monitor else {
                throw SettingsBackupApplyError.missingMonitorSettings
            }
            monitor.apply(to: &updated)
        }
        return updated
    }

    /// Returns imported profile data only when monitor settings are being restored.
    func importedProfileState(includeMonitor: Bool) -> ProfileState? {
        guard includeMonitor else { return nil }
        return profileState
    }
}

struct GeneralSettingsPayload: Codable {
    let launchAtLogin: Bool
    let showMenuBarIcon: Bool
    let hideDockIcon: Bool
    let appAppearancePreference: AppAppearancePreference?
    let hotkeyBindings: [HotkeyBinding]
    let showDisplayNumbers: Bool
    let fadeOutAnimationEnabled: Bool
    let fadeInAnimationEnabled: Bool
    let menuBarSimpleMode: Bool
    let menuBarQuickActionsMode: Bool?
    let fastActionsVisibilityMode: DimlySettings.FastActionsVisibilityMode?
    let nightShiftEnabled: Bool?
    let nightShiftStrength: Float?

    /// Snapshots general app preferences without monitor-specific state.
    init(from settings: DimlySettings) {
        launchAtLogin = settings.launchAtLogin
        showMenuBarIcon = settings.showMenuBarIcon
        hideDockIcon = settings.hideDockIcon
        appAppearancePreference = settings.appAppearancePreference
        hotkeyBindings = settings.hotkeyBindings
        showDisplayNumbers = settings.showDisplayNumbers
        fadeOutAnimationEnabled = settings.fadeOutAnimationEnabled
        fadeInAnimationEnabled = settings.fadeInAnimationEnabled
        menuBarSimpleMode = settings.menuBarSimpleMode
        menuBarQuickActionsMode = settings.menuBarQuickActionsMode
        fastActionsVisibilityMode = settings.fastActionsVisibilityMode
        nightShiftEnabled = settings.nightShiftEnabled
        nightShiftStrength = settings.nightShiftStrength
    }

    /// Writes general (non-monitor-specific) settings into the target settings object.
    func apply(to settings: inout DimlySettings) {
        settings.launchAtLogin = launchAtLogin
        settings.showMenuBarIcon = showMenuBarIcon
        settings.hideDockIcon = hideDockIcon
        settings.appAppearancePreference = appAppearancePreference ?? .system
        settings.hotkeyBindings = hotkeyBindings
        settings.showDisplayNumbers = showDisplayNumbers
        settings.fadeOutAnimationEnabled = fadeOutAnimationEnabled
        settings.fadeInAnimationEnabled = fadeInAnimationEnabled
        settings.menuBarSimpleMode = menuBarSimpleMode
        settings.menuBarQuickActionsMode = menuBarQuickActionsMode ?? false
        settings.fastActionsVisibilityMode = fastActionsVisibilityMode ?? .advancedOnly
        settings.nightShiftEnabled = nightShiftEnabled ?? false
        settings.nightShiftStrength = nightShiftStrength ?? 0.5
    }
}

struct MonitorSettingsPayload: Codable {
    let displayAliases: [String: String]
    let overlayOnlyDisplayIDs: [String]
    let menuBarExcludedDisplayIDs: [String]
    let menuBarIncludedInternalDisplayIDs: [String]
    let mergeInternalAndExternalDisplays: Bool
    let externalDisplayOrder: [String]
    let internalDisplayOrder: [String]
    let mergedDisplayOrder: [String]
    let externalDisplayRows: [[String]]
    let internalDisplayRows: [[String]]
    let mergedDisplayRows: [[String]]
    let brightnessPanelExpandedDisplayIDs: [String]
    let monitorBrightnessByDisplayID: [String: Int]
    let monitorPowerStateByDisplayID: [String: PersistedMonitorPowerState]
    let monitorContrastByDisplayID: [String: Int]
    let monitorInputSourceByDisplayID: [String: Int]
    let monitorDisplayModeByDisplayID: [String: Int]
    let monitorColorProfileByDisplayID: [String: String]
    let displayFilterByDisplayID: [String: DisplayFilter]
    let activeLUTByDisplayID: [String: UUID]
    let trueToneEnabledByDisplayID: [String: Bool]

    private enum CodingKeys: String, CodingKey {
        case displayAliases
        case overlayOnlyDisplayIDs
        case menuBarExcludedDisplayIDs
        case menuBarIncludedInternalDisplayIDs
        case mergeInternalAndExternalDisplays
        case externalDisplayOrder
        case internalDisplayOrder
        case mergedDisplayOrder
        case externalDisplayRows
        case internalDisplayRows
        case mergedDisplayRows
        case brightnessPanelExpandedDisplayIDs
        case monitorBrightnessByDisplayID
        case monitorPowerStateByDisplayID
        case monitorContrastByDisplayID
        case monitorInputSourceByDisplayID
        case monitorDisplayModeByDisplayID
        case monitorColorProfileByDisplayID
        case displayFilterByDisplayID
        case activeLUTByDisplayID
        case trueToneEnabledByDisplayID
    }

    /// Snapshots per-display ordering, aliases, brightness, power intent, and new display controls.
    init(from settings: DimlySettings) {
        displayAliases = settings.displayAliases
        overlayOnlyDisplayIDs = settings.overlayOnlyDisplayIDs
        menuBarExcludedDisplayIDs = settings.menuBarExcludedDisplayIDs
        menuBarIncludedInternalDisplayIDs = settings.menuBarIncludedInternalDisplayIDs
        mergeInternalAndExternalDisplays = settings.mergeInternalAndExternalDisplays
        externalDisplayOrder = settings.externalDisplayOrder
        internalDisplayOrder = settings.internalDisplayOrder
        mergedDisplayOrder = settings.mergedDisplayOrder
        externalDisplayRows = settings.externalDisplayRows
        internalDisplayRows = settings.internalDisplayRows
        mergedDisplayRows = settings.mergedDisplayRows
        brightnessPanelExpandedDisplayIDs = settings.brightnessPanelExpandedDisplayIDs
        monitorBrightnessByDisplayID = settings.monitorBrightnessByDisplayID
        monitorPowerStateByDisplayID = settings.monitorPowerStateByDisplayID
        monitorContrastByDisplayID = settings.monitorContrastByDisplayID
        monitorInputSourceByDisplayID = settings.monitorInputSourceByDisplayID
        monitorDisplayModeByDisplayID = settings.monitorDisplayModeByDisplayID
        monitorColorProfileByDisplayID = settings.monitorColorProfileByDisplayID
        displayFilterByDisplayID = settings.displayFilterByDisplayID
        activeLUTByDisplayID = settings.activeLUTByDisplayID
        trueToneEnabledByDisplayID = settings.trueToneEnabledByDisplayID
    }

    /// Decodes monitor payloads defensively so older backups can omit newer fields.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayAliases = try container.decodeIfPresent([String: String].self, forKey: .displayAliases) ?? [:]
        overlayOnlyDisplayIDs = try container.decodeIfPresent([String].self, forKey: .overlayOnlyDisplayIDs) ?? []
        menuBarExcludedDisplayIDs = try container.decodeIfPresent([String].self, forKey: .menuBarExcludedDisplayIDs) ?? []
        menuBarIncludedInternalDisplayIDs = try container.decodeIfPresent([String].self, forKey: .menuBarIncludedInternalDisplayIDs) ?? []
        mergeInternalAndExternalDisplays = try container.decodeIfPresent(Bool.self, forKey: .mergeInternalAndExternalDisplays) ?? false
        externalDisplayOrder = try container.decodeIfPresent([String].self, forKey: .externalDisplayOrder) ?? []
        internalDisplayOrder = try container.decodeIfPresent([String].self, forKey: .internalDisplayOrder) ?? []
        mergedDisplayOrder = try container.decodeIfPresent([String].self, forKey: .mergedDisplayOrder) ?? []
        externalDisplayRows = try container.decodeIfPresent([[String]].self, forKey: .externalDisplayRows) ?? []
        internalDisplayRows = try container.decodeIfPresent([[String]].self, forKey: .internalDisplayRows) ?? []
        mergedDisplayRows = try container.decodeIfPresent([[String]].self, forKey: .mergedDisplayRows) ?? []
        brightnessPanelExpandedDisplayIDs = try container.decodeIfPresent([String].self, forKey: .brightnessPanelExpandedDisplayIDs) ?? []
        monitorBrightnessByDisplayID = try container.decodeIfPresent([String: Int].self, forKey: .monitorBrightnessByDisplayID) ?? [:]
        monitorPowerStateByDisplayID = try container.decodeIfPresent([String: PersistedMonitorPowerState].self, forKey: .monitorPowerStateByDisplayID) ?? [:]
        monitorContrastByDisplayID = try container.decodeIfPresent([String: Int].self, forKey: .monitorContrastByDisplayID) ?? [:]
        monitorInputSourceByDisplayID = try container.decodeIfPresent([String: Int].self, forKey: .monitorInputSourceByDisplayID) ?? [:]
        monitorDisplayModeByDisplayID = try container.decodeIfPresent([String: Int].self, forKey: .monitorDisplayModeByDisplayID) ?? [:]
        monitorColorProfileByDisplayID = try container.decodeIfPresent([String: String].self, forKey: .monitorColorProfileByDisplayID) ?? [:]
        displayFilterByDisplayID = try container.decodeIfPresent([String: DisplayFilter].self, forKey: .displayFilterByDisplayID) ?? [:]
        activeLUTByDisplayID = try container.decodeIfPresent([String: UUID].self, forKey: .activeLUTByDisplayID) ?? [:]
        trueToneEnabledByDisplayID = try container.decodeIfPresent([String: Bool].self, forKey: .trueToneEnabledByDisplayID) ?? [:]
    }

    /// Encodes monitor payload while preserving forward/backward compatibility defaults.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayAliases, forKey: .displayAliases)
        try container.encode(overlayOnlyDisplayIDs, forKey: .overlayOnlyDisplayIDs)
        try container.encode(menuBarExcludedDisplayIDs, forKey: .menuBarExcludedDisplayIDs)
        try container.encode(menuBarIncludedInternalDisplayIDs, forKey: .menuBarIncludedInternalDisplayIDs)
        try container.encode(mergeInternalAndExternalDisplays, forKey: .mergeInternalAndExternalDisplays)
        try container.encode(externalDisplayOrder, forKey: .externalDisplayOrder)
        try container.encode(internalDisplayOrder, forKey: .internalDisplayOrder)
        try container.encode(mergedDisplayOrder, forKey: .mergedDisplayOrder)
        try container.encode(externalDisplayRows, forKey: .externalDisplayRows)
        try container.encode(internalDisplayRows, forKey: .internalDisplayRows)
        try container.encode(mergedDisplayRows, forKey: .mergedDisplayRows)
        try container.encode(brightnessPanelExpandedDisplayIDs, forKey: .brightnessPanelExpandedDisplayIDs)
        try container.encode(monitorBrightnessByDisplayID, forKey: .monitorBrightnessByDisplayID)
        try container.encode(monitorPowerStateByDisplayID, forKey: .monitorPowerStateByDisplayID)
        try container.encode(monitorContrastByDisplayID, forKey: .monitorContrastByDisplayID)
        try container.encode(monitorInputSourceByDisplayID, forKey: .monitorInputSourceByDisplayID)
        try container.encode(monitorDisplayModeByDisplayID, forKey: .monitorDisplayModeByDisplayID)
        try container.encode(monitorColorProfileByDisplayID, forKey: .monitorColorProfileByDisplayID)
        try container.encode(displayFilterByDisplayID, forKey: .displayFilterByDisplayID)
        try container.encode(activeLUTByDisplayID, forKey: .activeLUTByDisplayID)
        try container.encode(trueToneEnabledByDisplayID, forKey: .trueToneEnabledByDisplayID)
    }

    /// Writes monitor-related settings into the target settings object.
    func apply(to settings: inout DimlySettings) {
        settings.displayAliases = displayAliases
        settings.overlayOnlyDisplayIDs = overlayOnlyDisplayIDs
        settings.menuBarExcludedDisplayIDs = menuBarExcludedDisplayIDs
        settings.menuBarIncludedInternalDisplayIDs = menuBarIncludedInternalDisplayIDs
        settings.mergeInternalAndExternalDisplays = mergeInternalAndExternalDisplays
        settings.externalDisplayOrder = externalDisplayOrder
        settings.internalDisplayOrder = internalDisplayOrder
        settings.mergedDisplayOrder = mergedDisplayOrder
        settings.externalDisplayRows = externalDisplayRows
        settings.internalDisplayRows = internalDisplayRows
        settings.mergedDisplayRows = mergedDisplayRows
        settings.brightnessPanelExpandedDisplayIDs = brightnessPanelExpandedDisplayIDs
        settings.monitorBrightnessByDisplayID = monitorBrightnessByDisplayID
        settings.monitorPowerStateByDisplayID = monitorPowerStateByDisplayID
        settings.monitorContrastByDisplayID = monitorContrastByDisplayID
        settings.monitorInputSourceByDisplayID = monitorInputSourceByDisplayID
        settings.monitorDisplayModeByDisplayID = monitorDisplayModeByDisplayID
        settings.monitorColorProfileByDisplayID = monitorColorProfileByDisplayID
        settings.displayFilterByDisplayID = displayFilterByDisplayID
        settings.activeLUTByDisplayID = activeLUTByDisplayID
        settings.trueToneEnabledByDisplayID = trueToneEnabledByDisplayID
    }
}
