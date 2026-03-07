import AppKit

/// Presents modal alerts on the display that currently contains the mouse cursor.
enum AlertPresentation {
    /// Presents an alert centered on the screen currently under the mouse cursor.
    @MainActor
    static func runModalOnCursorScreen(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let mouseLocation = NSEvent.mouseLocation
        let screen = targetScreen(for: mouseLocation) ?? NSScreen.main
        let frame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let hostOrigin = NSPoint(x: frame.midX - 0.5, y: frame.midY - 0.5)
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

    /// Resolves the best target screen for the cursor, including monitor-edge fallback.
    @MainActor
    private static func targetScreen(for cursorLocation: NSPoint) -> NSScreen? {
        if let containing = NSScreen.screens.first(where: { screen in
            // Use a tiny inset so edge-aligned cursor points still resolve to a display.
            screen.frame.insetBy(dx: -1, dy: -1).contains(cursorLocation)
        }) {
            return containing
        }
        return NSScreen.screens.min { lhs, rhs in
            distanceSquared(from: cursorLocation, to: lhs.frame) < distanceSquared(from: cursorLocation, to: rhs.frame)
        }
    }

    /// Squared distance between a point and the nearest point in a rectangle.
    private static func distanceSquared(from point: NSPoint, to rect: NSRect) -> CGFloat {
        let clampedX = min(max(point.x, rect.minX), rect.maxX)
        let clampedY = min(max(point.y, rect.minY), rect.maxY)
        let dx = point.x - clampedX
        let dy = point.y - clampedY
        return (dx * dx) + (dy * dy)
    }
}
