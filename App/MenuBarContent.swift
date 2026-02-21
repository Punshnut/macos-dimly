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
    @State private var builtinBrightnessCacheByDisplayID: [CGDirectDisplayID: Int] = [:]
    private let builtinBrightnessRefreshTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    @Namespace private var modeSwitchNamespace
    @Environment(\.colorScheme) private var colorScheme

    /// Primary menu bar layout rendered inside the status item window.
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            modeSwitchRow
            if isSimpleMode {
                quickActionsSection(includeShowNumbers: false)
                if !menuBarDisplays.isEmpty {
                    externalDisplaysSimpleSection
                }
                appControlsSimpleSection
            } else {
                headerCard
                quickActionsSection(includeShowNumbers: true)
                if !menuBarDisplays.isEmpty {
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
            refreshBuiltinBrightnessCache()
            if presentation == .menuBar {
                handleModifierClickIfNeeded()
                installModifierClickMonitor()
            }
        }
        .onReceive(builtinBrightnessRefreshTimer) { _ in
            refreshBuiltinBrightnessCache()
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
        guard settingsStore.settings.menuBarSimpleMode != enabled else { return }
        let previouslyExpanded = settingsStore.settings.brightnessPanelExpandedDisplayIDs

        // Avoid SwiftUI transition crashes when switching layout branches with expanded
        // brightness dropdowns still mounted.
        if previouslyExpanded.isEmpty == false {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                settingsStore.update { settings in
                    settings.brightnessPanelExpandedDisplayIDs.removeAll()
                }
            }
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            settingsStore.update { settings in
                settings.menuBarSimpleMode = enabled
            }
        }

        guard previouslyExpanded.isEmpty == false else { return }
        // Restore expanded rows after the mode branch transition has settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14) {
            let liveIDs = Set(self.menuBarDisplays.map(\.stableIdentity))
            let restored = previouslyExpanded.filter { liveIDs.contains($0) }
            guard restored.isEmpty == false else { return }
            withAnimation(.spring(response: 0.28, dampingFraction: 0.84)) {
                settingsStore.update { settings in
                    // Keep user intent if mode changed again before restore fired.
                    guard settings.menuBarSimpleMode == enabled else { return }
                    settings.brightnessPanelExpandedDisplayIDs = restored
                }
            }
        }
    }

    private var excludedExternalDisplayIDs: Set<String> {
        Set(settingsStore.settings.menuBarExcludedDisplayIDs)
    }

    private var includedInternalDisplayIDs: Set<String> {
        Set(settingsStore.settings.menuBarIncludedInternalDisplayIDs)
    }

    private var mergeInternalAndExternalDisplays: Bool {
        settingsStore.settings.mergeInternalAndExternalDisplays
    }

    /// External displays visible in Dimly.
    private var visibleExternalDisplays: [DisplayInfo] {
        displayManager.displays.filter { $0.isExternal && excludedExternalDisplayIDs.contains($0.stableIdentity) == false }
    }

    /// Internal displays explicitly shown in Dimly.
    private var visibleInternalDisplays: [DisplayInfo] {
        displayManager.displays.filter { $0.isBuiltin && includedInternalDisplayIDs.contains($0.stableIdentity) }
    }

    /// External displays ordered by the user's preference list.
    private var orderedExternalDisplays: [DisplayInfo] {
        orderExternalDisplays(visibleExternalDisplays)
    }

    /// Internal displays ordered by the user's preference list.
    private var orderedInternalDisplays: [DisplayInfo] {
        orderInternalDisplays(visibleInternalDisplays)
    }

    /// Displays ordered as one merged list when merge mode is enabled.
    private var orderedMergedDisplays: [DisplayInfo] {
        orderMergedDisplays(visibleExternalDisplays + visibleInternalDisplays)
    }

    /// All displays visible in Dimly.
    private var menuBarDisplays: [DisplayInfo] {
        if mergeInternalAndExternalDisplays {
            return orderedMergedDisplays
        }
        return orderedExternalDisplays + orderedInternalDisplays
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
    private var visibleInternalDisplayCount: Int {
        visibleInternalDisplays.count
    }

    /// Number of external displays currently blacked out.
    private var blackoutActiveCount: Int {
        visibleExternalDisplays.filter { blackoutManager.activeDisplayIDs.contains($0.stableIdentity) }.count
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
        let externalCount = visibleExternalDisplays.count
        if externalCount > 0 {
            parts.append(String(format: String(localized: "ExternalCountFormat"), Int64(externalCount)))
        }
        if visibleInternalDisplayCount > 0 {
            parts.append(String(format: String(localized: "InternalCountFormat"), Int64(visibleInternalDisplayCount)))
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
        .disabled(visibleExternalDisplays.isEmpty)
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

    /// Per-display controls and status lines for visible displays.
    private var externalDisplaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(monitorsSectionTitle)
            ForEach(menuBarDisplays) { display in
                displayRow(display)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: orderedExternalIDs())
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: orderedInternalIDs())
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: orderedMergedIDs())
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: settingsStore.settings.brightnessPanelExpandedDisplayIDs)
    }

    /// Simplified per-display list for simple mode.
    private var externalDisplaysSimpleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(monitorsSectionTitle)
            ForEach(menuBarDisplays) { display in
                displayRowSimple(display)
            }
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: orderedExternalIDs())
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: orderedInternalIDs())
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: orderedMergedIDs())
        .animation(.spring(response: 0.25, dampingFraction: 0.82), value: settingsStore.settings.brightnessPanelExpandedDisplayIDs)
    }

    /// Renders a single display row with actions and status.
    private func displayRow(_ display: DisplayInfo) -> some View {
        displayCard(display, includeMenu: true)
    }

    /// Simplified display row showing only alignment arrows and toggle button.
    private func displayRowSimple(_ display: DisplayInfo) -> some View {
        displayCard(display, includeMenu: false)
    }

    /// Shared display card used by both simple and advanced layouts.
    private func displayCard(_ display: DisplayInfo, includeMenu: Bool) -> some View {
        let rowBackground: AnyShapeStyle = AnyShapeStyle(.thinMaterial)
        let rowShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let isExpanded = isBrightnessPanelExpanded(for: display)

        return VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            displayRowHeader(display, includeMenu: includeMenu, isExpanded: isExpanded)
            if isExpanded {
                brightnessDropdown(for: display)
            }
        }
        .padding(8)
        .background(rowBackground)
        .clipShape(rowShape)
        .contentShape(rowShape)
    }

    /// Header row with status and per-display actions; click to expand brightness.
    private func displayRowHeader(_ display: DisplayInfo, includeMenu: Bool, isExpanded: Bool) -> some View {
        let isBlackoutActive = engine.isDisplayBlackoutActive(display)
        let ddcState = ddcManager.states[display.stableIdentity]?.status.localizedDescription ?? String(localized: "Unknown")
        let name = displayName(for: display)
        let status = displayStatus(for: display)
        let marker = displayOverlayMarker(for: display)
        let brightnessText = String.localizedStringWithFormat(
            String(localized: "BrightnessPercentFormat"),
            Int64(brightnessPercent(for: display))
        )

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(name)
                        .font(.subheadline.weight(.semibold))
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    if !isExpanded {
                        Text(brightnessText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(String(format: String(localized: "DisplayRowStatusFormat"), display.resolution, ddcState, status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(marker)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleBrightnessPanel(for: display)
            }
            HStack(spacing: 6) {
                displayOrderButtons(for: display)
                sleepWakeButton(for: display)
                if includeMenu {
                    Menu {
                        Button(isBlackoutActive ? String(localized: "Restore Display") : String(localized: "Blackout Display")) {
                            engine.toggleDisplayBlackout(display: display)
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
        }
    }

    /// Per-display brightness controls (0-100 with DDC/fallback accenting).
    private func brightnessDropdown(for display: DisplayInfo) -> some View {
        let mode = display.isBuiltin ? BrightnessControlMode.ddc : engine.brightnessMode(for: display)
        let tint: Color
        let modeLabel: String
        switch mode {
        case .ddc:
            tint = .green
            modeLabel = String(localized: "DDC")
        case .fallback:
            tint = .blue
            modeLabel = String(localized: "Overlay mode")
        case .checking:
            tint = .orange
            modeLabel = String(localized: "Checking DDC")
        }
        let level = brightnessPercent(for: display)

        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(String(localized: "Brightness"), systemImage: "sun.max.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                Text(
                    String.localizedStringWithFormat(
                        String(localized: "BrightnessPercentFormat"),
                        Int64(level)
                    )
                )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(modeLabel)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(tint.opacity(0.18))
                    .foregroundStyle(tint)
                    .clipShape(Capsule())
            }

            HStack(spacing: 8) {
                Button {
                    nudgeBrightness(for: display, delta: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "Decrease brightness"))

                Slider(
                    value: Binding(
                        get: { Double(brightnessPercent(for: display)) },
                        set: { newValue in
                            setBrightness(Int(newValue.rounded()), for: display)
                        }
                    ),
                    in: 0...100
                )
                .tint(tint)

                Button {
                    nudgeBrightness(for: display, delta: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(String(localized: "Increase brightness"))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(tint.opacity(0.09))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
    }

    /// Builds the per-display control button (sleep/wake for externals, blackout toggle for internals).
    private func sleepWakeButton(for display: DisplayInfo) -> AnyView {
        if display.isBuiltin {
            let isBlackoutActive = engine.isDisplayBlackoutActive(display)
            let label = isBlackoutActive ? String(localized: "Restore Display") : String(localized: "Blackout Display")
            let icon = isBlackoutActive ? "moon.fill" : "sun.max.fill"
            let tint: Color = isBlackoutActive ? .green : .secondary

            return AnyView(
                Button {
                    engine.toggleDisplayBlackout(display: display)
                } label: {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                        .frame(width: 26, height: 26)
                        .background(
                            Circle()
                                .fill(tint.opacity(0.12))
                        )
                }
                .buttonStyle(StaticIconButtonStyle())
                .help(label)
            )
        }

        let state = ddcManager.states[display.stableIdentity] ?? DDCState(status: .unknown, lastError: nil, lastCommand: nil, lastCommandAt: nil)
        let canControl = true
        let ddcSupported = state.status == .supported
        let overlayOnly = settingsStore.settings.overlayOnlyDisplayIDs.contains(display.stableIdentity)
        let fallbackActive = (!ddcSupported || overlayOnly) && blackoutManager.activeDisplayIDs.contains(display.stableIdentity)
        let isAsleep = overlayOnly
            ? blackoutManager.activeDisplayIDs.contains(display.stableIdentity)
            : (ddcSupported ? (state.lastCommand == .standby) : fallbackActive)
        let label = isAsleep ? String(localized: "Wake Display") : String(localized: "Sleep Display")
        let icon = isAsleep ? "moon.zzz" : "sun.max.fill"
        let tint: Color = (ddcSupported && !overlayOnly) ? .green : (fallbackActive ? .blue : .secondary)

        return AnyView(
            Button {
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
        )
    }

    /// Up/down buttons used to reorder displays in their section.
    private func displayOrderButtons(for display: DisplayInfo) -> AnyView {
        let order: [String]
        if mergeInternalAndExternalDisplays {
            order = orderedMergedIDs()
        } else {
            order = display.isExternal ? orderedExternalIDs() : orderedInternalIDs()
        }
        let index = order.firstIndex(of: display.stableIdentity) ?? 0
        let canMoveUp = index > 0
        let canMoveDown = index < (order.count - 1)

        return AnyView(VStack(spacing: 4) {
            Button {
                if mergeInternalAndExternalDisplays {
                    moveMergedDisplayUp(display.stableIdentity)
                } else if display.isExternal {
                    moveExternalDisplayUp(display.stableIdentity)
                } else {
                    moveInternalDisplayUp(display.stableIdentity)
                }
            } label: {
                Image(systemName: "chevron.up")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 12)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveUp)

            Button {
                if mergeInternalAndExternalDisplays {
                    moveMergedDisplayDown(display.stableIdentity)
                } else if display.isExternal {
                    moveExternalDisplayDown(display.stableIdentity)
                } else {
                    moveInternalDisplayDown(display.stableIdentity)
                }
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 18, height: 12)
            }
            .buttonStyle(.plain)
            .disabled(!canMoveDown)
        }
        .foregroundStyle(.secondary)
        .help(String(localized: "Reorder Display")))
    }

    /// UI to save/apply display profiles.
    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Profiles"))
            HStack(spacing: 8) {
                Button {
                    saveCurrentProfileWithPrompt()
                } label: {
                    Label(String(localized: "Save Current Profile"), systemImage: "square.and.arrow.down")
                        .frame(maxWidth: .infinity)
                }
                applyProfileMenuButton(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
    }

    /// Reusable menu button that applies a saved profile.
    private func applyProfileMenuButton(maxWidth: CGFloat? = nil) -> some View {
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
                .frame(maxWidth: maxWidth)
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

            HStack(spacing: 8) {
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label(String(localized: "Quit Dimly"), systemImage: "power")
                }
                Spacer(minLength: 0)
                applyProfileMenuButton()
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private var monitorsSectionTitle: String {
        if visibleExternalDisplays.isEmpty == false && visibleInternalDisplays.isEmpty == false {
            return String(localized: "Monitors")
        }
        return String(localized: "External Displays")
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
        if engine.isDisplayBlackoutActive(display) {
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

    /// Returns whether the display's brightness dropdown is currently expanded.
    private func isBrightnessPanelExpanded(for display: DisplayInfo) -> Bool {
        settingsStore.settings.brightnessPanelExpandedDisplayIDs.contains(display.stableIdentity)
    }

    /// Toggles the persisted expansion state for a display's brightness dropdown.
    private func toggleBrightnessPanel(for display: DisplayInfo) {
        let isExpanding = isBrightnessPanelExpanded(for: display) == false
        settingsStore.update { settings in
            if let index = settings.brightnessPanelExpandedDisplayIDs.firstIndex(of: display.stableIdentity) {
                settings.brightnessPanelExpandedDisplayIDs.remove(at: index)
            } else {
                settings.brightnessPanelExpandedDisplayIDs.append(display.stableIdentity)
            }
        }
        if display.isBuiltin && isExpanding {
            refreshBuiltinBrightness(for: display, persistToSettings: true)
        }
    }

    /// Nudges brightness by a fixed percentage amount.
    private func nudgeBrightness(for display: DisplayInfo, delta: Int) {
        let current = brightnessPercent(for: display)
        let updated = min(100, max(0, current + delta))
        guard updated != current else { return }
        setBrightness(updated, for: display)
    }

    /// Returns display brightness from DDC/overlay for externals, macOS for internals.
    private func brightnessPercent(for display: DisplayInfo) -> Int {
        guard display.isBuiltin else {
            return engine.brightnessPercent(for: display)
        }

        if let liveBrightness = DisplayHardware.builtinDisplayBrightnessPercent(for: display.displayID) {
            if builtinBrightnessCacheByDisplayID[display.displayID] != liveBrightness {
                DispatchQueue.main.async {
                    builtinBrightnessCacheByDisplayID[display.displayID] = liveBrightness
                }
            }
            return builtinBrightnessCacheByDisplayID[display.displayID] ?? liveBrightness
        }

        return builtinBrightnessCacheByDisplayID[display.displayID]
            ?? settingsStore.settings.monitorBrightnessByDisplayID[display.stableIdentity]
            ?? 100
    }

    /// Applies display brightness to the right backend for this display type.
    private func setBrightness(_ percent: Int, for display: DisplayInfo) {
        if display.isBuiltin {
            let clamped = max(0, min(100, percent))
            builtinBrightnessCacheByDisplayID[display.displayID] = clamped
            _ = DisplayHardware.setBuiltinDisplayBrightnessPercent(clamped, for: display.displayID)
            settingsStore.update { settings in
                settings.monitorBrightnessByDisplayID[display.stableIdentity] = clamped
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                if let confirmed = DisplayHardware.builtinDisplayBrightnessPercent(for: display.displayID) {
                    builtinBrightnessCacheByDisplayID[display.displayID] = confirmed
                    settingsStore.update { settings in
                        settings.monitorBrightnessByDisplayID[display.stableIdentity] = confirmed
                    }
                }
            }
            return
        }
        engine.setBrightness(percent, for: display)
    }

    /// Keeps built-in brightness cache in sync while the menu is visible (e.g. media key changes).
    private func refreshBuiltinBrightnessCache() {
        guard visibleInternalDisplays.isEmpty == false else { return }
        for display in visibleInternalDisplays {
            refreshBuiltinBrightness(for: display, persistToSettings: false)
        }
    }

    /// Reads current built-in brightness and updates local cache (and optionally persisted settings).
    private func refreshBuiltinBrightness(for display: DisplayInfo, persistToSettings: Bool) {
        guard display.isBuiltin else { return }
        guard let liveBrightness = DisplayHardware.builtinDisplayBrightnessPercent(for: display.displayID) else { return }
        guard builtinBrightnessCacheByDisplayID[display.displayID] != liveBrightness else { return }

        builtinBrightnessCacheByDisplayID[display.displayID] = liveBrightness
        guard persistToSettings else { return }
        settingsStore.update { settings in
            settings.monitorBrightnessByDisplayID[display.stableIdentity] = liveBrightness
        }
    }

    /// Produces additional status rows for any non-visible displays.
    private func extendedStatusRows() -> [String] {
        let visibleText = String(localized: "Visible")
        return displayManager.displays.compactMap { display in
            if shouldShowInDimly(display) == false {
                return nil
            }
            let status = displayStatus(for: display)
            guard status != visibleText else { return nil }
            return "\(displayName(for: display)) • \(status)"
        }
    }

    private func shouldShowInDimly(_ display: DisplayInfo) -> Bool {
        if display.isBuiltin {
            return includedInternalDisplayIDs.contains(display.stableIdentity)
        }
        if display.isExternal {
            return excludedExternalDisplayIDs.contains(display.stableIdentity) == false
        }
        return true
    }

    private enum SuspendState {
        case none
        case partial
        case full
    }

    /// Roll-up state used to style the sleep button when some/all are asleep.
    private var suspendState: SuspendState {
        let externals = visibleExternalDisplays
        guard externals.isEmpty == false else { return .none }
        let suspendedCount = externals.filter { isDisplaySuspended($0) }.count
        if suspendedCount == 0 { return .none }
        if suspendedCount == externals.count { return .full }
        return .partial
    }

    /// Returns true when the display is in blackout or DDC standby.
    private func isDisplaySuspended(_ display: DisplayInfo) -> Bool {
        if engine.isDisplayBlackoutActive(display) {
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

    /// Orders internal displays using the persisted sort order.
    private func orderInternalDisplays(_ displays: [DisplayInfo]) -> [DisplayInfo] {
        guard displays.isEmpty == false else { return [] }
        let order = settingsStore.settings.internalDisplayOrder
        let byID = Dictionary(uniqueKeysWithValues: displays.map { ($0.stableIdentity, $0) })
        let ordered = order.compactMap { byID[$0] }
        let remaining = displays.filter { order.contains($0.stableIdentity) == false }
            .sorted { $0.displayID < $1.displayID }
        return ordered + remaining
    }

    /// Convenience helper returning internal display IDs in the current order.
    private func orderedInternalIDs() -> [String] {
        orderedInternalDisplays.map(\.stableIdentity)
    }

    /// Orders all visible displays using the merged saved order list.
    private func orderMergedDisplays(_ displays: [DisplayInfo]) -> [DisplayInfo] {
        guard displays.isEmpty == false else { return [] }
        let order = settingsStore.settings.mergedDisplayOrder
        let byID = Dictionary(uniqueKeysWithValues: displays.map { ($0.stableIdentity, $0) })
        let ordered = order.compactMap { byID[$0] }
        let remaining = displays.filter { order.contains($0.stableIdentity) == false }
            .sorted { $0.displayID < $1.displayID }
        return ordered + remaining
    }

    /// Convenience helper returning merged display IDs in the current order.
    private func orderedMergedIDs() -> [String] {
        orderedMergedDisplays.map(\.stableIdentity)
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

    /// Moves the given internal display one slot up in the saved order.
    private func moveInternalDisplayUp(_ id: String) {
        var order = orderedInternalIDs()
        guard let index = order.firstIndex(of: id), index > 0 else { return }
        order.swapAt(index, index - 1)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            settingsStore.update { settings in
                settings.internalDisplayOrder = order
            }
        }
    }

    /// Moves the given internal display one slot down in the saved order.
    private func moveInternalDisplayDown(_ id: String) {
        var order = orderedInternalIDs()
        guard let index = order.firstIndex(of: id), index < (order.count - 1) else { return }
        order.swapAt(index, index + 1)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            settingsStore.update { settings in
                settings.internalDisplayOrder = order
            }
        }
    }

    /// Moves the given display one slot up in the merged order list.
    private func moveMergedDisplayUp(_ id: String) {
        var order = orderedMergedIDs()
        guard let index = order.firstIndex(of: id), index > 0 else { return }
        order.swapAt(index, index - 1)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            settingsStore.update { settings in
                settings.mergedDisplayOrder = order
            }
        }
    }

    /// Moves the given display one slot down in the merged order list.
    private func moveMergedDisplayDown(_ id: String) {
        var order = orderedMergedIDs()
        guard let index = order.firstIndex(of: id), index < (order.count - 1) else { return }
        order.swapAt(index, index + 1)
        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
            settingsStore.update { settings in
                settings.mergedDisplayOrder = order
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
        let response = AlertPresentation.runModalOnCursorScreen(alert)
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

    /// Prompts for a profile name before saving from the advanced menu.
    private func saveCurrentProfileWithPrompt() {
        let alert = NSAlert()
        alert.messageText = String(localized: "Save Current Profile")
        alert.informativeText = String(localized: "Profile name")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let input = NSTextField(string: "")
        input.placeholderString = String(localized: "Profile name")
        input.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = input
        let response = AlertPresentation.runModalOnCursorScreen(alert)
        guard response == .alertFirstButtonReturn else { return }
        profileManager.saveCurrentProfile(named: input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
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
            let blackout = engine.isDisplayBlackoutActive(display) ? String(localized: "Blackout On") : String(localized: "Blackout Off")
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

/// Button style that keeps icon colors stable during pressed state (no accent flash).
private struct StaticIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
