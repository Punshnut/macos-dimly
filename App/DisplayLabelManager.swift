// MARK: - Display Label Manager
// Shows per-display numeric overlays to help identify screens.
import SwiftUI
import AppKit
import Combine

/// Controls on-screen numeric overlays used to identify displays.
@MainActor
final class DisplayLabelManager {
    private let settingsStore: AppSettingsStore
    private let displayManager: DisplayManager
    private var overlays: [String: DisplayLabelWindow] = [:]
    private var cancellables: Set<AnyCancellable> = []
    private var isEnabled = false

    /// Observes settings and display changes to keep overlays up to date.
    init(settingsStore: AppSettingsStore, displayManager: DisplayManager) {
        self.settingsStore = settingsStore
        self.displayManager = displayManager
        self.isEnabled = settingsStore.settings.showDisplayNumbers

        settingsStore.$settings
            .map(\.showDisplayNumbers)
            .removeDuplicates()
            .sink { [weak self] enabled in
                self?.isEnabled = enabled
                self?.refresh()
            }
            .store(in: &cancellables)

        displayManager.$displays
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)

        refresh()
    }

    /// Rebuilds overlays based on current display inventory and settings.
    private func refresh() {
        guard isEnabled else {
            hideAll()
            return
        }

        let displays = displayManager.displays
        let internalCount = displays.filter { $0.isBuiltin }.count
        let externalIndexMap = indexMap(for: displays.filter { $0.isExternal })
        let internalIndexMap = indexMap(for: displays.filter { $0.isBuiltin })
        let liveIDs = Set(displays.map(\.stableIdentity))

        // Remove overlays for disconnected displays.
        let stale = overlays.keys.filter { !liveIDs.contains($0) }
        for key in stale {
            overlays[key]?.hide()
            overlays[key]?.close()
            overlays.removeValue(forKey: key)
        }

        for display in displays {
            guard let screen = screen(for: display.displayID) else { continue }
            let externalIndex = externalIndexMap[display.stableIdentity] ?? 1
            let internalIndex = internalIndexMap[display.stableIdentity] ?? 1
            let name = DisplayLabelResolver.displayName(
                for: display,
                settings: settingsStore.settings,
                externalIndex: externalIndex,
                internalIndex: internalIndex
            )
            let marker = DisplayLabelResolver.overlayMarker(
                for: display,
                externalIndex: externalIndex,
                internalIndex: internalIndex,
                internalCount: internalCount
            )
            if let overlay = overlays[display.stableIdentity] {
                overlay.update(marker: marker, title: name, screen: screen)
                overlay.show()
            } else {
                let overlay = DisplayLabelWindow(screen: screen, marker: marker, title: name)
                overlays[display.stableIdentity] = overlay
                overlay.show()
            }
        }
    }

    /// Hides all overlays without destroying them.
    private func hideAll() {
        overlays.values.forEach { $0.hide() }
    }

    /// Stable ordering for numbering internal/external displays.
    private func indexMap(for displays: [DisplayInfo]) -> [String: Int] {
        // Stable, predictable ordering based on displayID.
        let ordered = displays.sorted { $0.displayID < $1.displayID }
        var mapping: [String: Int] = [:]
        for (index, display) in ordered.enumerated() {
            mapping[display.stableIdentity] = index + 1
        }
        return mapping
    }

    /// Finds the NSScreen matching a CoreGraphics display ID.
    private func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return false
            }
            return CGDirectDisplayID(number.uint32Value) == displayID
        }
    }
}

/// Borderless window used to host the SwiftUI overlay on a screen.
private final class DisplayLabelWindow: NSWindow {
    private var hostingView: NSHostingView<DisplayLabelOverlayView>

    /// Creates the window for a specific screen and label.
    init(screen: NSScreen, marker: String, title: String) {
        hostingView = NSHostingView(rootView: DisplayLabelOverlayView(marker: marker, title: title))
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        animationBehavior = .none
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        contentView = hostingView
        setFrame(screen.frame, display: true)
    }

    /// Updates the overlay label and resizes to the target screen.
    func update(marker: String, title: String, screen: NSScreen) {
        hostingView.rootView = DisplayLabelOverlayView(marker: marker, title: title)
        setFrame(screen.frame, display: true)
    }

    /// Shows the overlay window.
    func show() {
        orderFrontRegardless()
    }

    /// Hides the overlay window.
    func hide() {
        orderOut(nil)
    }
}

/// SwiftUI overlay content shown in the label window.
private struct DisplayLabelOverlayView: View {
    let marker: String
    let title: String

    /// Layout for the overlay marker and display title.
    var body: some View {
        ZStack {
            Color.clear
            VStack(spacing: 6) {
                Text(marker)
                    .font(.system(size: 64, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
