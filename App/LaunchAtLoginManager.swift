// MARK: - Login Item Toggle
// Wraps macOS login-item APIs so settings can keep a single entry point.
import Foundation
import ServiceManagement
import OSLog

/// Coordinates enabling or disabling Dimly as a login item.
enum LaunchAtLoginManager {
    private static let loginItemLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Dimly",
        category: "LaunchAtLogin"
    )
    /// State tracking to avoid redundant or failing login item requests.
    private actor State {
        var lastRequestState: Bool?
        var lastRequestDate: Date?
        var suppressedForSession = false

        /// Returns true when the same request was just attempted.
        func shouldSkipDuplicate(state: Bool, threshold: TimeInterval = 5) -> Bool {
            if let date = lastRequestDate, let last = lastRequestState, last == state,
               Date().timeIntervalSince(date) < threshold {
                return true
            }
            return false
        }

        /// Records a login item request for deduplication.
        func markRequest(state: Bool) {
            lastRequestState = state
            lastRequestDate = Date()
        }

        /// Suppresses further attempts after an EPERM failure.
        func suppressAfterEPERM() {
            suppressedForSession = true
        }
    }

    private static let state = State()

    /// Attempts to update the login item state using the best API available for the platform.
    static func setEnabled(_ shouldEnableLoginItem: Bool) {
        Task.detached(priority: .utility) {
            if await state.suppressedForSession {
                DiagnosticsLogger.shared.log("Login item toggle suppressed after previous failure", category: "login")
                return
            }

            if await state.shouldSkipDuplicate(state: shouldEnableLoginItem) {
                DiagnosticsLogger.shared.log("Skipping duplicate login item request \(shouldEnableLoginItem)", category: "login")
                return
            }
            await state.markRequest(state: shouldEnableLoginItem)

            let start = Date()
            DiagnosticsLogger.shared.log("Login item update requested -> \(shouldEnableLoginItem)", category: "login")
            loginItemLogger.notice("Applying login item state=\(shouldEnableLoginItem, privacy: .public)")

            if #available(macOS 13.0, *) {
                // Fast exit when the service is already in the desired state.
                if !needsUpdate(targetState: shouldEnableLoginItem) {
                    DiagnosticsLogger.shared.log("Login item already \(shouldEnableLoginItem ? "enabled" : "disabled")", category: "login")
                    return
                }

                do {
                    if shouldEnableLoginItem {
                        try SMAppService.mainApp.register()
                    } else {
                        try await SMAppService.mainApp.unregister()
                    }
                    let duration = Date().timeIntervalSince(start)
                    let durationString = String(format: "%.2f", duration)
                    loginItemLogger.notice("Login item set to \(shouldEnableLoginItem, privacy: .public) in \(durationString, privacy: .public)s")
                    DiagnosticsLogger.shared.log("Login item set to \(shouldEnableLoginItem) in \(durationString)s", category: "login")
                } catch {
                    let duration = Date().timeIntervalSince(start)
                    let durationString = String(format: "%.2f", duration)
                    loginItemLogger.error("Failed to update login item state after \(durationString, privacy: .public)s: \(error.localizedDescription, privacy: .public)")
                    DiagnosticsLogger.shared.log("Login item update failed after \(durationString)s: \(error.localizedDescription)", category: "login")
                    if (error as NSError).code == EPERM {
                        await state.suppressAfterEPERM()
                        DiagnosticsLogger.shared.log("Suppressing further login item attempts this session after EPERM", category: "login")
                    }
                }
            } else {
                // Pre-macOS 13 fallback relying on the legacy SMLoginItem API.
                guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
                    loginItemLogger.error("Missing bundle identifier; cannot toggle login item.")
                    DiagnosticsLogger.shared.log("Login item update failed: missing bundle id", category: "login")
                    return
                }
                let didUpdateLoginItem = SMLoginItemSetEnabled(bundleIdentifier as CFString, shouldEnableLoginItem)
                let duration = Date().timeIntervalSince(start)
                let durationString = String(format: "%.2f", duration)
                if didUpdateLoginItem {
                    loginItemLogger.notice("Legacy login item set to \(shouldEnableLoginItem, privacy: .public) in \(durationString, privacy: .public)s")
                    DiagnosticsLogger.shared.log("Legacy login item set to \(shouldEnableLoginItem) in \(durationString)s", category: "login")
                } else {
                    loginItemLogger.error("SMLoginItemSetEnabled returned false for identifier \(bundleIdentifier, privacy: .public)")
                    DiagnosticsLogger.shared.log("Legacy login item update failed for \(bundleIdentifier)", category: "login")
                }
            }
        }
    }

    /// Determines if the SMAppService state differs from the desired state.
    @available(macOS 13.0, *)
    private static func needsUpdate(targetState: Bool) -> Bool {
        switch SMAppService.mainApp.status {
        case .enabled:
            return targetState == false
        case .notRegistered:
            return targetState == true
        case .requiresApproval:
            // User still needs to approve in System Settings; keep trying.
            return true
        case .notFound:
            return true
        @unknown default:
            return true
        }
    }
}
