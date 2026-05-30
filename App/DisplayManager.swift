// MARK: - Display Manager
// Publishes live display inventory and coalesces topology-change callbacks.
import Foundation
import Combine
import OSLog
import CoreGraphics
import AppKit

/// Publishes the current display inventory and logs topology changes.
@MainActor
final class DisplayManager: ObservableObject {
    @Published private(set) var displays: [DisplayInfo] = []

    private let hardware: DisplayHardwareProviding
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "DisplayManager")
    private var callbackToken: AnyObject?
    private var appScreenChangeToken: NSObjectProtocol?
    private var appBecameActiveToken: NSObjectProtocol?
    private var workspaceWakeToken: NSObjectProtocol?
    private var workspaceScreensWakeToken: NSObjectProtocol?
    private var topologyRefreshTask: Task<Void, Never>?
    private var refreshGeneration: UInt64 = 0
    private var autoBrightnessObserverPtr: UnsafeMutableRawPointer?

    /// Loads the initial display inventory and subscribes to topology-change notifications.
    init(hardware: DisplayHardwareProviding = DisplayHardware()) {
        self.hardware = hardware
        refresh(reason: "initial boot")
        callbackToken = hardware.registerCallback { [weak self] displayID, flags in
            Task { @MainActor [weak self] in
                self?.handleDisplayChange(displayID: displayID, flags: flags)
            }
        }
        appScreenChangeToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleTopologyRefresh(reason: "didChangeScreenParameters")
            }
        }
        appBecameActiveToken = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh(reason: "appBecameActive")
            }
        }
        workspaceWakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleTopologyRefresh(reason: "workspaceDidWake")
            }
        }
        workspaceScreensWakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleTopologyRefresh(reason: "workspaceScreensDidWake")
            }
        }
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        autoBrightnessObserverPtr = selfPtr
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            selfPtr,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let manager = Unmanaged<DisplayManager>.fromOpaque(observer).takeUnretainedValue()
                Task { @MainActor in
                    manager.scheduleTopologyRefresh(reason: "autoBrightnessPreferenceChanged")
                }
            },
            "com.apple.BezelServices.BMDStatus" as CFString,
            nil,
            .deliverImmediately
        )
        DiagnosticsLogger.shared.log("DisplayManager init", category: "display")
    }

    @MainActor
    deinit {
        topologyRefreshTask?.cancel()
        if let callbackToken {
            hardware.unregisterCallback(callbackToken)
        }
        if let appScreenChangeToken {
            NotificationCenter.default.removeObserver(appScreenChangeToken)
        }
        if let appBecameActiveToken {
            NotificationCenter.default.removeObserver(appBecameActiveToken)
        }
        if let workspaceWakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceWakeToken)
        }
        if let workspaceScreensWakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceScreensWakeToken)
        }
        if let ptr = autoBrightnessObserverPtr {
            CFNotificationCenterRemoveObserver(
                CFNotificationCenterGetDarwinNotifyCenter(),
                ptr,
                CFNotificationName("com.apple.BezelServices.BMDStatus" as CFString),
                nil
            )
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

    /// Runs a short refresh burst to catch delayed topology/orientation settling.
    private func scheduleTopologyRefresh(reason: String) {
        topologyRefreshTask?.cancel()
        DiagnosticsLogger.shared.log("Schedule topology refresh: \(reason)", category: "display")
        topologyRefreshTask = Task { @MainActor [weak self] in
            guard let self else { return }
            self.refresh(reason: reason)
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            self.refresh(reason: "\(reason)-settle-250ms")
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            self.refresh(reason: "\(reason)-settle-1250ms")
        }
    }

    /// Refreshes display metadata off the main actor and tags the work with a generation number.
    private func refresh(reason: String) {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let currentIDs = hardware.activeDisplayIDs()
        DiagnosticsLogger.shared.log("Refresh displays (reason: \(reason)) count=\(currentIDs.count)", category: "display")

        // Resolving display metadata can block on IOKit, so the work runs off-main and returns asynchronously.
        Task.detached(priority: .utility) { [hardware, weak self] in
            let currentDisplays = currentIDs.map { hardware.displayInfo(for: $0) }
            await self?.applyDisplays(currentDisplays, reason: reason, generation: generation)
        }
    }

    /// Applies refreshed display metadata if it still belongs to the latest refresh generation.
    @MainActor
    private func applyDisplays(_ displays: [DisplayInfo], reason: String, generation: UInt64) {
        guard generation == refreshGeneration else {
            DiagnosticsLogger.shared.log("Discard stale display refresh reason=\(reason) generation=\(generation) latest=\(refreshGeneration)", category: "display")
            return
        }
        let previous = self.displays
        guard previous != displays else {
            DiagnosticsLogger.shared.log("Display inventory unchanged reason=\(reason)", category: "display")
            return
        }
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
