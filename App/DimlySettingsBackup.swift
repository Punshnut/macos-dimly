import Foundation

enum SettingsBackupType: String, Codable {
    case general
    case monitor
    case generalAndMonitor

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

struct DimlySettingsBackup: Codable {
    let version: Int
    let exportedAt: Date
    let type: SettingsBackupType
    let general: GeneralSettingsPayload?
    let monitor: MonitorSettingsPayload?

    init(settings: DimlySettings, type: SettingsBackupType, exportedAt: Date = Date()) {
        self.version = 1
        self.exportedAt = exportedAt
        self.type = type
        self.general = type.includesGeneral ? GeneralSettingsPayload(from: settings) : nil
        self.monitor = type.includesMonitor ? MonitorSettingsPayload(from: settings) : nil
    }

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
}

struct GeneralSettingsPayload: Codable {
    let launchAtLogin: Bool
    let showMenuBarIcon: Bool
    let hideDockIcon: Bool
    let hotkeyBindings: [HotkeyBinding]
    let showDisplayNumbers: Bool
    let fadeOutAnimationEnabled: Bool
    let fadeInAnimationEnabled: Bool
    let menuBarSimpleMode: Bool

    init(from settings: DimlySettings) {
        launchAtLogin = settings.launchAtLogin
        showMenuBarIcon = settings.showMenuBarIcon
        hideDockIcon = settings.hideDockIcon
        hotkeyBindings = settings.hotkeyBindings
        showDisplayNumbers = settings.showDisplayNumbers
        fadeOutAnimationEnabled = settings.fadeOutAnimationEnabled
        fadeInAnimationEnabled = settings.fadeInAnimationEnabled
        menuBarSimpleMode = settings.menuBarSimpleMode
    }

    func apply(to settings: inout DimlySettings) {
        settings.launchAtLogin = launchAtLogin
        settings.showMenuBarIcon = showMenuBarIcon
        settings.hideDockIcon = hideDockIcon
        settings.hotkeyBindings = hotkeyBindings
        settings.showDisplayNumbers = showDisplayNumbers
        settings.fadeOutAnimationEnabled = fadeOutAnimationEnabled
        settings.fadeInAnimationEnabled = fadeInAnimationEnabled
        settings.menuBarSimpleMode = menuBarSimpleMode
    }
}

struct MonitorSettingsPayload: Codable {
    let displayAliases: [String: String]
    let overlayOnlyDisplayIDs: [String]
    let externalDisplayOrder: [String]
    let brightnessPanelExpandedDisplayIDs: [String]
    let monitorBrightnessByDisplayID: [String: Int]
    let monitorPowerStateByDisplayID: [String: PersistedMonitorPowerState]

    private enum CodingKeys: String, CodingKey {
        case displayAliases
        case overlayOnlyDisplayIDs
        case externalDisplayOrder
        case brightnessPanelExpandedDisplayIDs
        case monitorBrightnessByDisplayID
        case monitorPowerStateByDisplayID
    }

    init(from settings: DimlySettings) {
        displayAliases = settings.displayAliases
        overlayOnlyDisplayIDs = settings.overlayOnlyDisplayIDs
        externalDisplayOrder = settings.externalDisplayOrder
        brightnessPanelExpandedDisplayIDs = settings.brightnessPanelExpandedDisplayIDs
        monitorBrightnessByDisplayID = settings.monitorBrightnessByDisplayID
        monitorPowerStateByDisplayID = settings.monitorPowerStateByDisplayID
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        displayAliases = try container.decodeIfPresent([String: String].self, forKey: .displayAliases) ?? [:]
        overlayOnlyDisplayIDs = try container.decodeIfPresent([String].self, forKey: .overlayOnlyDisplayIDs) ?? []
        externalDisplayOrder = try container.decodeIfPresent([String].self, forKey: .externalDisplayOrder) ?? []
        brightnessPanelExpandedDisplayIDs = try container.decodeIfPresent([String].self, forKey: .brightnessPanelExpandedDisplayIDs) ?? []
        monitorBrightnessByDisplayID = try container.decodeIfPresent([String: Int].self, forKey: .monitorBrightnessByDisplayID) ?? [:]
        monitorPowerStateByDisplayID = try container.decodeIfPresent([String: PersistedMonitorPowerState].self, forKey: .monitorPowerStateByDisplayID) ?? [:]
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(displayAliases, forKey: .displayAliases)
        try container.encode(overlayOnlyDisplayIDs, forKey: .overlayOnlyDisplayIDs)
        try container.encode(externalDisplayOrder, forKey: .externalDisplayOrder)
        try container.encode(brightnessPanelExpandedDisplayIDs, forKey: .brightnessPanelExpandedDisplayIDs)
        try container.encode(monitorBrightnessByDisplayID, forKey: .monitorBrightnessByDisplayID)
        try container.encode(monitorPowerStateByDisplayID, forKey: .monitorPowerStateByDisplayID)
    }

    func apply(to settings: inout DimlySettings) {
        settings.displayAliases = displayAliases
        settings.overlayOnlyDisplayIDs = overlayOnlyDisplayIDs
        settings.externalDisplayOrder = externalDisplayOrder
        settings.brightnessPanelExpandedDisplayIDs = brightnessPanelExpandedDisplayIDs
        settings.monitorBrightnessByDisplayID = monitorBrightnessByDisplayID
        settings.monitorPowerStateByDisplayID = monitorPowerStateByDisplayID
    }
}
