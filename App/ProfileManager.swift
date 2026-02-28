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
    case ocean
    case mint
    case violet
    case amber
    case rose
    case lime
    case slate
    case teal
    case indigo
    case coral
    case copper
    case emerald
    case sky
    case magenta
    case gold

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .sunset:
            return String(localized: "Sunset")
        case .ocean:
            return String(localized: "Ocean")
        case .mint:
            return String(localized: "Mint")
        case .violet:
            return String(localized: "Violet")
        case .amber:
            return String(localized: "Amber")
        case .rose:
            return String(localized: "Rose")
        case .lime:
            return String(localized: "Lime")
        case .slate:
            return String(localized: "Slate")
        case .teal:
            return String(localized: "Teal")
        case .indigo:
            return String(localized: "Indigo")
        case .coral:
            return String(localized: "Coral")
        case .copper:
            return String(localized: "Copper")
        case .emerald:
            return String(localized: "Emerald")
        case .sky:
            return String(localized: "Sky")
        case .magenta:
            return String(localized: "Magenta")
        case .gold:
            return String(localized: "Gold")
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

/// A named set of display snapshots captured at a point in time.
struct DisplayProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    var displays: [DisplaySnapshot]
    var monitorState: ProfileMonitorState?
    var showInSmartButtons: Bool = true
    var smartButtonColorPreset: SmartButtonColorPreset?

    init(
        id: UUID,
        name: String,
        createdAt: Date,
        displays: [DisplaySnapshot],
        monitorState: ProfileMonitorState?,
        showInSmartButtons: Bool = true,
        smartButtonColorPreset: SmartButtonColorPreset? = nil
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.displays = displays
        self.monitorState = monitorState
        self.showInSmartButtons = showInSmartButtons
        self.smartButtonColorPreset = smartButtonColorPreset
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case createdAt
        case displays
        case monitorState
        case showInSmartButtons
        case smartButtonColorPreset
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        displays = try container.decode([DisplaySnapshot].self, forKey: .displays)
        monitorState = try container.decodeIfPresent(ProfileMonitorState.self, forKey: .monitorState)
        showInSmartButtons = try container.decodeIfPresent(Bool.self, forKey: .showInSmartButtons) ?? true
        smartButtonColorPreset = try container.decodeIfPresent(SmartButtonColorPreset.self, forKey: .smartButtonColorPreset)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(displays, forKey: .displays)
        try container.encodeIfPresent(monitorState, forKey: .monitorState)
        try container.encode(showInSmartButtons, forKey: .showInSmartButtons)
        try container.encodeIfPresent(smartButtonColorPreset, forKey: .smartButtonColorPreset)
    }
}

/// Monitor-related UI + brightness state captured inside a profile.
struct ProfileMonitorState: Codable, Equatable {
    var menuBarExcludedDisplayIDs: [String]
    var menuBarIncludedInternalDisplayIDs: [String]
    var externalDisplayOrder: [String]
    var internalDisplayOrder: [String]
    var brightnessPanelExpandedDisplayIDs: [String]
    var monitorBrightnessByDisplayID: [String: Int]

    init(
        menuBarExcludedDisplayIDs: [String],
        menuBarIncludedInternalDisplayIDs: [String],
        externalDisplayOrder: [String],
        internalDisplayOrder: [String],
        brightnessPanelExpandedDisplayIDs: [String],
        monitorBrightnessByDisplayID: [String: Int]
    ) {
        self.menuBarExcludedDisplayIDs = menuBarExcludedDisplayIDs
        self.menuBarIncludedInternalDisplayIDs = menuBarIncludedInternalDisplayIDs
        self.externalDisplayOrder = externalDisplayOrder
        self.internalDisplayOrder = internalDisplayOrder
        self.brightnessPanelExpandedDisplayIDs = brightnessPanelExpandedDisplayIDs
        self.monitorBrightnessByDisplayID = monitorBrightnessByDisplayID
    }

    init(from settings: DimlySettings) {
        menuBarExcludedDisplayIDs = settings.menuBarExcludedDisplayIDs
        menuBarIncludedInternalDisplayIDs = settings.menuBarIncludedInternalDisplayIDs
        externalDisplayOrder = settings.externalDisplayOrder
        internalDisplayOrder = settings.internalDisplayOrder
        brightnessPanelExpandedDisplayIDs = settings.brightnessPanelExpandedDisplayIDs
        monitorBrightnessByDisplayID = settings.monitorBrightnessByDisplayID
    }

    func apply(to settings: inout DimlySettings) {
        settings.menuBarExcludedDisplayIDs = menuBarExcludedDisplayIDs
        settings.menuBarIncludedInternalDisplayIDs = menuBarIncludedInternalDisplayIDs
        settings.externalDisplayOrder = externalDisplayOrder
        settings.internalDisplayOrder = internalDisplayOrder
        settings.brightnessPanelExpandedDisplayIDs = brightnessPanelExpandedDisplayIDs
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
            monitorBrightnessByDisplayID: remap(monitorBrightnessByDisplayID, with: idMap)
        )
    }

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

    private func remap(_ values: [String: Int], with idMap: [String: String]) -> [String: Int] {
        var remapped: [String: Int] = [:]
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
}

/// Manages saving/applying display profiles and simple automation on external connect.
@MainActor
final class ProfileManager: ObservableObject {
    @Published private(set) var profiles: [DisplayProfile] = []
    @Published var automationEnabled: Bool = false {
        didSet { persist() }
    }
    @Published var automationProfileID: UUID? {
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

        previousDisplayIDs = Set(displayManager.displays.map(\.stableIdentity))

        displayManager.$displays
            .sink { [weak self] displays in
                self?.handleDisplayChange(displays)
            }
            .store(in: &cancellables)
    }

    // MARK: - Profile CRUD

    /// Captures the current display state into a new named profile.
    func saveCurrentProfile(named name: String) {
        let snapshots = displayManager.displays.map { display in
            DisplaySnapshot(
                from: display,
                powerState: currentPowerState(for: display),
                brightnessPercent: currentBrightness(for: display)
            )
        }
        let profile = DisplayProfile(
            id: UUID(),
            name: name.isEmpty
                ? String(format: String(localized: "ProfileDefaultNameFormat"), Int64(profiles.count + 1))
                : name,
            createdAt: Date(),
            displays: snapshots,
            monitorState: ProfileMonitorState(from: settingsStore.settings),
            showInSmartButtons: true
        )
        profiles.append(profile)
        persist()
    }

    /// Applies a profile to current displays, logging missing targets.
    func apply(profile: DisplayProfile) {
        let currentDisplays = displayManager.displays
        let matched = resolveSnapshotMappings(profile.displays, to: currentDisplays)
        let appliedSnapshotIDs = Set(matched.map(\.snapshot.id))
        let expectedIDs = Set(profile.displays.map(\.id))
        let missing = expectedIDs.subtracting(appliedSnapshotIDs)
        let idMap = Dictionary(uniqueKeysWithValues: matched.map { ($0.snapshot.id, $0.display.stableIdentity) })

        if let monitorState = profile.monitorState {
            let remappedState = monitorState.remapped(using: idMap)
            settingsStore.update { settings in
                remappedState.apply(to: &settings)
            }
        }

        let shouldAnimateBrightness = settingsStore.settings.fadeOutAnimationEnabled || settingsStore.settings.fadeInAnimationEnabled

        var appliedCount = 0
        var immediateBrightnessTargets: [(display: DisplayInfo, percent: Int)] = []
        var delayedBrightnessTargets: [(display: DisplayInfo, percent: Int)] = []
        var retryBrightnessTargets: [(display: DisplayInfo, percent: Int)] = []

        for (snapshot, display) in matched {
            let currentState = currentPowerState(for: display)
            if currentState != snapshot.powerState {
                applyPowerState(snapshot.powerState, to: display)
            }
            if snapshot.powerState == .visible, let brightness = snapshot.brightnessPercent {
                let clamped = max(0, min(100, brightness))
                let needsPostWakeStabilization = display.isExternal && (
                    currentState == .asleep ||
                    ddcManager.states[display.stableIdentity]?.status != .supported
                )
                if currentState == .asleep {
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
            engine.setBrightnessSynchronously(immediateBrightnessTargets, animated: shouldAnimateBrightness)
            if !delayedBrightnessTargets.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    delayedBrightnessTargets.forEach { target in
                        engine.setBrightness(target.percent, for: target.display, animated: false)
                    }
                }
            }
            if !retryBrightnessTargets.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
                    retryBrightnessTargets.forEach { target in
                        engine.setBrightness(target.percent, for: target.display, animated: false)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    retryBrightnessTargets.forEach { target in
                        engine.setBrightness(target.percent, for: target.display, animated: false)
                    }
                }
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

    // MARK: - Automation

    /// Triggers automation when new external displays appear.
    private func handleDisplayChange(_ displays: [DisplayInfo]) {
        let current = Set(displays.map(\.stableIdentity))
        let added = current.subtracting(previousDisplayIDs)
        previousDisplayIDs = current

        guard automationEnabled, !added.isEmpty, let profileID = automationProfileID,
              let profile = profiles.first(where: { $0.id == profileID }) else { return }

        let addedExternals = displays.filter { added.contains($0.stableIdentity) && $0.isExternal }
        guard addedExternals.isEmpty == false else { return }

        logger.notice("Automation triggered on display connect; applying profile \(profile.name, privacy: .public)")
        apply(profile: profile)
    }

    /// Determines current power state using blackout/standby signals.
    private func currentPowerState(for display: DisplayInfo) -> DisplayPowerState {
        if blackoutManager.activeDisplayIDs.contains(display.stableIdentity) {
            return .asleep
        }
        if ddcManager.states[display.stableIdentity]?.lastCommand == .standby {
            return .asleep
        }
        return .visible
    }

    /// Applies a desired power state to a display via the engine.
    private func applyPowerState(_ state: DisplayPowerState, to display: DisplayInfo) {
        guard let engine else {
            logger.error("Cannot apply profile state; engine unavailable")
            return
        }
        switch state {
        case .asleep:
            engine.standby(display: display)
        case .visible:
            engine.wake(display: display)
        }
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
            automationProfileID: automationProfileID
        )
    }

    /// Restores profile state from backup import.
    func importState(_ state: ProfileState) {
        profiles = state.profiles
        automationEnabled = state.automationEnabled
        automationProfileID = state.automationProfileID
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
            return ProfileState(profiles: [], automationEnabled: false, automationProfileID: nil)
        }
        do {
            return try JSONDecoder().decode(ProfileState.self, from: data)
        } catch {
            return ProfileState(profiles: [], automationEnabled: false, automationProfileID: nil)
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
