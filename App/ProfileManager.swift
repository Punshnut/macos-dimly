// MARK: - Profile Automation
// Captures display snapshots, stores named profiles, and re-applies them when hardware changes.
import Foundation
import Combine
import OSLog
import AppKit
import CoreGraphics

enum DisplayPowerState: String, Codable {
    case visible
    case asleep
}

struct DisplaySnapshot: Codable, Equatable, Identifiable {
    let id: String
    let name: String?
    let isPrimary: Bool
    let resolution: String
    let refreshRateHz: Double?
    let powerState: DisplayPowerState

    init(from info: DisplayInfo, powerState: DisplayPowerState) {
        id = info.stableIdentity
        name = info.name
        isPrimary = info.displayID == CGMainDisplayID()
        resolution = info.resolution
        refreshRateHz = info.refreshRateHz
        self.powerState = powerState
    }

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case isPrimary
        case resolution
        case refreshRateHz
        case powerState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        isPrimary = try container.decode(Bool.self, forKey: .isPrimary)
        resolution = try container.decode(String.self, forKey: .resolution)
        refreshRateHz = try container.decodeIfPresent(Double.self, forKey: .refreshRateHz)
        powerState = try container.decodeIfPresent(DisplayPowerState.self, forKey: .powerState) ?? .visible
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(name, forKey: .name)
        try container.encode(isPrimary, forKey: .isPrimary)
        try container.encode(resolution, forKey: .resolution)
        try container.encodeIfPresent(refreshRateHz, forKey: .refreshRateHz)
        try container.encode(powerState, forKey: .powerState)
    }
}

struct DisplayProfile: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let createdAt: Date
    var displays: [DisplaySnapshot]
}

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
    weak var engine: DimlyEngine?
    private let store: ProfileStore
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "Profiles")
    private var cancellables: Set<AnyCancellable> = []
    private var previousDisplayIDs: Set<String> = []

    init(
        displayManager: DisplayManager,
        blackoutManager: BlackoutManager,
        ddcManager: DDCManager,
        store: ProfileStore = ProfileStore()
    ) {
        self.displayManager = displayManager
        self.blackoutManager = blackoutManager
        self.ddcManager = ddcManager
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

    func saveCurrentProfile(named name: String) {
        let snapshots = displayManager.displays.map { display in
            DisplaySnapshot(from: display, powerState: currentPowerState(for: display))
        }
        let profile = DisplayProfile(
            id: UUID(),
            name: name.isEmpty
                ? String(format: String(localized: "ProfileDefaultNameFormat"), Int64(profiles.count + 1))
                : name,
            createdAt: Date(),
            displays: snapshots
        )
        profiles.append(profile)
        persist()
    }

    func apply(profile: DisplayProfile) {
        let currentDisplays = displayManager.displays
        let expectedIDs = Set(profile.displays.map(\.id))
        let currentIDs = Set(currentDisplays.map(\.stableIdentity))
        let missing = expectedIDs.subtracting(currentIDs)

        var appliedCount = 0
        for display in currentDisplays {
            guard let snapshot = profile.displays.first(where: { $0.id == display.stableIdentity }) else { continue }
            let currentState = currentPowerState(for: display)
            if currentState != snapshot.powerState {
                applyPowerState(snapshot.powerState, to: display)
            }
            appliedCount += 1
        }

        if missing.isEmpty {
            logger.notice("Applied profile \(profile.name, privacy: .public) to \(appliedCount, privacy: .public) displays")
        } else {
            let missingList = missing.joined(separator: ", ")
            logger.info("Applied profile \(profile.name, privacy: .public) partially to \(appliedCount, privacy: .public) displays; missing: \(missingList, privacy: .public)")
        }
        lastAppliedProfileName = profile.name
    }

    func rename(profile: DisplayProfile, to newName: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].name = newName
        persist()
    }

    func delete(profile: DisplayProfile) {
        profiles.removeAll { $0.id == profile.id }
        if automationProfileID == profile.id {
            automationProfileID = nil
        }
        persist()
    }

    // MARK: - Automation

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

    private func currentPowerState(for display: DisplayInfo) -> DisplayPowerState {
        if blackoutManager.activeDisplayIDs.contains(display.stableIdentity) {
            return .asleep
        }
        if ddcManager.states[display.stableIdentity]?.lastCommand == .standby {
            return .asleep
        }
        return .visible
    }

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

    // MARK: - Persistence

    private func persist() {
        let state = ProfileState(
            profiles: profiles,
            automationEnabled: automationEnabled,
            automationProfileID: automationProfileID
        )
        store.save(state)
    }
}

/// Stores profile state in Application Support as JSON.
struct ProfileStore {
    private let filename = "profiles.json"

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

    func save(_ state: ProfileState) {
        let url = storageURL()
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(state) {
            try? data.write(to: url)
        }
    }

    private func storageURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Dimly", isDirectory: true)
            .appendingPathComponent(filename, conformingTo: .json)
    }
}
