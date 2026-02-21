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

/// Snapshot of a single display used inside profiles.
struct DisplaySnapshot: Codable, Equatable, Identifiable {
    let id: String
    let name: String?
    let isPrimary: Bool
    let resolution: String
    let refreshRateHz: Double?
    let powerState: DisplayPowerState
    let brightnessPercent: Int?

    /// Builds a snapshot from live display info.
    init(from info: DisplayInfo, powerState: DisplayPowerState, brightnessPercent: Int?) {
        id = info.stableIdentity
        name = info.name
        isPrimary = info.displayID == CGMainDisplayID()
        resolution = info.resolution
        refreshRateHz = info.refreshRateHz
        self.powerState = powerState
        self.brightnessPercent = brightnessPercent.map { max(0, min(100, $0)) }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isPrimary
        case resolution
        case refreshRateHz
        case powerState
        case brightnessPercent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isPrimary = try container.decode(Bool.self, forKey: .isPrimary)
        resolution = try container.decode(String.self, forKey: .resolution)
        refreshRateHz = try container.decodeIfPresent(Double.self, forKey: .refreshRateHz)
        powerState = try container.decodeIfPresent(DisplayPowerState.self, forKey: .powerState) ?? .visible
        brightnessPercent = try container.decodeIfPresent(Int.self, forKey: .brightnessPercent)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
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
}

/// Monitor-related UI + brightness state captured inside a profile.
struct ProfileMonitorState: Codable, Equatable {
    var menuBarExcludedDisplayIDs: [String]
    var menuBarIncludedInternalDisplayIDs: [String]
    var externalDisplayOrder: [String]
    var internalDisplayOrder: [String]
    var brightnessPanelExpandedDisplayIDs: [String]
    var monitorBrightnessByDisplayID: [String: Int]

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
            monitorState: ProfileMonitorState(from: settingsStore.settings)
        )
        profiles.append(profile)
        persist()
    }

    /// Applies a profile to current displays, logging missing targets.
    func apply(profile: DisplayProfile) {
        if let monitorState = profile.monitorState {
            settingsStore.update { settings in
                monitorState.apply(to: &settings)
            }
        }

        let currentDisplays = displayManager.displays
        let expectedIDs = Set(profile.displays.map(\.id))
        let currentIDs = Set(currentDisplays.map(\.stableIdentity))
        let missing = expectedIDs.subtracting(currentIDs)
        let shouldAnimateBrightness = settingsStore.settings.fadeOutAnimationEnabled || settingsStore.settings.fadeInAnimationEnabled

        var appliedCount = 0
        var immediateBrightnessTargets: [(display: DisplayInfo, percent: Int)] = []
        var delayedBrightnessTargets: [(display: DisplayInfo, percent: Int)] = []
        for display in currentDisplays {
            guard let snapshot = profile.displays.first(where: { $0.id == display.stableIdentity }) else { continue }
            let currentState = currentPowerState(for: display)
            if currentState != snapshot.powerState {
                applyPowerState(snapshot.powerState, to: display)
            }
            if snapshot.powerState == .visible, let brightness = snapshot.brightnessPercent {
                let clamped = max(0, min(100, brightness))
                if currentState == .asleep {
                    delayedBrightnessTargets.append((display: display, percent: clamped))
                } else {
                    immediateBrightnessTargets.append((display: display, percent: clamped))
                }
            }
            appliedCount += 1
        }
        if let engine {
            engine.setBrightnessSynchronously(immediateBrightnessTargets, animated: shouldAnimateBrightness)
            if !delayedBrightnessTargets.isEmpty {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
                    engine.setBrightnessSynchronously(delayedBrightnessTargets, animated: shouldAnimateBrightness)
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
