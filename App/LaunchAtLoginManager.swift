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

    /// Attempts to update the login item state using the best API available for the platform.
    static func setEnabled(_ shouldEnableLoginItem: Bool) {
        Task.detached(priority: .utility) {
            let start = Date()
            DiagnosticsLogger.shared.log("Login item update requested -> \(shouldEnableLoginItem)", category: "login")
            loginItemLogger.notice("Applying login item state=\(shouldEnableLoginItem, privacy: .public)")

            do {
                try await setEnabledWithServiceManagement(shouldEnableLoginItem)
                let duration = Date().timeIntervalSince(start)
                let durationString = String(format: "%.2f", duration)
                loginItemLogger.notice("Login item set to \(shouldEnableLoginItem, privacy: .public) in \(durationString, privacy: .public)s")
                DiagnosticsLogger.shared.log("Login item set to \(shouldEnableLoginItem) in \(durationString)s", category: "login")
            } catch {
                let duration = Date().timeIntervalSince(start)
                let durationString = String(format: "%.2f", duration)
                loginItemLogger.error("Login item update failed after \(durationString, privacy: .public)s: \(error.localizedDescription, privacy: .public)")
                DiagnosticsLogger.shared.log("Login item update failed after \(durationString)s: \(error.localizedDescription)", category: "login")
            }
        }
    }

    private static func setEnabledWithServiceManagement(_ shouldEnableLoginItem: Bool) async throws {
        // Fast exit when the service is already in the desired state.
        if !needsUpdate(targetState: shouldEnableLoginItem) {
            DiagnosticsLogger.shared.log("SMAppService already \(shouldEnableLoginItem ? "enabled" : "disabled")", category: "login")
            return
        }
        if shouldEnableLoginItem {
            try SMAppService.mainApp.register()
        } else {
            try await SMAppService.mainApp.unregister()
        }
    }

    /// Determines if the SMAppService state differs from the desired state.
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
