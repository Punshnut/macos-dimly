// MARK: - Display Manager
// Publishes live display inventory and normalizes change callbacks.
import Foundation
import Combine
import OSLog
import CoreGraphics

/// Publishes a live list of connected displays and logs changes.
@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []

    private let hardware: DisplayHardwareProviding
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "DisplayManager")
    private var callbackToken: AnyObject?

    /// Loads initial display inventory and installs change callbacks.
    init(hardware: DisplayHardwareProviding = DisplayHardware()) {
        self.hardware = hardware
        refresh(reason: "initial boot")
        callbackToken = hardware.registerCallback { [weak self] displayID, flags in
            Task { @MainActor [weak self] in
                self?.handleDisplayChange(displayID: displayID, flags: flags)
            }
        }
        DiagnosticsLogger.shared.log("DisplayManager init", category: "display")
    }

    @MainActor
    deinit {
        if let callbackToken {
            hardware.unregisterCallback(callbackToken)
        }
    }

    // MARK: - Private

    /// Handles CoreGraphics change callbacks and refreshes display state.
    private func handleDisplayChange(displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        let changeDesc = flagDescription(flags)
        logger.notice("Display change detected for id \(displayID, privacy: .public): \(changeDesc, privacy: .public)")
        DiagnosticsLogger.shared.log("Display change id=\(displayID) flags=\(changeDesc)", category: "display")
        refresh(reason: changeDesc)
    }

    /// Refreshes display info off the main actor.
    private func refresh(reason: String) {
        let previous = displays
        let currentIDs = hardware.activeDisplayIDs()
        DiagnosticsLogger.shared.log("Refresh displays (reason: \(reason)) count=\(currentIDs.count)", category: "display")

        // Resolving display info can block on IOKit; perform off the main actor and marshal back.
        Task.detached(priority: .utility) { [hardware, weak self] in
            let currentDisplays = currentIDs.map { hardware.displayInfo(for: $0) }
            await self?.applyDisplays(currentDisplays, previous: previous, reason: reason)
        }
    }

    /// Applies new display info and logs changes.
    @MainActor
    private func applyDisplays(_ displays: [DisplayInfo], previous: [DisplayInfo], reason: String) {
        self.displays = displays
        logDiff(previous: previous, current: displays, reason: reason)
        logInventory(displays, reason: reason)
        DiagnosticsLogger.shared.log("Applied displays: prev=\(previous.count) curr=\(displays.count) reason=\(reason)", category: "display")
    }

    /// Logs display additions/removals.
    private func logDiff(previous: [DisplayInfo], current: [DisplayInfo], reason: String) {
        let prevIDs = Set(previous.map(\.stableIdentity))
        let currIDs = Set(current.map(\.stableIdentity))
        let added = currIDs.subtracting(prevIDs)
        let removed = prevIDs.subtracting(currIDs)
        for id in added {
            logger.notice("Display connected (\(reason, privacy: .public)): \(id, privacy: .public)")
        }
        for id in removed {
            logger.notice("Display disconnected (\(reason, privacy: .public)): \(id, privacy: .public)")
        }
    }

    /// Logs a full inventory snapshot for diagnostics.
    private func logInventory(_ displays: [DisplayInfo], reason: String) {
        for display in displays {
            let origin = display.isBuiltin ? "builtin" : "external"
            let refresh = display.refreshRateHz.map { String(format: "%.0fHz", $0) } ?? "n/a"
            let name = display.name ?? "Unknown"
            logger.notice("Display inventory (\(reason, privacy: .public)): \(origin, privacy: .public) id=\(display.stableIdentity, privacy: .public) res=\(display.resolution, privacy: .public) refresh=\(refresh, privacy: .public) name=\(name, privacy: .public)")
            DiagnosticsLogger.shared.log("Display \(origin) id=\(display.stableIdentity) name=\(name) res=\(display.resolution) refresh=\(refresh) reason=\(reason)", category: "display")
        }
    }

    /// Converts CGDisplay change flags into a readable string.
    private func flagDescription(_ flags: CGDisplayChangeSummaryFlags) -> String {
        var parts: [String] = []
        if flags.contains(.addFlag) { parts.append("add") }
        if flags.contains(.removeFlag) { parts.append("remove") }
        if flags.contains(.movedFlag) { parts.append("moved") }
        if flags.contains(.enabledFlag) { parts.append("enabled") }
        if flags.contains(.disabledFlag) { parts.append("disabled") }
        if flags.contains(.setMainFlag) { parts.append("setMain") }
        return parts.isEmpty ? "unknown change" : parts.joined(separator: ", ")
    }
}
