// MARK: - Color Profile Manager
// ICC color profile listing and switching via ColorSync (public) + one private CGDisplay symbol.
import Foundation
import CoreGraphics
import Darwin
import OSLog

/// Logical grouping of a color profile — used to render sections in the picker.
enum ColorProfileGroup: String {
    case standard       // curated macOS system profiles (sRGB, P3, Adobe RGB…)
    case modern         // named CGColorSpace profiles (Extended P3, HDR…)
    case creative       // /Library effect profiles (Black & White, Sepia…)
    case calibration    // /Library/Displays hardware calibration profiles
    case user           // ~/Library user-installed profiles
}

/// An installed ICC color profile available for a display.
struct ColorProfile: Identifiable, Equatable {
    /// Sentinel ID for the "System Default" entry — passes nil to CGDisplaySetColorProfile.
    static let systemDefaultID = "__dimly_system_default__"

    let id: String              // file path for file-backed profiles; unique id for virtual ones
    let name: String
    let url: URL?               // nil for system default and named-space profiles
    let embeddedICCData: Data?  // ICC bytes for named CGColorSpace profiles (no file)
    let group: ColorProfileGroup

    /// Designated init.
    init(id: String, name: String, url: URL?,
         embeddedICCData: Data? = nil,
         group: ColorProfileGroup = .user) {
        self.id = id
        self.name = name
        self.url = url
        self.embeddedICCData = embeddedICCData
        self.group = group
    }

    static func == (lhs: ColorProfile, rhs: ColorProfile) -> Bool { lhs.id == rhs.id }

    /// Sentinel representing the macOS system-assigned color profile.
    static let systemDefault = ColorProfile(
        id: systemDefaultID,
        name: String(localized: "ColorProfileSystemDefaultLabel"),
        url: nil,
        group: .standard
    )

    var isSystemDefault: Bool { id == Self.systemDefaultID }

    /// Returns the ICC data to pass to CGDisplaySetColorProfile, or nil to reset.
    func iccData() -> CFData? {
        if isSystemDefault { return nil }
        if let embedded = embeddedICCData { return embedded as CFData }
        guard let url else { return nil }
        return (try? Data(contentsOf: url)) as CFData?
    }
}

// MARK: -

/// Lists installed ICC profiles and switches the active profile per display.
@MainActor
final class ColorProfileManager: ObservableObject {
    @Published private(set) var availableProfiles: [String: [ColorProfile]] = [:]
    @Published private(set) var currentProfile: [String: ColorProfile] = [:]

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "ColorProfile")

    // CGDisplaySetColorProfile is private; dlsym it from CoreGraphics.
    private typealias CGDisplaySetColorProfileFn = @convention(c) (CGDirectDisplayID, CFData?) -> CGError
    private static let cgSetColorProfile: CGDisplaySetColorProfileFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
              let sym = dlsym(handle, "CGDisplaySetColorProfile") else { return nil }
        return unsafeBitCast(sym, to: CGDisplaySetColorProfileFn.self)
    }()

    // MARK: - Profile Loading

    /// Loads the curated profile list for a display and detects the currently active profile.
    func loadProfiles(for display: DisplayInfo) {
        let displayID = display.displayID
        let stableID = display.stableIdentity
        Task.detached(priority: .utility) {
            let system = Self.enumerateSystemProfiles()
            let modern = Self.enumerateModernNamedProfiles()
            let library = Self.enumerateLibraryCreativeProfiles()
            let displaySpecific = Self.enumerateDisplayCalibrationProfiles()
            let user = Self.enumerateUserProfiles()

            // Detect which profile is currently active by comparing ICC data bytes.
            let currentData = Self.currentColorSpaceICCData(for: displayID)
            let allReal = system + modern + library + displaySpecific + user

            await MainActor.run { [weak self] in
                let all: [ColorProfile] = [.systemDefault] + allReal
                self?.availableProfiles[stableID] = all

                if let currentData {
                    // Definitive match: compare raw ICC bytes.
                    let match = allReal.first { profile in
                        if let embedded = profile.embeddedICCData {
                            return embedded == currentData
                        }
                        guard let url = profile.url,
                              let fileData = try? Data(contentsOf: url) else { return false }
                        return fileData == currentData
                    }
                    self?.currentProfile[stableID] = match ?? .systemDefault
                } else {
                    self?.currentProfile[stableID] = .systemDefault
                }
            }
        }
    }

    // MARK: - Profile Application

    /// Applies a color profile to the display. Returns true on success.
    @discardableResult
    func setProfile(_ profile: ColorProfile, for display: DisplayInfo) -> Bool {
        guard let setFn = Self.cgSetColorProfile else {
            logger.error("CGDisplaySetColorProfile symbol unavailable")
            return false
        }
        let iccData = profile.iccData()   // nil = reset to system default
        let result = setFn(display.displayID, iccData)
        if result == .success {
            currentProfile[display.stableIdentity] = profile
            let label = profile.isSystemDefault ? "system default" : profile.name
            logger.notice("Color profile → \(label, privacy: .public) for \(display.stableIdentity, privacy: .public)")
            return true
        }
        logger.error("Color profile switch failed: \(result.rawValue, privacy: .public) (\(profile.name, privacy: .public))")
        return false
    }

    /// Resets a display to its system-assigned color profile.
    @discardableResult
    func resetToSystemDefault(for display: DisplayInfo) -> Bool {
        setProfile(.systemDefault, for: display)
    }

    // MARK: - Curated System Profiles
    // Ordered by prevalence: everyday use → professional/video → scientific.

    private nonisolated static let curatedSystemProfiles: [(filename: String, friendlyName: String)] = [
        ("sRGB Profile.icc",           "sRGB (Standard)"),
        ("Display P3.icc",             "Display P3 (Wide Gamut)"),
        ("DCI(P3) RGB.icc",            "DCI-P3 (Cinema)"),
        ("AdobeRGB1998.icc",           "Adobe RGB (1998)"),
        ("ITU-709.icc",                "ITU-R BT.709 (HD Video)"),
        ("ITU-2020.icc",               "ITU-R BT.2020 (UHD Video)"),
        ("ROMM RGB.icc",               "ProPhoto RGB (ROMM)"),
        ("ACESCG Linear.icc",          "ACES CG Linear (VFX)"),
        ("Generic RGB Profile.icc",    "Generic RGB"),
    ]

    // Modern named color spaces — backed by CGColorSpace constants, no standalone ICC file.
    // The `cgName` strings match the CGColorSpace constant values (e.g. "kCGColorSpaceExtendedDisplayP3").
    private nonisolated static let modernNamedSpaces: [(id: String, name: String, cgName: String)] = [
        ("__extendedDisplayP3__",  "Extended Display P3",    "kCGColorSpaceExtendedDisplayP3"),
        ("__extendedSRGB__",       "Extended sRGB",           "kCGColorSpaceExtendedSRGB"),
        ("__linearSRGB__",         "sRGB Linear",             "kCGColorSpaceLinearSRGB"),
        ("__itur_2100_PQ__",       "BT.2100 PQ (HDR)",        "kCGColorSpaceITUR_2100_PQ"),
        ("__itur_2100_HLG__",      "BT.2100 HLG (HDR)",       "kCGColorSpaceITUR_2100_HLG"),
    ]

    // Creative effect profiles installed by macOS in /Library (present on every Mac).
    // WebSafeColors is excluded — not appropriate for modern display control.
    private nonisolated static let libraryProfileFilenames: Set<String> = [
        "Black & White.icc",
        "Blue Tone.icc",
        "Gray Tone.icc",
        "Lightness Decrease.icc",
        "Lightness Increase.icc",
        "Sepia Tone.icc",
    ]

    // Path constants — nonisolated so background tasks can reference them.
    private nonisolated static let systemProfilesDir =
        URL(fileURLWithPath: "/System/Library/ColorSync/Profiles")
    private nonisolated static let libraryProfilesDir =
        URL(fileURLWithPath: "/Library/ColorSync/Profiles")
    private nonisolated static let libraryDisplaysDir =
        URL(fileURLWithPath: "/Library/ColorSync/Profiles/Displays")
    private nonisolated static let userProfilesDir =
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/ColorSync/Profiles")

    // MARK: - Enumeration (nonisolated — called from Task.detached)

    private nonisolated static func enumerateSystemProfiles() -> [ColorProfile] {
        curatedSystemProfiles.compactMap { entry in
            let url = systemProfilesDir.appendingPathComponent(entry.filename)
            guard FileManager.default.fileExists(atPath: url.path) else { return nil }
            return ColorProfile(id: url.path, name: entry.friendlyName, url: url, group: .standard)
        }
    }

    /// Named CGColorSpace profiles — get ICC data from the live color space object.
    private nonisolated static func enumerateModernNamedProfiles() -> [ColorProfile] {
        modernNamedSpaces.compactMap { entry in
            guard let cs = CGColorSpace(name: entry.cgName as CFString),
                  let iccData = cs.copyICCData() as Data? else { return nil }
            return ColorProfile(id: entry.id, name: entry.name, url: nil,
                                embeddedICCData: iccData, group: .modern)
        }
    }

    /// Creative effect profiles from /Library (Black & White, Sepia, etc.).
    private nonisolated static func enumerateLibraryCreativeProfiles() -> [ColorProfile] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: libraryProfilesDir, includingPropertiesForKeys: nil
        ) else { return [] }
        return items
            .filter { libraryProfileFilenames.contains($0.lastPathComponent) }
            .compactMap { url -> ColorProfile? in
                let name = iccProfileName(at: url) ?? url.deletingPathExtension().lastPathComponent
                return ColorProfile(id: url.path, name: name, url: url, group: .creative)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Monitor-specific calibration profiles stored by ColorSync, DisplayCAL, i1Profiler, etc.
    private nonisolated static func enumerateDisplayCalibrationProfiles() -> [ColorProfile] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: libraryDisplaysDir, includingPropertiesForKeys: nil
        ) else { return [] }
        return items
            .filter { $0.pathExtension.lowercased() == "icc" || $0.pathExtension.lowercased() == "icm" }
            .compactMap { url -> ColorProfile? in
                let name = iccProfileName(at: url) ?? url.deletingPathExtension().lastPathComponent
                return ColorProfile(id: url.path, name: name, url: url, group: .calibration)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Profiles installed by the user into ~/Library/ColorSync/Profiles.
    private nonisolated static func enumerateUserProfiles() -> [ColorProfile] {
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: userProfilesDir, includingPropertiesForKeys: nil
        ) else { return [] }
        return items
            .filter { $0.pathExtension.lowercased() == "icc" || $0.pathExtension.lowercased() == "icm" }
            .compactMap { url -> ColorProfile? in
                let name = iccProfileName(at: url) ?? url.deletingPathExtension().lastPathComponent
                return ColorProfile(id: url.path, name: name, url: url, group: .user)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Helpers

    private nonisolated static func iccProfileName(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) as CFData,
              let cs = CGColorSpace(iccData: data) else { return nil }
        return cs.name as String?
    }

    /// Returns the raw ICC bytes of the display's current color space for fingerprint matching.
    private nonisolated static func currentColorSpaceICCData(for displayID: CGDirectDisplayID) -> Data? {
        CGDisplayCopyColorSpace(displayID).copyICCData() as Data?
    }
}
