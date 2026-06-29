// MARK: - Display Mode Manager
// Resolution and refresh rate switching via public CoreGraphics APIs.
import Foundation
import CoreGraphics
import Combine
import OSLog

/// A single available display mode (resolution + refresh rate).
struct DisplayMode: Identifiable, Equatable, Hashable {
    let id: Int
    let width: Int
    let height: Int
    let refreshRate: Double
    let isHiDPI: Bool

    var resolutionLabel: String { "\(width)×\(height)" }

    var fullLabel: String {
        var parts = [resolutionLabel]
        if isHiDPI { parts.append(String(localized: "ResolutionHiDPIBadge")) }
        if refreshRate > 1 { parts.append(String(format: "%.0fHz", refreshRate)) }
        return parts.joined(separator: " ")
    }
}

/// Manages available display modes and switches resolutions/refresh rates.
@MainActor
final class DisplayModeManager: ObservableObject {
    @Published private(set) var availableModes: [String: [DisplayMode]] = [:]
    @Published private(set) var currentMode: [String: DisplayMode] = [:]

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "DisplayMode")

    /// Loads all available modes for a display and records the current mode.
    func loadModes(for display: DisplayInfo) {
        let displayID = display.displayID
        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let rawModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] else { return }

        let modes: [DisplayMode] = rawModes.compactMap { mode in
            let width  = mode.width
            let height = mode.height
            let hz     = mode.refreshRate
            guard width > 0, height > 0 else { return nil }
            let hiDPI  = mode.pixelWidth > mode.width
            let modeID = mode.ioDisplayModeID
            return DisplayMode(id: Int(modeID), width: width, height: height, refreshRate: hz, isHiDPI: hiDPI)
        }

        let deduped = Array(
            Dictionary(grouping: modes, by: { DisplayMode(id: $0.id, width: $0.width, height: $0.height, refreshRate: $0.refreshRate, isHiDPI: $0.isHiDPI) })
                .keys
        )
        .sorted { lhs, rhs in
            if lhs.width != rhs.width { return lhs.width > rhs.width }
            if lhs.height != rhs.height { return lhs.height > rhs.height }
            if lhs.isHiDPI != rhs.isHiDPI { return lhs.isHiDPI }
            return lhs.refreshRate > rhs.refreshRate
        }
        availableModes[display.stableIdentity] = deduped

        if let current = CGDisplayCopyDisplayMode(displayID) {
            let hz     = current.refreshRate
            let hiDPI  = current.pixelWidth > current.width
            let cur = DisplayMode(
                id: Int(current.ioDisplayModeID),
                width: current.width,
                height: current.height,
                refreshRate: hz,
                isHiDPI: hiDPI
            )
            currentMode[display.stableIdentity] = cur
        }
    }

    /// Returns modes grouped by logical resolution label, sorted by descending resolution.
    func groupedModes(for display: DisplayInfo) -> [(resolution: String, modes: [DisplayMode])] {
        guard let modes = availableModes[display.stableIdentity] else { return [] }
        var groups: [(String, [DisplayMode])] = []
        var seen: [String: Int] = [:]
        for mode in modes {
            let key = mode.resolutionLabel + (mode.isHiDPI ? " HiDPI" : "")
            if let idx = seen[key] {
                groups[idx].1.append(mode)
            } else {
                seen[key] = groups.count
                groups.append((key, [mode]))
            }
        }
        return groups
    }

    /// Switches the display to the given mode permanently. Returns true on success.
    @discardableResult
    func setMode(_ mode: DisplayMode, for display: DisplayInfo) -> Bool {
        let displayID = display.displayID
        let options: CFDictionary = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        guard let rawModes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode],
              let target = rawModes.first(where: { $0.ioDisplayModeID == UInt32(mode.id) }) else {
            logger.error("Mode \(mode.id, privacy: .public) not found for \(display.stableIdentity, privacy: .public)")
            return false
        }
        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success else { return false }
        CGConfigureDisplayWithDisplayMode(config, displayID, target, nil)
        let result = CGCompleteDisplayConfiguration(config, .permanently)
        if result == .success {
            currentMode[display.stableIdentity] = mode
            logger.notice("Mode set to \(mode.fullLabel, privacy: .public) for \(display.stableIdentity, privacy: .public)")
            return true
        }
        CGCancelDisplayConfiguration(config)
        logger.error("Mode switch failed for \(display.stableIdentity, privacy: .public): \(result.rawValue, privacy: .public)")
        return false
    }
}
