// MARK: - Profile Automation
// Captures display snapshots, stores named profiles, and re-applies them when hardware changes.
import Foundation
import Combine
import OSLog
import AppKit
import CoreGraphics

/// Normalized power state used by display profiles.
enum DisplayPowerState: String, Codable {
    case visible
    case asleep
}

/// Curated color presets for smart profile buttons.
enum SmartButtonColorPreset: String, Codable, CaseIterable, Identifiable {
    case sunset
    case violet
    case mint
    case rose
    case amber
    case lime
    case ruby
    case ocean
    case magenta
    case pine
    case teal
    case coral
    case lavender
    case gold
    case tangerine
    case indigo
    case emerald
    case sky
    case copper
    case slate

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .sunset:
            return String(localized: "ColorSunsetLabel")
        case .ocean:
            return String(localized: "ColorOceanLabel")
        case .mint:
            return String(localized: "ColorMintLabel")
        case .violet:
            return String(localized: "ColorVioletLabel")
        case .amber:
            return String(localized: "ColorAmberLabel")
        case .rose:
            return String(localized: "ColorRoseLabel")
        case .lime:
            return String(localized: "ColorLimeLabel")
        case .slate:
            return String(localized: "ColorSlateLabel")
        case .teal:
            return String(localized: "ColorTealLabel")
        case .indigo:
            return String(localized: "ColorIndigoLabel")
        case .coral:
            return String(localized: "ColorCoralLabel")
        case .copper:
            return String(localized: "ColorCopperLabel")
        case .emerald:
            return String(localized: "ColorEmeraldLabel")
        case .sky:
            return String(localized: "ColorSkyLabel")
        case .magenta:
            return String(localized: "ColorMagentaLabel")
        case .gold:
            return String(localized: "ColorGoldLabel")
        case .ruby:
            return String(localized: "ColorRubyLabel")
        case .lavender:
            return String(localized: "ColorLavenderLabel")
        case .pine:
            return String(localized: "ColorPineLabel")
        case .tangerine:
            return String(localized: "ColorTangerineLabel")
        }
    }
}

/// Snapshot of a single display used inside profiles.
struct DisplaySnapshot: Codable, Equatable, Identifiable {
    let id: String
    let uuid: String?
    let serialNumber: Int?
    let vendorNumber: Int?
    let modelNumber: Int?
    let name: String?
    let isBuiltin: Bool?
    let isPrimary: Bool
    let resolution: String
    let refreshRateHz: Double?
    let powerState: DisplayPowerState
    let brightnessPercent: Int?

    /// Builds a snapshot from live display info.
    init(from info: DisplayInfo, powerState: DisplayPowerState, brightnessPercent: Int?) {
        id = info.stableIdentity
        uuid = info.uuid
        serialNumber = info.serialNumber
        vendorNumber = info.vendorNumber
        modelNumber = info.modelNumber
        name = info.name
        isBuiltin = info.isBuiltin
        isPrimary = info.displayID == CGMainDisplayID()
        resolution = info.resolution
        refreshRateHz = info.refreshRateHz
        self.powerState = powerState
        self.brightnessPercent = brightnessPercent.map { max(0, min(100, $0)) }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case serialNumber
        case vendorNumber
        case modelNumber
        case name
        case isBuiltin
        case isPrimary
        case resolution
        case refreshRateHz
        case powerState
        case brightnessPercent
    }

    /// Decodes a saved display snapshot while preserving compatibility with older profile formats.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        uuid = try container.decodeIfPresent(String.self, forKey: .uuid)
        serialNumber = try container.decodeIfPresent(Int.self, forKey: .serialNumber)
        vendorNumber = try container.decodeIfPresent(Int.self, forKey: .vendorNumber)
        modelNumber = try container.decodeIfPresent(Int.self, forKey: .modelNumber)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isBuiltin = try container.decodeIfPresent(Bool.self, forKey: .isBuiltin)
        isPrimary = try container.decode(Bool.self, forKey: .isPrimary)
        resolution = try container.decode(String.self, forKey: .resolution)
        refreshRateHz = try container.decodeIfPresent(Double.self, forKey: .refreshRateHz)
        powerState = try container.decodeIfPresent(DisplayPowerState.self, forKey: .powerState) ?? .visible
        brightnessPercent = try container.decodeIfPresent(Int.self, forKey: .brightnessPercent)
    }

    /// Encodes a display snapshot, preserving optional hardware identity fields.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(uuid, forKey: .uuid)
        try container.encodeIfPresent(serialNumber, forKey: .serialNumber)
        try container.encodeIfPresent(vendorNumber, forKey: .vendorNumber)
        try container.encodeIfPresent(modelNumber, forKey: .modelNumber)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encodeIfPresent(isBuiltin, forKey: .isBuiltin)
        try container.encode(isPrimary, forKey: .isPrimary)
        try container.encode(resolution, forKey: .resolution)
        try container.encodeIfPresent(refreshRateHz, forKey: .refreshRateHz)
        try container.encode(powerState, forKey: .powerState)
        try container.encodeIfPresent(brightnessPercent, forKey: .brightnessPercent)
    }
}

/// Maps a display connection event to a profile to auto-apply.
struct DisplayConnectionRule: Codable, Identifiable, Equatable {
    var id: UUID
    var isEnabled: Bool
    var profileID: UUID
    /// stableIdentity of the triggering display; empty string means any external display.
    var displayID: String
    /// Cached display name for showing the rule when the display is offline.
    var displayName: String?
}

/// A named set of display snapshots captured at a point in time.
struct DisplayProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    var displays: [DisplaySnapshot]
    var monitorState: ProfileMonitorState?
    var showInSmartButtons: Bool = true
    var smartButtonColorPreset: SmartButtonColorPreset?
    var autoColorPreset: SmartButtonColorPreset?

    /// Creates a named profile from captured display snapshots and optional monitor metadata.
    init(
        id: UUID,
        name: String,
        createdAt: Date,
        displays: [DisplaySnapshot],
        monitorState: ProfileMonitorState?,
        showInSmartButtons: Bool = true,
        smartButtonColorPreset: SmartButtonColorPreset? = nil,
        autoColorPreset: SmartButtonColorPreset? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.displays = displays
        self.monitorState = monitorState
        self.showInSmartButtons = showInSmartButtons
        self.smartButtonColorPreset = smartButtonColorPreset
        self.autoColorPreset = autoColorPreset
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case displays
        case monitorState
        case showInSmartButtons
        case smartButtonColorPreset
        case autoColorPreset
    }

    /// Decodes a saved profile and backfills newer UI metadata with sensible defaults.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        displays = try container.decode([DisplaySnapshot].self, forKey: .displays)
        monitorState = try container.decodeIfPresent(ProfileMonitorState.self, forKey: .monitorState)
        showInSmartButtons = try container.decodeIfPresent(Bool.self, forKey: .showInSmartButtons) ?? true
        smartButtonColorPreset = try container.decodeIfPresent(SmartButtonColorPreset.self, forKey: .smartButtonColorPreset)
        autoColorPreset = try container.decodeIfPresent(SmartButtonColorPreset.self, forKey: .autoColorPreset)
    }

    /// Encodes profile metadata and captured display snapshots.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(displays, forKey: .displays)
        try container.encodeIfPresent(monitorState, forKey: .monitorState)
        try container.encode(showInSmartButtons, forKey: .showInSmartButtons)
        try container.encodeIfPresent(smartButtonColorPreset, forKey: .smartButtonColorPreset)
        try container.encodeIfPresent(autoColorPreset, forKey: .autoColorPreset)
    }
}

extension Array where Element == DisplayProfile {
    /// Returns a transient profile order with two profile IDs swapped for drag previews.
    func swappingProfiles(_ firstID: UUID?, with secondID: UUID?) -> [DisplayProfile] {
        guard let firstID, let secondID, firstID != secondID else { return self }
        guard let sourceIndex = firstIndex(where: { $0.id == firstID }),
              let targetIndex = firstIndex(where: { $0.id == secondID }) else { return self }

        var swapped = self
        swapped.swapAt(sourceIndex, targetIndex)
        return swapped
    }
}

/// Monitor-related UI + brightness state captured inside a profile.
struct ProfileMonitorState: Codable, Equatable {
    var menuBarExcludedDisplayIDs: [String]
    var menuBarIncludedInternalDisplayIDs: [String]
    var externalDisplayOrder: [String]
    var internalDisplayOrder: [String]
    var brightnessPanelExpandedDisplayIDs: [String]
    var monitorPowerStateByDisplayID: [String: PersistedMonitorPowerState]
    var monitorBrightnessByDisplayID: [String: Int]

    private enum CodingKeys: String, CodingKey {
        case menuBarExcludedDisplayIDs
        case menuBarIncludedInternalDisplayIDs
        case externalDisplayOrder
        case internalDisplayOrder
        case brightnessPanelExpandedDisplayIDs
        case monitorPowerStateByDisplayID
        case monitorBrightnessByDisplayID
    }

    /// Creates the monitor-specific portion of a profile snapshot.
    init(
        menuBarExcludedDisplayIDs: [String],
        menuBarIncludedInternalDisplayIDs: [String],
        externalDisplayOrder: [String],
        internalDisplayOrder: [String],
        brightnessPanelExpandedDisplayIDs: [String],
        monitorPowerStateByDisplayID: [String: PersistedMonitorPowerState],
        monitorBrightnessByDisplayID: [String: Int]
    ) {
        self.menuBarExcludedDisplayIDs = menuBarExcludedDisplayIDs
        self.menuBarIncludedInternalDisplayIDs = menuBarIncludedInternalDisplayIDs
        self.externalDisplayOrder = externalDisplayOrder
        self.internalDisplayOrder = internalDisplayOrder
        self.brightnessPanelExpandedDisplayIDs = brightnessPanelExpandedDisplayIDs
        self.monitorPowerStateByDisplayID = monitorPowerStateByDisplayID
        self.monitorBrightnessByDisplayID = monitorBrightnessByDisplayID
    }

    /// Captures monitor ordering and per-display state from the current live settings.
    init(from settings: DimlySettings) {
        menuBarExcludedDisplayIDs = settings.menuBarExcludedDisplayIDs
        menuBarIncludedInternalDisplayIDs = settings.menuBarIncludedInternalDisplayIDs
        externalDisplayOrder = settings.externalDisplayOrder
        internalDisplayOrder = settings.internalDisplayOrder
        brightnessPanelExpandedDisplayIDs = settings.brightnessPanelExpandedDisplayIDs
        monitorPowerStateByDisplayID = settings.monitorPowerStateByDisplayID
        monitorBrightnessByDisplayID = settings.monitorBrightnessByDisplayID
    }

    /// Decodes saved monitor UI state while tolerating fields that may be absent in older profiles.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        menuBarExcludedDisplayIDs = try container.decodeIfPresent([String].self, forKey: .menuBarExcludedDisplayIDs) ?? []
        menuBarIncludedInternalDisplayIDs = try container.decodeIfPresent([String].self, forKey: .menuBarIncludedInternalDisplayIDs) ?? []
        externalDisplayOrder = try container.decodeIfPresent([String].self, forKey: .externalDisplayOrder) ?? []
        internalDisplayOrder = try container.decodeIfPresent([String].self, forKey: .internalDisplayOrder) ?? []
        brightnessPanelExpandedDisplayIDs = try container.decodeIfPresent([String].self, forKey: .brightnessPanelExpandedDisplayIDs) ?? []
        monitorPowerStateByDisplayID = try container.decodeIfPresent([String: PersistedMonitorPowerState].self, forKey: .monitorPowerStateByDisplayID) ?? [:]
        monitorBrightnessByDisplayID = try container.decodeIfPresent([String: Int].self, forKey: .monitorBrightnessByDisplayID) ?? [:]
    }

    /// Encodes monitor-specific profile state for persistence and backup export.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(menuBarExcludedDisplayIDs, forKey: .menuBarExcludedDisplayIDs)
        try container.encode(menuBarIncludedInternalDisplayIDs, forKey: .menuBarIncludedInternalDisplayIDs)
        try container.encode(externalDisplayOrder, forKey: .externalDisplayOrder)
        try container.encode(internalDisplayOrder, forKey: .internalDisplayOrder)
        try container.encode(brightnessPanelExpandedDisplayIDs, forKey: .brightnessPanelExpandedDisplayIDs)
        try container.encode(monitorPowerStateByDisplayID, forKey: .monitorPowerStateByDisplayID)
        try container.encode(monitorBrightnessByDisplayID, forKey: .monitorBrightnessByDisplayID)
    }

    /// Applies captured monitor-related UI state back into live app settings.
    func apply(to settings: inout DimlySettings) {
        settings.menuBarExcludedDisplayIDs = menuBarExcludedDisplayIDs
        settings.menuBarIncludedInternalDisplayIDs = menuBarIncludedInternalDisplayIDs
        settings.externalDisplayOrder = externalDisplayOrder
        settings.internalDisplayOrder = internalDisplayOrder
        settings.brightnessPanelExpandedDisplayIDs = brightnessPanelExpandedDisplayIDs
        settings.monitorPowerStateByDisplayID = monitorPowerStateByDisplayID
        settings.monitorBrightnessByDisplayID = monitorBrightnessByDisplayID
    }

    /// Rewrites monitor IDs using profile snapshot -> current display mappings.
    func remapped(using idMap: [String: String]) -> ProfileMonitorState {
        ProfileMonitorState(
            menuBarExcludedDisplayIDs: remap(menuBarExcludedDisplayIDs, with: idMap),
            menuBarIncludedInternalDisplayIDs: remap(menuBarIncludedInternalDisplayIDs, with: idMap),
            externalDisplayOrder: remap(externalDisplayOrder, with: idMap),
            internalDisplayOrder: remap(internalDisplayOrder, with: idMap),
            brightnessPanelExpandedDisplayIDs: remap(brightnessPanelExpandedDisplayIDs, with: idMap),
            monitorPowerStateByDisplayID: remap(monitorPowerStateByDisplayID, with: idMap),
            monitorBrightnessByDisplayID: remap(monitorBrightnessByDisplayID, with: idMap)
        )
    }

    /// Remaps an ordered ID list while preserving order and removing duplicates.
    private func remap(_ ids: [String], with idMap: [String: String]) -> [String] {
        var remapped: [String] = []
        var seen: Set<String> = []
        for id in ids {
            let resolved = idMap[id] ?? id
            guard seen.contains(resolved) == false else { continue }
            remapped.append(resolved)
            seen.insert(resolved)
        }
        return remapped
    }

    /// Remaps dictionary keys from snapshot IDs to current display IDs.
    private func remap(_ values: [String: Int], with idMap: [String: String]) -> [String: Int] {
        var remapped: [String: Int] = [:]
        for (id, value) in values {
            remapped[idMap[id] ?? id] = value
        }
        return remapped
    }

    /// Remaps dictionary keys from snapshot IDs to current display IDs.
    private func remap(
        _ values: [String: PersistedMonitorPowerState],
        with idMap: [String: String]
    ) -> [String: PersistedMonitorPowerState] {
        var remapped: [String: PersistedMonitorPowerState] = [:]
        for (id, value) in values {
            remapped[idMap[id] ?? id] = value
        }
        return remapped
    }
}

/// Persisted profile list + automation settings.
struct ProfileState: Codable {
    var profiles: [DisplayProfile]
    var automationEnabled: Bool
    var automationProfileID: UUID?
    var automationTriggerTarget: HotkeyTarget
    var connectionRules: [DisplayConnectionRule]

    private enum CodingKeys: String, CodingKey {
        case profiles
        case automationEnabled
        case automationProfileID
        case automationTriggerTarget
        case connectionRules
    }

    /// Creates the full persisted profile payload, including automation preferences.
    init(
        profiles: [DisplayProfile],
        automationEnabled: Bool,
        automationProfileID: UUID?,
        automationTriggerTarget: HotkeyTarget,
        connectionRules: [DisplayConnectionRule]
    ) {
        self.profiles = profiles
        self.automationEnabled = automationEnabled
        self.automationProfileID = automationProfileID
        self.automationTriggerTarget = automationTriggerTarget
        self.connectionRules = connectionRules
    }

    /// Decodes persisted profile state, migrating old single-rule automation to connectionRules if needed.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        profiles = try container.decode([DisplayProfile].self, forKey: .profiles)
        automationEnabled = try container.decodeIfPresent(Bool.self, forKey: .automationEnabled) ?? false
        automationProfileID = try container.decodeIfPresent(UUID.self, forKey: .automationProfileID)
        automationTriggerTarget = try container.decodeIfPresent(HotkeyTarget.self, forKey: .automationTriggerTarget) ?? .allExternalDisplays

        var rules = try container.decodeIfPresent([DisplayConnectionRule].self, forKey: .connectionRules) ?? []
        // Migrate from the old single-rule format on first load.
        if rules.isEmpty, let oldProfileID = automationProfileID, automationEnabled {
            let displayID: String
            switch automationTriggerTarget {
            case .allExternalDisplays: displayID = ""
            case .display(let id): displayID = id
            }
            rules = [DisplayConnectionRule(id: UUID(), isEnabled: true, profileID: oldProfileID, displayID: displayID, displayName: nil)]
        }
        connectionRules = rules
    }
}

/// Manages saved display profiles and automation triggered by external-display changes.
@MainActor
final class ProfileManager: ObservableObject {
    @Published private(set) var profiles: [DisplayProfile] = []
    @Published var automationEnabled: Bool = false {
        didSet { persist() }
    }
    @Published var automationProfileID: UUID? {
        didSet { persist() }
    }
    @Published var automationTriggerTarget: HotkeyTarget = .allExternalDisplays {
        didSet { persist() }
    }
    @Published var connectionRules: [DisplayConnectionRule] = [] {
        didSet { persist() }
    }
    @Published var lastAppliedProfileName: String?

    private let displayManager: DisplayManager
    private let blackoutManager: BlackoutManager
    private let ddcManager: DDCManager
    private let settingsStore: AppSettingsStore
    weak var engine: DimlyEngine?
    private let store: ProfileStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "Profiles")
    private var cancellables: Set<AnyCancellable> = []
    private var previousDisplayIDs: Set<String> = []
    private var profileApplyGeneration: UInt64 = 0
    private var pendingProfileBrightnessTasks: [Task<Void, Never>] = []
    private var workspaceWakeToken: NSObjectProtocol?
    private var workspaceScreensWakeToken: NSObjectProtocol?
    private var workspaceSessionDidResignToken: NSObjectProtocol?
    private var workspaceSessionDidBecomeToken: NSObjectProtocol?
    private var distributedScreenLockedToken: NSObjectProtocol?
    private var distributedScreenUnlockedToken: NSObjectProtocol?
    private var automationSuppressedUntil: Date = .distantPast
    private let wakeAutomationSuppressWindow: TimeInterval = 12

    /// Loads profiles and starts observing display changes for automation.
    init(
        displayManager: DisplayManager,
        blackoutManager: BlackoutManager,
        ddcManager: DDCManager,
        settingsStore: AppSettingsStore,
        store: ProfileStore = ProfileStore()
    ) {
        self.displayManager = displayManager
        self.blackoutManager = blackoutManager
        self.ddcManager = ddcManager
        self.settingsStore = settingsStore
        self.store = store

        let loaded = store.load()
        profiles = loaded.profiles
        automationEnabled = loaded.automationEnabled
        automationProfileID = loaded.automationProfileID
        automationTriggerTarget = loaded.automationTriggerTarget
        connectionRules = loaded.connectionRules

        previousDisplayIDs = Set(displayManager.displays.map(\.stableIdentity))

        displayManager.$displays
            .sink { [weak self] displays in
                self?.handleDisplayChange(displays)
            }
            .store(in: &cancellables)

        workspaceWakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.suppressAutomation(for: self.wakeAutomationSuppressWindow, reason: "workspaceDidWake")
            }
        }
        workspaceScreensWakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.suppressAutomation(for: self.wakeAutomationSuppressWindow, reason: "workspaceScreensDidWake")
            }
        }
        workspaceSessionDidResignToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.suppressAutomation(for: self.wakeAutomationSuppressWindow, reason: "workspaceSessionDidResign")
            }
        }
        workspaceSessionDidBecomeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.suppressAutomation(for: self.wakeAutomationSuppressWindow, reason: "workspaceSessionDidBecome")
            }
        }
        let distributedCenter = DistributedNotificationCenter.default()
        distributedScreenLockedToken = distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsLocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.suppressAutomation(for: self.wakeAutomationSuppressWindow, reason: "distributedScreenLocked")
            }
        }
        distributedScreenUnlockedToken = distributedCenter.addObserver(
            forName: Notification.Name("com.apple.screenIsUnlocked"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.suppressAutomation(for: self.wakeAutomationSuppressWindow, reason: "distributedScreenUnlocked")
            }
        }
    }

    @MainActor
    deinit {
        if let workspaceWakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceWakeToken)
        }
        if let workspaceScreensWakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceScreensWakeToken)
        }
        if let workspaceSessionDidResignToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceSessionDidResignToken)
        }
        if let workspaceSessionDidBecomeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceSessionDidBecomeToken)
        }
        let distributedCenter = DistributedNotificationCenter.default()
        if let distributedScreenLockedToken {
            distributedCenter.removeObserver(distributedScreenLockedToken)
        }
        if let distributedScreenUnlockedToken {
            distributedCenter.removeObserver(distributedScreenUnlockedToken)
        }
    }

    // MARK: - Profile CRUD

    /// Captures the current display state into a new named profile.
    func saveCurrentProfile(named name: String) {
        let snapshots = captureCurrentDisplaySnapshots()
        let newID = UUID()
        let usedColors = Set(profiles.compactMap { $0.smartButtonColorPreset ?? $0.autoColorPreset })
        let allPresets = SmartButtonColorPreset.allCases
        let autoColor: SmartButtonColorPreset = allPresets.first(where: { !usedColors.contains($0) }) ?? {
            var hash: UInt64 = 1469598103934665603
            for byte in newID.uuidString.lowercased().utf8 {
                hash ^= UInt64(byte)
                hash &*= 1099511628211
            }
            return allPresets[Int(hash % UInt64(allPresets.count))]
        }()
        let profile = DisplayProfile(
            id: newID,
            name: name.isEmpty
                ? String(format: String(localized: "ProfileDefaultNameFormat"), Int64(profiles.count + 1))
                : name,
            createdAt: Date(),
            displays: snapshots,
            monitorState: ProfileMonitorState(from: settingsStore.settings),
            showInSmartButtons: true,
            autoColorPreset: autoColor
        )
        profiles.append(profile)
        persist()
    }

    /// Replaces a saved profile's captured state with the current live setup.
    func overwriteProfileWithCurrentSettings(_ profile: DisplayProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        var updated = profiles[index]
        updated.displays = captureCurrentDisplaySnapshots()
        updated.monitorState = ProfileMonitorState(from: settingsStore.settings)
        profiles[index] = updated
        persist()
    }

    /// Applies a profile to current displays, logging missing targets.
    func apply(profile: DisplayProfile) {
        pendingProfileBrightnessTasks.forEach { $0.cancel() }
        pendingProfileBrightnessTasks.removeAll()
        profileApplyGeneration &+= 1
        let applyGeneration = profileApplyGeneration
        DiagnosticsLogger.shared.log(
            "Apply profile name=\(profile.name) generation=\(applyGeneration)",
            category: "profile"
        )

        let currentDisplays = displayManager.displays
        let matched = resolveSnapshotMappings(profile.displays, to: currentDisplays)
        let appliedSnapshotIDs = Set(matched.map(\.snapshot.id))
        let expectedIDs = Set(profile.displays.map(\.id))
        let missing = expectedIDs.subtracting(appliedSnapshotIDs)
        let idMap = Dictionary(uniqueKeysWithValues: matched.map { ($0.snapshot.id, $0.display.stableIdentity) })
        let remappedMonitorState = profile.monitorState?.remapped(using: idMap)
        let runtimePowerStateByDisplayID = Dictionary(
            uniqueKeysWithValues: matched.map { ($0.display.stableIdentity, currentRuntimePowerState(for: $0.display)) }
        )
        let desiredPowerStateByDisplayID = Dictionary(
            uniqueKeysWithValues: matched.map { match in
                (
                    match.display.stableIdentity,
                    desiredPowerState(
                        for: match.snapshot,
                        display: match.display,
                        remappedMonitorState: remappedMonitorState
                    )
                )
            }
        )

        if remappedMonitorState != nil || !desiredPowerStateByDisplayID.isEmpty {
            settingsStore.update { settings in
                remappedMonitorState?.apply(to: &settings)
                for (displayID, powerState) in desiredPowerStateByDisplayID {
                    settings.monitorPowerStateByDisplayID[displayID] = powerState
                }
            }
        }

        let shouldAnimateBrightness = settingsStore.settings.fadeOutAnimationEnabled || settingsStore.settings.fadeInAnimationEnabled

        var appliedCount = 0
        var immediateBrightnessTargets: [(display: DisplayInfo, percent: Int)] = []
        var delayedBrightnessTargets: [(display: DisplayInfo, percent: Int)] = []
        var retryBrightnessTargets: [(display: DisplayInfo, percent: Int)] = []

        for (snapshot, display) in matched {
            let desiredPowerState = desiredPowerStateByDisplayID[display.stableIdentity]
                ?? desiredPowerState(for: snapshot, display: display, remappedMonitorState: remappedMonitorState)
            let currentState = runtimePowerStateByDisplayID[display.stableIdentity] ?? .visible
            if currentState != desiredPowerState {
                applyPowerState(desiredPowerState, to: display)
            }
            if desiredPowerState == .visible, let brightness = snapshot.brightnessPercent,
               !display.isAutoBrightnessEnabled {
                let clamped = max(0, min(100, brightness))
                let needsPostWakeStabilization = display.isExternal && (
                    currentState != .visible ||
                    ddcManager.states[display.stableIdentity]?.status != .supported
                )
                if currentState != .visible {
                    delayedBrightnessTargets.append((display: display, percent: clamped))
                } else {
                    immediateBrightnessTargets.append((display: display, percent: clamped))
                }
                if needsPostWakeStabilization {
                    retryBrightnessTargets.append((display: display, percent: clamped))
                }
            }
            appliedCount += 1
        }
        if let engine {
            let deduplicatedImmediate = deduplicatedBrightnessTargets(immediateBrightnessTargets)
            engine.setBrightnessSynchronously(deduplicatedImmediate, animated: shouldAnimateBrightness)
            if !delayedBrightnessTargets.isEmpty {
                scheduleProfileBrightnessApply(
                    targets: deduplicatedBrightnessTargets(delayedBrightnessTargets),
                    afterNanoseconds: 550_000_000,
                    generation: applyGeneration,
                    phase: "postWakeDelay"
                )
            }
            if !retryBrightnessTargets.isEmpty {
                let deduplicatedRetry = deduplicatedBrightnessTargets(retryBrightnessTargets)
                scheduleProfileBrightnessApply(
                    targets: deduplicatedRetry,
                    afterNanoseconds: 1_600_000_000,
                    generation: applyGeneration,
                    phase: "retry1"
                )
                scheduleProfileBrightnessApply(
                    targets: deduplicatedRetry,
                    afterNanoseconds: 3_000_000_000,
                    generation: applyGeneration,
                    phase: "retry2"
                )
            }
        }

        if missing.isEmpty {
            logger.notice("Applied profile \(profile.name, privacy: .public) to \(appliedCount, privacy: .public) displays")
        } else {
            let missingList = missing.joined(separator: ", ")
            logger.info("Applied profile \(profile.name, privacy: .public) partially to \(appliedCount, privacy: .public) displays; missing: \(missingList, privacy: .public)")
        }
        lastAppliedProfileName = profile.name
    }

    /// Schedules one delayed profile-brightness phase that is canceled by newer applies.
    private func scheduleProfileBrightnessApply(
        targets: [(display: DisplayInfo, percent: Int)],
        afterNanoseconds delay: UInt64,
        generation: UInt64,
        phase: String
    ) {
        guard !targets.isEmpty else { return }
        let task = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard let self else { return }
            guard !Task.isCancelled else { return }
            guard self.profileApplyGeneration == generation else {
                DiagnosticsLogger.shared.log(
                    "Skip stale profile brightness phase=\(phase) generation=\(generation) latest=\(self.profileApplyGeneration)",
                    category: "profile"
                )
                return
            }
            guard let engine = self.engine else { return }
            DiagnosticsLogger.shared.log(
                "Run profile brightness phase=\(phase) generation=\(generation) targets=\(targets.count)",
                category: "profile"
            )
            for target in targets {
                self.applyProfileBrightnessTargetIfNeeded(
                    target,
                    engine: engine,
                    generation: generation,
                    phase: phase
                )
            }
        }
        pendingProfileBrightnessTasks.append(task)
    }

    /// Applies one profile brightness target only when it still meaningfully differs.
    private func applyProfileBrightnessTargetIfNeeded(
        _ target: (display: DisplayInfo, percent: Int),
        engine: DimlyEngine,
        generation: UInt64,
        phase: String
    ) {
        guard profileApplyGeneration == generation else { return }
        let clamped = max(0, min(100, target.percent))
        let currentState = currentRuntimePowerState(for: target.display)
        let currentBrightness = engine.brightnessPercent(for: target.display)
        if currentState == .visible, abs(currentBrightness - clamped) <= 1 {
            DiagnosticsLogger.shared.log(
                "Skip profile brightness noop id=\(target.display.stableIdentity) phase=\(phase) current=\(currentBrightness) target=\(clamped)",
                category: "profile"
            )
            return
        }
        DiagnosticsLogger.shared.log(
            "Apply profile brightness id=\(target.display.stableIdentity) phase=\(phase) current=\(currentBrightness) target=\(clamped)",
            category: "profile"
        )
        engine.setBrightness(clamped, for: target.display, animated: false)
    }

    /// Coalesces duplicate display entries while preserving ordering.
    private func deduplicatedBrightnessTargets(
        _ targets: [(display: DisplayInfo, percent: Int)]
    ) -> [(display: DisplayInfo, percent: Int)] {
        var ordered: [(display: DisplayInfo, percent: Int)] = []
        var indexByDisplayID: [String: Int] = [:]
        for target in targets {
            let id = target.display.stableIdentity
            let clamped = max(0, min(100, target.percent))
            if let index = indexByDisplayID[id] {
                ordered[index] = (display: target.display, percent: clamped)
            } else {
                indexByDisplayID[id] = ordered.count
                ordered.append((display: target.display, percent: clamped))
            }
        }
        return ordered
    }

    /// Resolves profile snapshots to currently connected displays with robust fallback matching.
    private func resolveSnapshotMappings(
        _ snapshots: [DisplaySnapshot],
        to currentDisplays: [DisplayInfo]
    ) -> [(snapshot: DisplaySnapshot, display: DisplayInfo)] {
        var result: [(snapshot: DisplaySnapshot, display: DisplayInfo)] = []
        var unmatchedDisplaysByID = Dictionary(uniqueKeysWithValues: currentDisplays.map { ($0.stableIdentity, $0) })
        var unmatchedSnapshots: [DisplaySnapshot] = []

        for snapshot in snapshots {
            if let exact = unmatchedDisplaysByID.removeValue(forKey: snapshot.id) {
                result.append((snapshot: snapshot, display: exact))
            } else {
                unmatchedSnapshots.append(snapshot)
            }
        }

        typealias Candidate = (snapshot: DisplaySnapshot, display: DisplayInfo, score: Int)
        var candidates: [Candidate] = []
        for snapshot in unmatchedSnapshots {
            for display in unmatchedDisplaysByID.values {
                let score = snapshotMatchScore(snapshot: snapshot, display: display)
                if score >= 70 {
                    candidates.append((snapshot: snapshot, display: display, score: score))
                }
            }
        }
        candidates.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.snapshot.id != $1.snapshot.id { return $0.snapshot.id < $1.snapshot.id }
            return $0.display.stableIdentity < $1.display.stableIdentity
        }

        var usedSnapshots = Set<String>()
        var usedDisplays = Set<String>()
        for candidate in candidates {
            let snapshotID = candidate.snapshot.id
            let displayID = candidate.display.stableIdentity
            guard usedSnapshots.contains(snapshotID) == false else { continue }
            guard usedDisplays.contains(displayID) == false else { continue }
            usedSnapshots.insert(snapshotID)
            usedDisplays.insert(displayID)
            result.append((snapshot: candidate.snapshot, display: candidate.display))
        }

        return result
    }

    /// Scores how likely a current display is to be the same physical panel as a saved snapshot.
    private func snapshotMatchScore(snapshot: DisplaySnapshot, display: DisplayInfo) -> Int {
        if let snapshotIsBuiltin = snapshot.isBuiltin, snapshotIsBuiltin != display.isBuiltin {
            return 0
        }

        var score = 0
        if let uuid = snapshot.uuid, uuid == display.uuid {
            score += 130
        }
        if let serial = snapshot.serialNumber, serial == display.serialNumber {
            score += 90
        }
        if let vendor = snapshot.vendorNumber, let model = snapshot.modelNumber,
           vendor == display.vendorNumber, model == display.modelNumber {
            score += 70
        }
        if normalized(snapshot.name) == normalized(display.name) {
            score += 35
        }
        if snapshot.resolution == display.resolution {
            score += 20
        }
        if let snapshotHz = snapshot.refreshRateHz, let displayHz = display.refreshRateHz,
           abs(snapshotHz - displayHz) < 1 {
            score += 10
        }
        if snapshot.isPrimary == (display.displayID == CGMainDisplayID()) {
            score += 5
        }
        return score
    }

    /// Normalizes optional names for relaxed case-insensitive matching.
    private func normalized(_ value: String?) -> String {
        (value ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// Renames an existing profile.
    func rename(profile: DisplayProfile, to newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].name = newName
        persist()
    }

    /// Deletes a profile and clears automation if it was selected.
    func delete(profile: DisplayProfile) {
        profiles.removeAll { $0.id == profile.id }
        if automationProfileID == profile.id {
            automationProfileID = nil
        }
        persist()
    }

    /// Moves a profile one slot up in the saved order.
    func moveProfileUp(_ profile: DisplayProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }), index > 0 else { return }
        profiles.swapAt(index, index - 1)
        persist()
    }

    /// Moves a profile one slot down in the saved order.
    func moveProfileDown(_ profile: DisplayProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }), index < (profiles.count - 1) else { return }
        profiles.swapAt(index, index + 1)
        persist()
    }

    /// Swaps the saved order of two profiles.
    func swapProfiles(_ firstID: UUID, with secondID: UUID) {
        guard firstID != secondID else { return }
        guard let firstIndex = profiles.firstIndex(where: { $0.id == firstID }),
              let secondIndex = profiles.firstIndex(where: { $0.id == secondID }) else { return }
        profiles.swapAt(firstIndex, secondIndex)
        persist()
    }

    /// Moves a profile to appear before another profile.
    func moveProfile(_ draggedID: UUID, before targetID: UUID) {
        guard draggedID != targetID else { return }
        guard let fromIndex = profiles.firstIndex(where: { $0.id == draggedID }),
              let toIndex = profiles.firstIndex(where: { $0.id == targetID }) else { return }
        let insertionIndex = fromIndex < toIndex ? max(0, toIndex - 1) : toIndex
        guard insertionIndex != fromIndex else { return }
        let profile = profiles.remove(at: fromIndex)
        profiles.insert(profile, at: insertionIndex)
        persist()
    }

    /// Moves a profile to appear after another profile.
    func moveProfile(_ draggedID: UUID, after targetID: UUID) {
        guard draggedID != targetID else { return }
        guard let fromIndex = profiles.firstIndex(where: { $0.id == draggedID }),
              let toIndex = profiles.firstIndex(where: { $0.id == targetID }) else { return }
        let insertionIndex = fromIndex < toIndex ? toIndex : min(profiles.count, toIndex + 1)
        guard insertionIndex != fromIndex else { return }
        let profile = profiles.remove(at: fromIndex)
        profiles.insert(profile, at: insertionIndex)
        persist()
    }

    /// Moves a profile to the end of the saved order.
    func moveProfileToEnd(_ draggedID: UUID) {
        guard let fromIndex = profiles.firstIndex(where: { $0.id == draggedID }) else { return }
        guard fromIndex != (profiles.count - 1) else { return }
        let profile = profiles.remove(at: fromIndex)
        profiles.append(profile)
        persist()
    }

    /// Shows or hides a profile from the menu bar smart buttons section.
    func setSmartButtonVisibility(for profile: DisplayProfile, isVisible: Bool) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        guard profiles[index].showInSmartButtons != isVisible else { return }
        profiles[index].showInSmartButtons = isVisible
        persist()
    }

    /// Sets an optional smart button color preset for a profile (`nil` uses auto).
    func setSmartButtonColorPreset(for profile: DisplayProfile, preset: SmartButtonColorPreset?) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        guard profiles[index].smartButtonColorPreset != preset else { return }
        profiles[index].smartButtonColorPreset = preset
        persist()
    }

    // MARK: - Connection Rules CRUD

    /// Appends a new default connection rule (any external display → first profile).
    func addConnectionRule() {
        let rule = DisplayConnectionRule(
            id: UUID(),
            isEnabled: true,
            profileID: profiles.first?.id ?? UUID(),
            displayID: "",
            displayName: nil
        )
        connectionRules.append(rule)
    }

    /// Removes the connection rule with the given ID.
    func removeConnectionRule(id: UUID) {
        connectionRules.removeAll { $0.id == id }
    }

    /// Replaces the matching connection rule in-place.
    func updateConnectionRule(_ rule: DisplayConnectionRule) {
        guard let index = connectionRules.firstIndex(where: { $0.id == rule.id }) else { return }
        connectionRules[index] = rule
    }

    // MARK: - Automation

    /// Triggers automation when new external displays appear and match connection rules.
    private func handleDisplayChange(_ displays: [DisplayInfo]) {
        let current = Set(displays.map(\.stableIdentity))
        let added = current.subtracting(previousDisplayIDs)
        previousDisplayIDs = current

        guard automationEnabled, !added.isEmpty else { return }
        guard Date() >= automationSuppressedUntil else {
            DiagnosticsLogger.shared.log(
                "Skip automation during suppression added=\(added.count) until=\(automationSuppressedUntil.timeIntervalSinceNow)",
                category: "profile"
            )
            return
        }

        let addedExternalIDs = Set(displays.filter { added.contains($0.stableIdentity) && $0.isExternal }.map(\.stableIdentity))
        guard !addedExternalIDs.isEmpty else { return }

        let matching = connectionRules.filter { rule in
            guard rule.isEnabled, profiles.contains(where: { $0.id == rule.profileID }) else { return false }
            return rule.displayID.isEmpty || addedExternalIDs.contains(rule.displayID)
        }
        // Specific-display rules take priority over catch-all "any external" rules.
        let best = matching.first(where: { !$0.displayID.isEmpty }) ?? matching.first
        guard let rule = best, let profile = profiles.first(where: { $0.id == rule.profileID }) else { return }

        logger.notice("Automation triggered on display connect; applying profile \(profile.name, privacy: .public)")
        lastAppliedProfileName = profile.name
        apply(profile: profile)
    }

    /// Suppresses display-connect automation during wake/lock churn so reconnects do not clobber manual state.
    private func suppressAutomation(for duration: TimeInterval, reason: String) {
        let until = Date().addingTimeInterval(duration)
        if until > automationSuppressedUntil {
            automationSuppressedUntil = until
        }
        DiagnosticsLogger.shared.log(
            "Suppress automation reason=\(reason) duration=\(String(format: "%.1f", duration))s remaining=\(String(format: "%.1f", automationSuppressedUntil.timeIntervalSinceNow))s",
            category: "profile"
        )
    }

    /// Returns the current runtime power state from overlays/DDC without relying on persisted intent.
    private func currentRuntimePowerState(for display: DisplayInfo) -> PersistedMonitorPowerState {
        let id = display.stableIdentity
        if blackoutManager.activeDisplayIDs.contains(id) {
            return .blackout
        }
        if ddcManager.states[id]?.lastCommand == .standby {
            return .standby
        }
        if display.isBuiltin, let persisted = settingsStore.settings.monitorPowerStateByDisplayID[id], persisted != .visible {
            return persisted
        }
        return .visible
    }

    /// Returns the desired persisted power state used when saving/restoring profiles.
    private func currentDesiredPowerState(for display: DisplayInfo) -> PersistedMonitorPowerState {
        let id = display.stableIdentity
        if let persisted = settingsStore.settings.monitorPowerStateByDisplayID[id] {
            return persisted
        }
        if blackoutManager.activeDisplayIDs.contains(id) {
            return .blackout
        }
        if ddcManager.states[id]?.lastCommand == .standby {
            return .standby
        }
        return .visible
    }

    /// Applies a desired power state to a display via the engine.
    private func applyPowerState(_ state: PersistedMonitorPowerState, to display: DisplayInfo) {
        guard let engine else {
            logger.error("Cannot apply profile state; engine unavailable")
            return
        }
        engine.applyUserPowerState(state, to: display)
    }

    /// Captures snapshots for all currently known displays.
    private func captureCurrentDisplaySnapshots() -> [DisplaySnapshot] {
        displayManager.displays.map { display in
            let powerState = currentDesiredPowerState(for: display)
            return DisplaySnapshot(
                from: display,
                powerState: powerState == .visible ? .visible : .asleep,
                brightnessPercent: currentBrightness(for: display)
            )
        }
    }

    /// Resolves exact per-display power intent for profile apply, preferring captured monitor-state metadata.
    private func desiredPowerState(
        for snapshot: DisplaySnapshot,
        display: DisplayInfo,
        remappedMonitorState: ProfileMonitorState?
    ) -> PersistedMonitorPowerState {
        if let stored = remappedMonitorState?.monitorPowerStateByDisplayID[display.stableIdentity] {
            return stored
        }
        switch snapshot.powerState {
        case .visible:
            return .visible
        case .asleep:
            return inferredLegacyAsleepPowerState(for: display)
        }
    }

    /// Infers exact power intent for older profiles that only stored `visible` vs `asleep`.
    private func inferredLegacyAsleepPowerState(for display: DisplayInfo) -> PersistedMonitorPowerState {
        let id = display.stableIdentity
        if let persisted = settingsStore.settings.monitorPowerStateByDisplayID[id], persisted != .visible {
            return persisted
        }
        if display.isBuiltin {
            return .blackout
        }
        if settingsStore.settings.overlayOnlyDisplayIDs.contains(id) {
            return .blackout
        }
        if blackoutManager.activeDisplayIDs.contains(id) {
            return .blackout
        }
        if ddcManager.states[id]?.lastCommand == .standby {
            return .standby
        }
        if ddcManager.states[id]?.status == .supported {
            return .standby
        }
        return .blackout
    }

    /// Determines the current brightness for profile capture.
    private func currentBrightness(for display: DisplayInfo) -> Int? {
        if display.isBuiltin {
            if let liveBrightness = DisplayHardware.builtinDisplayBrightnessPercent(for: display.displayID) {
                return liveBrightness
            }
            return settingsStore.settings.monitorBrightnessByDisplayID[display.stableIdentity]
        }

        guard display.isExternal else { return nil }
        if let engine {
            return engine.brightnessPercent(for: display)
        }
        if let fallback = blackoutManager.fallbackBrightnessLevels[display.stableIdentity] {
            return fallback
        }
        if let ddc = ddcManager.brightnessLevels[display.stableIdentity] {
            return ddc
        }
        return 100
    }

    // MARK: - Persistence

    /// Returns the current profile state for backup export.
    func exportState() -> ProfileState {
        ProfileState(
            profiles: profiles,
            automationEnabled: automationEnabled,
            automationProfileID: automationProfileID,
            automationTriggerTarget: automationTriggerTarget,
            connectionRules: connectionRules
        )
    }

    /// Restores profile state from backup import.
    func importState(_ state: ProfileState) {
        profiles = state.profiles
        automationEnabled = state.automationEnabled
        automationProfileID = state.automationProfileID
        automationTriggerTarget = state.automationTriggerTarget
        connectionRules = state.connectionRules
        persist()
    }

    /// Persists profiles and automation settings to disk.
    private func persist() {
        store.save(exportState())
    }
}

/// Stores profile state in Application Support as JSON.
struct ProfileStore {
    private let filename = "profiles.json"

    /// Loads profiles from disk or returns an empty state.
    func load() -> ProfileState {
        let url = storageURL()
        guard let data = try? Data(contentsOf: url) else {
            return ProfileState(
                profiles: [],
                automationEnabled: false,
                automationProfileID: nil,
                automationTriggerTarget: .allExternalDisplays,
                connectionRules: []
            )
        }
        do {
            return try JSONDecoder().decode(ProfileState.self, from: data)
        } catch {
            return ProfileState(
                profiles: [],
                automationEnabled: false,
                automationProfileID: nil,
                automationTriggerTarget: .allExternalDisplays,
                connectionRules: []
            )
        }
    }

    /// Saves profile state to disk.
    func save(_ state: ProfileState) {
        let url = storageURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url)
        }
    }

    /// Resolves the Application Support URL for the profile file.
    private func storageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Dimly", isDirectory: true)
            .appendingPathComponent(filename, conformingTo: .json)
    }
}
