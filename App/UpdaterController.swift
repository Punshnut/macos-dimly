// MARK: - Sparkle Integration
// Wraps the updater in a tiny coordinator so menu items can trigger updates safely.
import AppKit
import Sparkle

/// Owns Sparkle's updater and exposes actions for menu items and commands.
@MainActor
final class UpdaterController: NSObject, SPUStandardUserDriverDelegate, SPUUpdaterDelegate {
    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: self
        )
    }()

    override init() {
        super.init()
        _ = updaterController
    }

    /// Invoked from menu items or the menu bar to present Sparkle's update UI.
    @IBAction func checkForUpdates(_ sender: Any?) {
        bringUpdateUIToFront()
        updaterController.checkForUpdates(sender)
    }

    // MARK: - SPUStandardUserDriverDelegate

    /// Ensures Sparkle alerts are visible above the app's windows.
    nonisolated func standardUserDriverWillShowModalAlert() {
        Task { @MainActor [weak self] in
            self?.bringUpdateUIToFront()
        }
    }

    /// Shows a fallback download hint if Sparkle aborts due to signature/validation errors.
    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        Task { @MainActor [weak self] in
            self?.presentFallbackDownloadHintIfNeeded(for: error)
        }
    }

    // MARK: - Private

    /// Activates the app and elevates Sparkle windows so update UI is not hidden.
    private func bringUpdateUIToFront() {
        NotificationCenter.default.post(name: .sparkleWillPresentUpdateUI, object: nil)
        NSApp.activate(ignoringOtherApps: true)
        elevateSparkleWindowsIfNeeded()
        DispatchQueue.main.async { [weak self] in
            self?.elevateSparkleWindowsIfNeeded()
        }
    }

    /// Raises Sparkle windows above other app windows and keeps them on the active space.
    private func elevateSparkleWindowsIfNeeded() {
        let targetLevel = NSWindow.Level.screenSaver
        let behaviors: NSWindow.CollectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]

        for window in NSApp.windows where isSparkleWindow(window) {
            window.level = targetLevel
            window.collectionBehavior.insert(behaviors)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    /// Detects Sparkle windows by class name prefix.
    private func isSparkleWindow(_ window: NSWindow) -> Bool {
        let className = NSStringFromClass(type(of: window))
        return className.hasPrefix("SPU") || className.hasPrefix("SU")
    }

    /// Offers a GitHub download fallback when Sparkle cannot verify an update.
    private func presentFallbackDownloadHintIfNeeded(for error: Error) {
        let nsError = error as NSError
        guard nsError.domain == SUSparkleErrorDomain,
              let sparkleError = SUError(rawValue: OSStatus(nsError.code)),
              sparkleError == .signatureError || sparkleError == .validationError
        else {
            return
        }

        Task { @MainActor in
            let alert = NSAlert()
            alert.messageText = String(localized: "Update could not be verified")
            alert.informativeText = String(localized: "Dimly couldn't verify the downloaded update. Please download the latest release directly from GitHub instead.")
            alert.addButton(withTitle: String(localized: "Open GitHub"))
            alert.addButton(withTitle: String(localized: "Cancel"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn,
               let url = URL(string: "https://github.com/Punshnut/dimly/releases/latest") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

extension Notification.Name {
    /// Posted before Sparkle update UI is shown so windows can be prepared.
    static let sparkleWillPresentUpdateUI = Notification.Name("DimlySparkleWillPresentUpdateUI")
}
