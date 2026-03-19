// MARK: - Login Item Toggle
// Login-item state management.
import Foundation
import ServiceManagement
import OSLog

/// Enables or disables the app login item.
enum LaunchAtLoginManager {
    private static let loginItemLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Dimly",
        category: "LaunchAtLogin"
    )

    /// Updates login-item state using the best API available on this platform.
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

    /// Uses `SMAppService` to register/unregister only when a state change is required.
    private static func setEnabledWithServiceManagement(_ shouldEnableLoginItem: Bool) async throws {
        // Avoid redundant ServiceManagement calls when the current state already matches the request.
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
            // Keep reporting work as pending while macOS is waiting for user approval in System Settings.
            return true
        case .notFound:
            return true
        @unknown default:
            return true
        }
    }
}
