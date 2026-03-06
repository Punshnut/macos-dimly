import AppKit

/// Presents modal alerts on the display that currently contains the mouse cursor.
enum AlertPresentation {
    /// Presents an alert centered on the screen currently under the mouse cursor.
    @MainActor
    static func runModalOnCursorScreen(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let hostOrigin = NSPoint(x: frame.midX, y: frame.midY)
        let hostWindow = NSWindow(
            contentRect: NSRect(origin: hostOrigin, size: NSSize(width: 1, height: 1)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        hostWindow.isOpaque = false
        hostWindow.backgroundColor = .clear
        hostWindow.hasShadow = false
        hostWindow.alphaValue = 0
        hostWindow.ignoresMouseEvents = true
        hostWindow.level = .modalPanel
        hostWindow.collectionBehavior = [.transient, .moveToActiveSpace]
        hostWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let response = runModalAsSheet(alert, for: hostWindow)
        hostWindow.orderOut(nil)
        return response
    }

    /// Runs an `NSAlert` as a sheet and bridges the completion callback to a blocking modal response.
    @MainActor
    private static func runModalAsSheet(_ alert: NSAlert, for window: NSWindow) -> NSApplication.ModalResponse {
        var response: NSApplication.ModalResponse = .abort
        alert.beginSheetModal(for: window) { modalResponse in
            response = modalResponse
            NSApp.stopModal()
        }
        NSApp.runModal(for: window)
        return response
    }
}
