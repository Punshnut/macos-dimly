import AppKit

/// Presents modal alerts on the display that currently contains the mouse cursor.
enum AlertPresentation {
    /// Presents an alert centered on the screen currently under the mouse cursor.
    @MainActor
    static func runModalOnCursorScreen(_ alert: NSAlert) -> NSApplication.ModalResponse {
        let mouseLocation = NSEvent.mouseLocation
        let screen = targetScreen(for: mouseLocation) ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let alertWindow = alert.window
        let centeredOrigin = NSPoint(
            x: visibleFrame.midX - (alertWindow.frame.width * 0.5),
            y: visibleFrame.midY - (alertWindow.frame.height * 0.5)
        )
        alertWindow.setFrameOrigin(centeredOrigin)
        alertWindow.level = .modalPanel
        alertWindow.collectionBehavior = [.transient, .moveToActiveSpace]
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal()
    }

    /// Resolves the best target screen for the cursor, including monitor-edge fallback.
    @MainActor
    private static func targetScreen(for cursorLocation: NSPoint) -> NSScreen? {
        if let containing = NSScreen.screens.first(where: { screen in
            // Expand the hit area slightly so border-adjacent cursor positions still map to a screen.
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
