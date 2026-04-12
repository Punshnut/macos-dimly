// MARK: - Schedule Manager
// Manages time-based and solar-triggered profile scheduling.
import Foundation
import AppKit
import CoreLocation
import OSLog

// MARK: - Data Models

/// Persisted latitude/longitude from a one-shot CoreLocation lookup.
struct SavedCoordinate: Codable, Equatable {
    let latitude: Double
    let longitude: Double
    let updatedAt: Date
}

/// Specifies when a schedule entry should fire.
enum ScheduleTrigger: Equatable {
    case clockTime(hour: Int, minute: Int)
    case sunrise(offsetMinutes: Int)
    case sunset(offsetMinutes: Int)
}

extension ScheduleTrigger: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case hour
        case minute
        case offsetMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let type = try c.decode(String.self, forKey: .type)
        switch type {
        case "clockTime":
            let h = try c.decodeIfPresent(Int.self, forKey: .hour) ?? 8
            let m = try c.decodeIfPresent(Int.self, forKey: .minute) ?? 0
            self = .clockTime(hour: h, minute: m)
        case "sunrise":
            let offset = try c.decodeIfPresent(Int.self, forKey: .offsetMinutes) ?? 0
            self = .sunrise(offsetMinutes: offset)
        case "sunset":
            let offset = try c.decodeIfPresent(Int.self, forKey: .offsetMinutes) ?? 0
            self = .sunset(offsetMinutes: offset)
        default:
            self = .clockTime(hour: 8, minute: 0)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .clockTime(let h, let m):
            try c.encode("clockTime", forKey: .type)
            try c.encode(h, forKey: .hour)
            try c.encode(m, forKey: .minute)
        case .sunrise(let offset):
            try c.encode("sunrise", forKey: .type)
            try c.encode(offset, forKey: .offsetMinutes)
        case .sunset(let offset):
            try c.encode("sunset", forKey: .type)
            try c.encode(offset, forKey: .offsetMinutes)
        }
    }
}

/// A single scheduled profile-apply rule.
struct ScheduleEntry: Codable, Identifiable, Equatable {
    var id: UUID
    var isEnabled: Bool
    var profileID: UUID
    var trigger: ScheduleTrigger
    /// Calendar weekday integers (1 = Sunday … 7 = Saturday). Empty means every day.
    var daysOfWeek: [Int]

    private enum CodingKeys: String, CodingKey {
        case id, isEnabled, profileID, trigger, daysOfWeek
    }

    init(id: UUID, isEnabled: Bool, profileID: UUID, trigger: ScheduleTrigger, daysOfWeek: [Int]) {
        self.id = id
        self.isEnabled = isEnabled
        self.profileID = profileID
        self.trigger = trigger
        self.daysOfWeek = daysOfWeek
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        profileID = try c.decode(UUID.self, forKey: .profileID)
        trigger = try c.decode(ScheduleTrigger.self, forKey: .trigger)
        daysOfWeek = try c.decodeIfPresent([Int].self, forKey: .daysOfWeek) ?? []
    }
}

/// Full persisted schedule state.
struct ScheduleState: Codable {
    var entries: [ScheduleEntry]
    var schedulingEnabled: Bool
    var savedCoordinate: SavedCoordinate?

    private enum CodingKeys: String, CodingKey {
        case entries, schedulingEnabled, savedCoordinate
    }

    init(entries: [ScheduleEntry] = [], schedulingEnabled: Bool = false, savedCoordinate: SavedCoordinate? = nil) {
        self.entries = entries
        self.schedulingEnabled = schedulingEnabled
        self.savedCoordinate = savedCoordinate
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entries = try c.decodeIfPresent([ScheduleEntry].self, forKey: .entries) ?? []
        schedulingEnabled = try c.decodeIfPresent(Bool.self, forKey: .schedulingEnabled) ?? false
        savedCoordinate = try c.decodeIfPresent(SavedCoordinate.self, forKey: .savedCoordinate)
    }
}

/// `UserDefaults`-backed persistence for schedule state.
enum ScheduleStore {
    static let key = "DimlySchedules.v1"

    static func load() -> ScheduleState {
        guard let data = UserDefaults.standard.data(forKey: key) else { return ScheduleState() }
        do {
            return try JSONDecoder().decode(ScheduleState.self, from: data)
        } catch {
            return ScheduleState()
        }
    }

    static func save(_ state: ScheduleState) {
        do {
            let data = try JSONEncoder().encode(state)
            UserDefaults.standard.set(data, forKey: key)
        } catch {}
    }
}

// MARK: - ScheduleManager

/// Manages time-triggered and solar-triggered profile applications.
@MainActor
final class ScheduleManager: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: Published State

    @Published var entries: [ScheduleEntry] {
        didSet { persist(); refreshTimers() }
    }
    @Published var schedulingEnabled: Bool {
        didSet { persist(); refreshTimers() }
    }
    @Published var savedCoordinate: SavedCoordinate? {
        didSet { persist(); refreshTimers() }
    }
    @Published private(set) var locationAuthStatus: CLAuthorizationStatus = .notDetermined
    @Published private(set) var isRequestingLocation: Bool = false

    // MARK: Dependencies

    weak var profileManager: ProfileManager?

    // MARK: Private

    private var timers: [UUID: Timer] = [:]
    private var locationManager: CLLocationManager?
    private var wakeToken: NSObjectProtocol?
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "Schedule")

    /// Schedules that missed their fire time by less than this window are applied on wake.
    /// Schedules missed by more are skipped to avoid applying a stale "night mode" in the morning.
    private let catchUpWindow: TimeInterval = 5 * 60  // 5 minutes

    // MARK: Init

    override init() {
        let state = ScheduleStore.load()
        entries = state.entries
        schedulingEnabled = state.schedulingEnabled
        savedCoordinate = state.savedCoordinate
        super.init()
        observeWake()
    }

    // MARK: - Wake Observation

    private func observeWake() {
        wakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleWake()
            }
        }
    }

    /// Called after system wake. Cancels stale timers, applies any schedule that was missed within
    /// the catch-up window, then reschedules all future fires from the current time.
    private func handleWake() {
        guard schedulingEnabled else { return }
        let now = Date()

        // Cancel all pending timers — they may have stale fire dates from before sleep.
        for timer in timers.values { timer.invalidate() }
        timers.removeAll()

        for entry in entries where entry.isEnabled {
            guard profileManager?.profiles.contains(where: { $0.id == entry.profileID }) == true else { continue }

            // Check if this entry's trigger fired while the Mac was asleep (within catch-up window).
            let catchUpStart = now.addingTimeInterval(-catchUpWindow)
            if let missedDate = nextFireDate(for: entry, after: catchUpStart),
               missedDate <= now {
                logger.info("Wake catch-up: firing missed schedule \(entry.id) (was due \(missedDate))")
                fire(entryID: entry.id)
                continue
            }

            // Otherwise schedule normally from now.
            if let nextDate = nextFireDate(for: entry, after: now) {
                scheduleTimer(for: entry.id, at: nextDate)
            }
        }
    }

    // MARK: - CRUD

    func addEntry(_ entry: ScheduleEntry) {
        entries.append(entry)
    }

    func remove(id: UUID) {
        timers[id]?.invalidate()
        timers.removeValue(forKey: id)
        entries.removeAll { $0.id == id }
    }

    func update(entry: ScheduleEntry) {
        guard let idx = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[idx] = entry
    }

    // MARK: - Persistence

    private func persist() {
        ScheduleStore.save(ScheduleState(entries: entries, schedulingEnabled: schedulingEnabled, savedCoordinate: savedCoordinate))
    }

    // MARK: - Timer Scheduling

    /// Cancels all existing timers and reschedules enabled entries.
    func refreshTimers() {
        for timer in timers.values { timer.invalidate() }
        timers.removeAll()

        guard schedulingEnabled else { return }

        let now = Date()
        for entry in entries where entry.isEnabled {
            guard profileManager?.profiles.contains(where: { $0.id == entry.profileID }) == true else { continue }
            guard let fireDate = nextFireDate(for: entry, after: now) else { continue }
            scheduleTimer(for: entry.id, at: fireDate)
        }
    }

    private func scheduleTimer(for id: UUID, at date: Date) {
        let timer = Timer(fire: date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.fire(entryID: id)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        timers[id] = timer
        logger.info("Scheduled entry \(id) for \(date)")
    }

    private func fire(entryID: UUID) {
        guard let entry = entries.first(where: { $0.id == entryID }) else { return }
        guard let profile = profileManager?.profiles.first(where: { $0.id == entry.profileID }) else { return }

        logger.info("Firing schedule entry \(entryID) → profile '\(profile.name)'")
        profileManager?.apply(profile: profile)

        // Remove spent timer and reschedule for the next occurrence
        timers.removeValue(forKey: entryID)
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        if let nextDate = nextFireDate(for: entry, after: tomorrow) {
            scheduleTimer(for: entryID, at: nextDate)
        }
    }

    // MARK: - Next Fire Date

    /// Computes the next fire date for an entry, starting after `now`.
    /// Searches up to 8 days to find a matching weekday.
    func nextFireDate(for entry: ScheduleEntry, after now: Date) -> Date? {
        let cal = Calendar.current
        for dayOffset in 0...7 {
            guard let candidate = cal.date(byAdding: .day, value: dayOffset, to: now) else { continue }
            guard let fireTime = triggerTime(for: entry.trigger, on: candidate) else { continue }
            guard fireTime > now else { continue }
            if !entry.daysOfWeek.isEmpty {
                let weekday = cal.component(.weekday, from: candidate) // 1=Sun…7=Sat
                guard entry.daysOfWeek.contains(weekday) else { continue }
            }
            return fireTime
        }
        return nil
    }

    private func triggerTime(for trigger: ScheduleTrigger, on day: Date) -> Date? {
        let cal = Calendar.current
        switch trigger {
        case .clockTime(let h, let m):
            return cal.date(bySettingHour: h, minute: m, second: 0, of: day)
        case .sunrise(let offsetMinutes):
            guard let coord = savedCoordinate else { return nil }
            guard let base = SunCalculator.sunriseTime(on: day, latitude: coord.latitude, longitude: coord.longitude) else { return nil }
            return base.addingTimeInterval(TimeInterval(offsetMinutes * 60))
        case .sunset(let offsetMinutes):
            guard let coord = savedCoordinate else { return nil }
            guard let base = SunCalculator.sunsetTime(on: day, latitude: coord.latitude, longitude: coord.longitude) else { return nil }
            return base.addingTimeInterval(TimeInterval(offsetMinutes * 60))
        }
    }

    // MARK: - Location

    /// Requests a one-shot location update to store lat/lng for solar calculations.
    func requestLocation() {
        guard !isRequestingLocation else { return }
        isRequestingLocation = true
        let manager = CLLocationManager()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        locationManager = manager

        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if status == .authorizedAlways || status == .authorized {
            manager.requestLocation()
        } else {
            // Permission denied — signal UI
            isRequestingLocation = false
            locationManager = nil
        }
    }

    // MARK: CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor [weak self] in
            self?.locationAuthStatus = status
            if status == .authorizedAlways || status == .authorized {
                self?.locationManager?.requestLocation()
            } else if status == .denied || status == .restricted {
                self?.isRequestingLocation = false
                self?.locationManager = nil
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor [weak self] in
            guard let location = locations.first else { return }
            self?.savedCoordinate = SavedCoordinate(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                updatedAt: Date()
            )
            self?.isRequestingLocation = false
            self?.locationManager = nil
            self?.logger.info("Location updated: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.logger.error("Location request failed: \(error.localizedDescription)")
            self?.isRequestingLocation = false
            self?.locationManager = nil
        }
    }
}

// MARK: - ScheduleTrigger Helpers

extension ScheduleTrigger {
    /// The display type used in the UI picker.
    var triggerType: ScheduleTriggerType {
        switch self {
        case .clockTime: return .clockTime
        case .sunrise: return .sunrise
        case .sunset: return .sunset
        }
    }
}

/// Flat enum for UI picker binding (no associated values).
enum ScheduleTriggerType: String, CaseIterable, Identifiable {
    case clockTime
    case sunrise
    case sunset

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .clockTime: return String(localized: "Clock")
        case .sunrise: return String(localized: "Sunrise")
        case .sunset: return String(localized: "Sunset")
        }
    }
}
