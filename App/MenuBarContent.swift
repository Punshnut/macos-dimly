// MARK: - Menu Bar UI
// Status item popover showing quick actions and app controls.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// SwiftUI menu bar contents shown when the status item is visible.
struct MenuBarContentView: View {
    enum Presentation {
        case menuBar
        case window
    }

    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var blackoutManager: BlackoutManager
    @ObservedObject var ddcManager: DDCManager
    @ObservedObject var profileManager: ProfileManager
    let engine: DimlyEngine
    let updaterController: UpdaterController
    let presentation: Presentation
    @State private var modifierClickMonitor: Any?
    @Namespace private var modeSwitchNamespace
    @Environment(\.colorScheme) private var colorScheme

    /// Primary menu bar layout rendered inside the status item window.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modeSwitchRow
            if isSimpleMode {
                quickActionsSection(includeShowNumbers: false)
                if !externalDisplays.isEmpty {
                    externalDisplaysSimpleSection
                }
                appControlsSimpleSection
            } else {
                headerCard
                quickActionsSection(includeShowNumbers: true)
                if !externalDisplays.isEmpty {
                    externalDisplaysSection
                }
                profilesSection
                appControlsSection
            }
        }
        .padding(12)
        .frame(minWidth: 300)
        .onAppear {
            activateWindowIfNeeded()
            if presentation == .menuBar {
                handleModifierClickIfNeeded()
                installModifierClickMonitor()
            }
        }
        .onDisappear {
            removeModifierClickMonitor()
        }
    }

    /// Brings the menu bar popover window forward for better keyboard focus.
    private func activateWindowIfNeeded() {
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            let candidate = presentation == .menuBar
                ? NSApp.windows.first { window in
                    window.level == .statusBar || window.level == .popUpMenu
                }
                : NSApp.keyWindow
            candidate?.makeKeyAndOrderFront(nil)
        }
    }

    /// Handles option/control modifier clicks to trigger quick actions.
    private func handleModifierClickIfNeeded() {
        guard let event = NSApp.currentEvent else { return }
        guard event.type == .leftMouseUp || event.type == .leftMouseDown else { return }
        let flags = event.modifierFlags
        if flags.contains(.option) {
            engine.toggleExternalBlackout()
            if event.type == .leftMouseDown, presentation == .menuBar {
                closeMenuBarWindow()
            }
        } else if flags.contains(.control) {
            engine.toggleExternalSleepWake()
            if event.type == .leftMouseDown, presentation == .menuBar {
                closeMenuBarWindow()
            }
        }
    }

    /// Installs a local monitor so modifier clicks work while the menu is open.
    private func installModifierClickMonitor() {
        guard modifierClickMonitor == nil else { return }
        modifierClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { event in
            let flags = event.modifierFlags
            if flags.contains(.option) {
                engine.toggleExternalBlackout()
            } else if flags.contains(.control) {
                engine.toggleExternalSleepWake()
            }
            return event
        }
    }

    /// Removes the event monitor to avoid leaks when the menu closes.
    private func removeModifierClickMonitor() {
        if let modifierClickMonitor {
            NSEvent.removeMonitor(modifierClickMonitor)
            self.modifierClickMonitor = nil
        }
    }

    /// Closes the menu bar window after a modifier-triggered action.
    private func closeMenuBarWindow() {
        guard presentation == .menuBar else { return }
        DispatchQueue.main.async {
            let candidate = NSApp.windows.first { window in
                window.level == .statusBar || window.level == .popUpMenu
            } ?? NSApp.keyWindow
            candidate?.orderOut(nil)
        }
    }

    /// Top-level switch between simple and advanced layouts.
    private var modeSwitchRow: some View {
        HStack(spacing: 10) {
            Text(String(localized: "Mode"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            HStack(spacing: 6) {
                modeSwitchButton(title: String(localized: "Simple"), isActive: isSimpleMode) {
                    setSimpleMode(true)
                }
                modeSwitchButton(title: String(localized: "Advanced"), isActive: !isSimpleMode) {
                    setSimpleMode(false)
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(Color.secondary.opacity(0.12))
            )
        }
    }

    private func modeSwitchButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? .primary : .secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(alignment: .center) {
                    if isActive {
                        Capsule()
                            .fill(Color.accentColor.opacity(0.25))
                            .matchedGeometryEffect(id: "modeSwitch", in: modeSwitchNamespace)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var isSimpleMode: Bool {
        settingsStore.settings.menuBarSimpleMode
    }

    private func setSimpleMode(_ enabled: Bool) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            settingsStore.update { settings in
                settings.menuBarSimpleMode = enabled
            }
        }
    }

    /// External displays only, as seen by the display manager.
    private var externalDisplays: [DisplayInfo] {
        displayManager.displays.filter { $0.isExternal }
    }

    /// External displays ordered by the user's preference list.
    private var orderedExternalDisplays: [DisplayInfo] {
        orderExternalDisplays(externalDisplays)
    }

    /// Map of display stable IDs to their external index number.
    private var externalIndexMap: [String: Int] {
        indexMap(for: displayManager.displays.filter { $0.isExternal })
    }

    /// Map of display stable IDs to their internal index number.
    private var internalIndexMap: [String: Int] {
        indexMap(for: displayManager.displays.filter { $0.isBuiltin })
    }

    /// Count of internal (built-in) panels.
    private var internalDisplayCount: Int {
        displayManager.displays.filter { $0.isBuiltin }.count
    }

    /// Number of external displays currently blacked out.
    private var blackoutActiveCount: Int {
        externalDisplays.filter { blackoutManager.activeDisplayIDs.contains($0.stableIdentity) }.count
    }

    /// Summary card showing active display count and overall status.
    private var headerCard: some View {
        let count = displayManager.displays.count
        let countText = String(format: NSLocalizedString("DisplayCountFormat", comment: "Menu bar display count"), count)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "display.2")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(.ultraThinMaterial))
                VStack(alignment: .leading, spacing: 2) {
                    Text(countText)
                        .font(.headline)
                    Text(displaySummaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if count > 0 {
                    statusPill
                }
            }
            extendedStatusView
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// One-line summary of internal vs external display counts.
    private var displaySummaryText: String {
        var parts: [String] = []
        let externalCount = externalDisplays.count
        if externalCount > 0 {
            parts.append(String(format: String(localized: "ExternalCountFormat"), Int64(externalCount)))
        }
        if internalDisplayCount > 0 {
            parts.append(String(format: String(localized: "InternalCountFormat"), Int64(internalDisplayCount)))
        }
        return parts.isEmpty ? String(localized: "No displays detected") : parts.joined(separator: " • ")
    }

    /// Small badge highlighting blackout status.
    private var statusPill: some View {
        let isBlackoutActive = blackoutActiveCount > 0
        return Text(isBlackoutActive ? String(localized: "Blackout On") : String(localized: "Ready"))
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(isBlackoutActive ? Color.red.opacity(0.18) : Color.green.opacity(0.18))
            .foregroundStyle(isBlackoutActive ? .red : .green)
            .clipShape(Capsule())
    }

    /// Optional list of non-visible displays (sleep/blackout).
    private var extendedStatusView: some View {
        let rows = extendedStatusRows()
        if rows.isEmpty {
            return AnyView(
                Text(String(localized: "All displays active"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            )
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.self) { row in
                    Text(row)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        )
    }

    /// Prominent actions for global blackout/sleep/wake.
    private func quickActionsSection(includeShowNumbers: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Quick Actions"))
            Button {
                engine.toggleExternalBlackout()
            } label: {
                Label(String(localized: "Toggle External Blackout"), systemImage: "moon.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            suspendAllButtons

            Button {
                engine.panicBlackout(animated: settingsStore.settings.fadeInAnimationEnabled)
            } label: {
                Label(String(localized: "Panic: All On"), systemImage: "exclamationmark.triangle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .tint(.red)

            if includeShowNumbers {
                Toggle(isOn: Binding(
                    get: { settingsStore.settings.showDisplayNumbers },
                    set: { newValue in settingsStore.update { $0.showDisplayNumbers = newValue } }
                )) {
                    Label(String(localized: "Show Display Numbers"), systemImage: "number.circle")
                }
                .toggleStyle(.switch)
            }
        }
    }

    /// Side-by-side sleep and wake buttons for all externals.
    private var suspendAllButtons: some View {
        HStack(spacing: 8) {
            suspendAllButton
            Button {
                engine.wakeExternalDisplays()
            } label: {
                Label(String(localized: "Wake Externals"), systemImage: "sun.max.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .disabled(externalDisplays.isEmpty)
    }

    /// Sleep button that reflects whether all/partial/none are asleep.
    private var suspendAllButton: some View {
        let state = suspendState
        let tint: Color = state == .full ? .red : .primary
        let strokeColor: Color = state == .partial ? .orange : .clear

        let button = Button {
            engine.sleepExternalDisplays()
        } label: {
            Label(String(localized: "Sleep Externals"), systemImage: "moon.zzz")
                .frame(maxWidth: .infinity)
        }
        .tint(tint)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(strokeColor, lineWidth: 2)
        )
        .help(String(localized: "Sleep Externals"))

        if state == .full {
            return AnyView(button.buttonStyle(BorderedProminentButtonStyle()))
        }
        return AnyView(button.buttonStyle(BorderedButtonStyle()))
    }

    /// Per-display controls and status lines for external displays.
    private var externalDisplaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "External Displays"))
            ForEach(orderedExternalDisplays) { display in
                displayRow(display)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: orderedExternalIDs())
    }

    /// Simplified per-display list for simple mode.
    private var externalDisplaysSimpleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "External Displays"))
            ForEach(orderedExternalDisplays) { display in
                displayRowSimple(display)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: orderedExternalIDs())
    }

    /// Renders a single display row with actions and status.
    private func displayRow(_ display: DisplayInfo) -> some View {
        let isBlackoutActive = blackoutManager.activeDisplayIDs.contains(display.stableIdentity)
        let ddcState = ddcManager.states[display.stableIdentity]?.status.localizedDescription ?? String(localized: "Unknown")
        let name = displayName(for: display)
        let status = displayStatus(for: display)
        let marker = displayOverlayMarker(for: display)
        let rowBackground: AnyShapeStyle = AnyShapeStyle(.thinMaterial)
        let rowShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let content = HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(String(format: String(localized: "DisplayRowStatusFormat"), display.resolution, ddcState, status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(marker)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                displayOrderButtons(for: display)
                sleepWakeButton(for: display)
                Menu {
                    Button(isBlackoutActive ? String(localized: "Restore Display") : String(localized: "Blackout Display")) {
                        let settings = settingsStore.settings
                        blackoutManager.toggle(display: display, fadeOut: settings.fadeOutAnimationEnabled, fadeIn: settings.fadeInAnimationEnabled)
                    }
                    Button(String(localized: "Sleep Display")) {
                        engine.standby(display: display)
                    }
                    Button(String(localized: "Wake Display")) {
                        engine.wake(display: display)
                    }
                    Toggle(isOn: Binding(
                        get: { settingsStore.settings.overlayOnlyDisplayIDs.contains(display.stableIdentity) },
                        set: { enabled in
                            settingsStore.update { settings in
                                if enabled {
                                    if settings.overlayOnlyDisplayIDs.contains(display.stableIdentity) == false {
                                        settings.overlayOnlyDisplayIDs.append(display.stableIdentity)
                                    }
                                } else {
                                    settings.overlayOnlyDisplayIDs.removeAll { $0 == display.stableIdentity }
                                }
                            }
                        }
                    )) {
                        Text(String(localized: "Overlay Only (Never Sleep)"))
                    }
                    Divider()
                    Button(String(localized: "Rename Display...")) {
                        renameDisplay(display, currentName: name)
                    }
                    Button(String(localized: "Copy Display ID")) {
                        copyDisplayID(display.stableIdentity)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(Color.secondary.opacity(0.12))
                        )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }
        }
        return content
        .padding(8)
        .background(rowBackground)
        .clipShape(rowShape)
        .contentShape(rowShape)
    }

    /// Simplified display row showing only alignment arrows and toggle button.
    private func displayRowSimple(_ display: DisplayInfo) -> some View {
        let ddcState = ddcManager.states[display.stableIdentity]?.status.localizedDescription ?? String(localized: "Unknown")
        let name = displayName(for: display)
        let status = displayStatus(for: display)
        let marker = displayOverlayMarker(for: display)
        let rowBackground: AnyShapeStyle = AnyShapeStyle(.thinMaterial)
        let rowShape = RoundedRectangle(cornerRadius: 10, style: .continuous)

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 6) {
                    Text(String(format: String(localized: "DisplayRowStatusFormat"), display.resolution, ddcState, status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(marker)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            HStack(spacing: 6) {
                displayOrderButtons(for: display)
                sleepWakeButton(for: display)
            }
        }
        .padding(8)
        .background(rowBackground)
        .clipShape(rowShape)
        .contentShape(rowShape)
    }

    /// Builds the sleep/wake button, respecting DDC support and overlay-only settings.
    private func sleepWakeButton(for display: DisplayInfo) -> some View {
        let state = ddcManager.states[display.stableIdentity] ?? DDCState(status: .unknown, lastError: nil, lastCommand: nil, lastCommandAt: nil)
        let canControl = display.isExternal
        let ddcSupported = state.status == .supported
        let overlayOnly = settingsStore.settings.overlayOnlyDisplayIDs.contains(display.stableIdentity)
        let fallbackActive = (!ddcSupported || overlayOnly) && blackoutManager.activeDisplayIDs.contains(display.stableIdentity)
        let isAsleep = overlayOnly
            ? blackoutManager.activeDisplayIDs.contains(display.stableIdentity)
            : (ddcSupported ? (state.lastCommand == .standby) : fallbackActive)
        let label = isAsleep ? String(localized: "Wake Display") : String(localized: "Sleep Display")
        let icon = isAsleep ? "moon.zzz" : "sun.max.fill"
        let tint: Color = (ddcSupported && !overlayOnly) ? .green : (fallbackActive ? .blue : .secondary)

        return Button {
            if isAsleep {
                engine.wake(display: display)
            } else {
                engine.standby(display: display)
            }
        } label: {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(canControl ? tint : .secondary)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill((canControl ? tint : .secondary).opacity(0.12))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canControl)
        .help(label)
    }

    /// Up/down buttons used to reorder external displays.
    private func displayOrderButtons(for display: DisplayInfo) -> some View {
        let order = orderedExternalIDs()
        let index = order.firstIndex(of: display.stableIdentity) ?? 0
        let canMoveUp = index > 0
        let canMoveDown = index < (order.count - 1)

        return VStack(spacing: 4) {
            Button {
                moveExternalDisplayUp(display.stableIdentity)
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 12)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveUp)

            Button {
                moveExternalDisplayDown(display.stableIdentity)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 12)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDown)
        }
        .foregroundStyle(.secondary)
        .help(String(localized: "Reorder Display"))
    }

    /// UI to save/apply display profiles.
    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Profiles"))
            HStack(spacing: 8) {
                Button {
                    profileManager.saveCurrentProfile(named: "")
                } label: {
                    Label(String(localized: "Save Current Profile"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                Menu {
                    if profileManager.profiles.isEmpty {
                        Button(String(localized: "No profiles yet")) {}
                            .disabled(true)
                    } else {
                        ForEach(profileManager.profiles) { profile in
                            Button(profile.name) {
                                profileManager.apply(profile: profile)
                            }
                        }
                    }
                } label: {
                    Label(String(localized: "Apply Profile"), systemImage: "rectangle.3.group")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    /// App-level utilities such as settings, diagnostics, and quit.
    private var appControlsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "App"))
            let columns = [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                Button {
                    copyDisplayReport()
                } label: {
                    Label(String(localized: "Copy Display Report"), systemImage: "doc.on.doc")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    openDiagnosticsLog()
                } label: {
                    Label(String(localized: "Open Diagnostics Log"), systemImage: "doc.text.magnifyingglass")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                SettingsLink {
                    Label(String(localized: "Settings..."), systemImage: "gearshape")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    updaterController.checkForUpdates(nil)
                } label: {
                    Label(String(localized: "Check for Updates..."), systemImage: "arrow.triangle.2.circlepath")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Divider()
            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label(String(localized: "Quit Dimly"), systemImage: "power")
            }
        }
    }

    /// Simplified app controls for simple mode.
    private var appControlsSimpleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "App"))
            let columns = [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                SettingsLink {
                    Label(String(localized: "Settings..."), systemImage: "gearshape")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    updaterController.checkForUpdates(nil)
                } label: {
                    Label(String(localized: "Check for Updates..."), systemImage: "arrow.triangle.2.circlepath")
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Divider()

            Button(role: .destructive) {
                NSApp.terminate(nil)
            } label: {
                Label(String(localized: "Quit Dimly"), systemImage: "power")
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Standard section header styling used in the popover.
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
    }

    /// Resolves a human-friendly display name using settings and metadata.
    private func displayName(for display: DisplayInfo) -> String {
        let externalIndex = externalIndexMap[display.stableIdentity] ?? 1
        let internalIndex = internalIndexMap[display.stableIdentity] ?? 1
        return DisplayLabelResolver.displayName(
            for: display,
            settings: settingsStore.settings,
            externalIndex: externalIndex,
            internalIndex: internalIndex
        )
    }

    /// Computes the visibility/sleep/blackout status for a display.
    private func displayStatus(for display: DisplayInfo) -> String {
        if blackoutManager.activeDisplayIDs.contains(display.stableIdentity) {
            return String(localized: "Blackout")
        }
        if settingsStore.settings.overlayOnlyDisplayIDs.contains(display.stableIdentity) == false,
           ddcManager.states[display.stableIdentity]?.lastCommand == .standby {
            return String(localized: "Sleep requested")
        }
        return String(localized: "Visible")
    }

    /// Determines the overlay label shown on-screen for a display.
    private func displayOverlayMarker(for display: DisplayInfo) -> String {
        let internalCount = displayManager.displays.filter { $0.isBuiltin }.count
        let externalIndex = externalIndexMap[display.stableIdentity] ?? 1
        let internalIndex = internalIndexMap[display.stableIdentity] ?? 1
        return DisplayLabelResolver.overlayMarker(
            for: display,
            externalIndex: externalIndex,
            internalIndex: internalIndex,
            internalCount: internalCount
        )
    }

    /// Produces additional status rows for any non-visible displays.
    private func extendedStatusRows() -> [String] {
        let visibleText = String(localized: "Visible")
        return displayManager.displays.compactMap { display in
            let status = displayStatus(for: display)
            guard status != visibleText else { return nil }
            return "\(displayName(for: display)) • \(status)"
        }
    }

    private enum SuspendState {
        case none
        case partial
        case full
    }

    /// Roll-up state used to style the sleep button when some/all are asleep.
    private var suspendState: SuspendState {
        let externals = externalDisplays
        guard externals.isEmpty == false else { return .none }
        let suspendedCount = externals.filter { isDisplaySuspended($0) }.count
        if suspendedCount == 0 { return .none }
        if suspendedCount == externals.count { return .full }
        return .partial
    }

    /// Returns true when the display is in blackout or DDC standby.
    private func isDisplaySuspended(_ display: DisplayInfo) -> Bool {
        if blackoutManager.activeDisplayIDs.contains(display.stableIdentity) {
            return true
        }
        return ddcManager.states[display.stableIdentity]?.lastCommand == .standby
    }

    /// Creates a stable index map for display numbering.
    private func indexMap(for displays: [DisplayInfo]) -> [String: Int] {
        let ordered = displays.sorted { $0.displayID < $1.displayID }
        var mapping: [String: Int] = [:]
        for (index, display) in ordered.enumerated() {
            mapping[display.stableIdentity] = index + 1
        }
        return mapping
    }

    /// Orders external displays using the persisted sort order.
    private func orderExternalDisplays(_ displays: [DisplayInfo]) -> [DisplayInfo] {
        guard displays.isEmpty == false else { return [] }
        let order = settingsStore.settings.externalDisplayOrder
        let byID = Dictionary(uniqueKeysWithValues: displays.map { ($0.stableIdentity, $0) })
        let ordered = order.compactMap { byID[$0] }
        let remaining = displays.filter { order.contains($0.stableIdentity) == false }
            .sorted { $0.displayID < $1.displayID }
        return ordered + remaining
    }

    /// Convenience helper returning external display IDs in the current order.
    private func orderedExternalIDs() -> [String] {
        orderedExternalDisplays.map(\.stableIdentity)
    }

    /// Swaps two external displays in the saved order list.
    private func moveExternalDisplay(from draggedID: String, to targetID: String) {
        var order = orderedExternalIDs()
        guard let fromIndex = order.firstIndex(of: draggedID),
              let toIndex = order.firstIndex(of: targetID),
              fromIndex != toIndex else { return }
        order.swapAt(fromIndex, toIndex)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            settingsStore.update { settings in
                settings.externalDisplayOrder = order
            }
        }
    }

    /// Moves the given display one slot up in the saved order.
    private func moveExternalDisplayUp(_ id: String) {
        var order = orderedExternalIDs()
        guard let index = order.firstIndex(of: id), index > 0 else { return }
        order.swapAt(index, index - 1)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            settingsStore.update { settings in
                settings.externalDisplayOrder = order
            }
        }
    }

    /// Moves the given display one slot down in the saved order.
    private func moveExternalDisplayDown(_ id: String) {
        var order = orderedExternalIDs()
        guard let index = order.firstIndex(of: id), index < (order.count - 1) else { return }
        order.swapAt(index, index + 1)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            settingsStore.update { settings in
                settings.externalDisplayOrder = order
            }
        }
    }

    /// Copies a plain-text report of all displays to the clipboard.
    private func copyDisplayReport() {
        let report = buildDisplayReport()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
    }

    /// Copies a single display's stable ID to the clipboard.
    private func copyDisplayID(_ id: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(id, forType: .string)
    }

    /// Presents a prompt to rename the given display.
    private func renameDisplay(_ display: DisplayInfo, currentName: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Display")
        alert.informativeText = String(localized: "Give this display a friendly name.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let input = NSTextField(string: currentName)
        input.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = input
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            let trimmed = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            settingsStore.update { settings in
                if trimmed.isEmpty {
                    settings.displayAliases.removeValue(forKey: display.stableIdentity)
                } else {
                    settings.displayAliases[display.stableIdentity] = trimmed
                }
            }
        }
    }

    /// Builds a human-readable report for troubleshooting.
    private func buildDisplayReport() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let timestamp = formatter.string(from: Date())
        var lines: [String] = []
        lines.append(String(localized: "DisplayReportTitle"))
        lines.append(String(format: String(localized: "DisplayReportGeneratedFormat"), timestamp))
        lines.append("")

        for display in displayManager.displays {
            let name = displayName(for: display)
            let type = display.isExternal ? String(localized: "External") : String(localized: "Internal")
            let refresh = display.refreshRateHz.map { String(format: String(localized: "DisplayReportRefreshRateFormat"), $0) } ?? String(localized: "DisplayReportRefreshNA")
            let ddc = ddcManager.states[display.stableIdentity]?.status.localizedDescription ?? String(localized: "Unknown")
            let blackout = blackoutManager.activeDisplayIDs.contains(display.stableIdentity) ? String(localized: "Blackout On") : String(localized: "Blackout Off")
            lines.append(String(format: String(localized: "DisplayReportLineFormat"), name, type))
            lines.append(String(format: String(localized: "DisplayReportResolutionFormat"), display.resolution))
            lines.append(String(format: String(localized: "DisplayReportRefreshFormat"), refresh))
            lines.append(String(format: String(localized: "DisplayReportDDCFormat"), ddc, blackout))
            lines.append(String(format: String(localized: "DisplayReportIDFormat"), display.stableIdentity))
            lines.append("")
        }

        return lines.joined(separator: "\n")
    }

    /// Opens the diagnostics log in Finder.
    private func openDiagnosticsLog() {
        let url = DiagnosticsLogger.shared.logFileURL
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
