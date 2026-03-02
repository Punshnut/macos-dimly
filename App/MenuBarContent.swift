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

    private enum LayoutMode: Equatable {
        case simple
        case advanced
        case short
    }

    private enum SmartButtonDropTarget: Equatable {
        case before(UUID)
        case after(UUID)
    }

    private enum SmartButtonGridItem: Identifiable, Equatable {
        case profile(UUID)
        case spacerBefore(UUID)
        case spacerAfter(UUID)

        var id: String {
            switch self {
            case .profile(let id):
                return "profile-\(id.uuidString)"
            case .spacerBefore(let targetID):
                return "spacer-before-\(targetID.uuidString)"
            case .spacerAfter(let targetID):
                return "spacer-after-\(targetID.uuidString)"
            }
        }
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
    @State private var draggedSmartButtonProfileID: UUID?
    @State private var smartButtonFramesByProfileID: [UUID: CGRect] = [:]
    @State private var smartButtonDragStartFramesByProfileID: [UUID: CGRect] = [:]
    @State private var smartButtonDragTranslation: CGSize = .zero
    @State private var smartButtonDropTarget: SmartButtonDropTarget?
    private let builtinBrightnessRefreshTimer = Timer.publish(every: 0.4, on: .main, in: .common).autoconnect()
    private let smartButtonsGridCoordinateSpace = "smartButtonsGrid"
    @Namespace private var modeSwitchNamespace
    @Environment(\.colorScheme) private var colorScheme

    /// Primary menu bar layout rendered inside the status item window.
    var body: some View {
        VStack(alignment: .leading, spacing: sectionSpacing) {
            modeSwitchRow
            switch activeLayoutMode {
            case .simple:
                quickActionsSection(includeShowNumbers: false)
                smartButtonsSection(compact: false)
                if !menuBarDisplays.isEmpty {
                    externalDisplaysSimpleSection
                }
                appControlsSimpleSection
            case .advanced:
                headerCard
                quickActionsSection(includeShowNumbers: true)
                smartButtonsSection(compact: true)
                if !menuBarDisplays.isEmpty {
                    externalDisplaysSection
                }
                profilesSection
                appControlsSection
            case .short:
                quickActionsSection(includeShowNumbers: false)
                smartButtonsSection(compact: false)
                shortModeAppActionsSection
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
        .preferredColorScheme(preferredColorSchemeSelection)
    }

    private var sectionSpacing: CGFloat { 12 }

    private var neutralPrimaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.95) : Color.black.opacity(0.86)
    }

    private var neutralSecondaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.76) : Color.black.opacity(0.62)
    }

    private var neutralTertiaryText: Color {
        colorScheme == .dark ? Color.white.opacity(0.56) : Color.black.opacity(0.46)
    }

    private var neutralCardFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.white.opacity(0.5)
    }

    private var neutralCardFillStrong: Color {
        colorScheme == .dark ? Color.white.opacity(0.13) : Color.white.opacity(0.62)
    }

    private var neutralChromeFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.14) : Color.black.opacity(0.08)
    }

    private var neutralStroke: Color {
        colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.11)
    }

    private var preferredColorSchemeSelection: ColorScheme? {
        switch settingsStore.settings.appAppearancePreference {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
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

    /// Top-level switch between all supported menu bar layouts.
    private var modeSwitchRow: some View {
        HStack(spacing: 10) {
            Text(String(localized: "Mode"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(neutralSecondaryText)
            Spacer()
            HStack(spacing: 6) {
                modeSwitchButton(title: String(localized: "Simple"), isActive: activeLayoutMode == .simple) {
                    setLayoutMode(.simple)
                }
                modeSwitchButton(title: String(localized: "Advanced"), isActive: activeLayoutMode == .advanced) {
                    setLayoutMode(.advanced)
                }
                modeSwitchButton(title: String(localized: "Short"), isActive: activeLayoutMode == .short) {
                    setLayoutMode(.short)
                }
            }
            .padding(4)
            .background(
                Capsule()
                    .fill(neutralChromeFill)
            )
        }
    }

    /// Segment-like button used by the menu layout mode switch row.
    private func modeSwitchButton(title: String, isActive: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isActive ? neutralPrimaryText : neutralSecondaryText)
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

    /// Cached convenience value for the current menu bar layout mode.
    private var activeLayoutMode: LayoutMode {
        layoutMode(for: settingsStore.settings)
    }

    private func layoutMode(for settings: DimlySettings) -> LayoutMode {
        switch settings.menuBarLayoutMode {
        case .simple:
            return .simple
        case .advanced:
            return .advanced
        case .short:
            return .short
        }
    }

    /// Switches layout mode while preserving expanded brightness rows when safe.
    private func setLayoutMode(_ mode: LayoutMode) {
        guard activeLayoutMode != mode else { return }
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
                switch mode {
                case .simple:
                    settings.menuBarLayoutMode = .simple
                case .advanced:
                    settings.menuBarLayoutMode = .advanced
                case .short:
                    settings.menuBarLayoutMode = .short
                }
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
                    guard layoutMode(for: settings) == mode else { return }
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
                    .foregroundStyle(neutralPrimaryText)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(neutralChromeFill))
                VStack(alignment: .leading, spacing: 2) {
                    Text(countText)
                        .font(.headline)
                        .foregroundStyle(neutralPrimaryText)
                    Text(displaySummaryText)
                        .font(.caption)
                        .foregroundStyle(neutralSecondaryText)
                }
                Spacer()
                if count > 0 {
                    statusPill
                }
            }
            extendedStatusView
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(neutralCardFillStrong)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(neutralStroke, lineWidth: 1)
        )
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
                    .foregroundStyle(neutralSecondaryText)
            )
        }
        return AnyView(
            VStack(alignment: .leading, spacing: 4) {
                ForEach(rows, id: \.self) { row in
                    Text(row)
                        .font(.caption)
                        .foregroundStyle(neutralSecondaryText)
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

    /// Profiles pinned for quick one-click apply actions under Quick Actions.
    private var smartButtonProfiles: [DisplayProfile] {
        let selected = profileManager.profiles.filter(\.showInSmartButtons)
        return Array(selected.prefix(smartButtonLimit))
    }

    /// Fast lookup of visible smart-button profiles by ID.
    private var smartButtonProfileByID: [UUID: DisplayProfile] {
        Dictionary(uniqueKeysWithValues: smartButtonProfiles.map { ($0.id, $0) })
    }

    /// Render list for the smart-button grid including a temporary spacer while dragging.
    private var smartButtonGridItems: [SmartButtonGridItem] {
        let ids = smartButtonProfiles.map(\.id)
        guard let draggedSmartButtonProfileID,
              ids.contains(draggedSmartButtonProfileID),
              let smartButtonDropTarget else {
            return ids.map { .profile($0) }
        }
        let reducedIDs = ids.filter { $0 != draggedSmartButtonProfileID }
        var items = reducedIDs.map { SmartButtonGridItem.profile($0) }
        switch smartButtonDropTarget {
        case .before(let targetID):
            guard let targetIndex = reducedIDs.firstIndex(of: targetID) else {
                return ids.map { .profile($0) }
            }
            items.insert(.spacerBefore(targetID), at: targetIndex)
        case .after(let targetID):
            guard let targetIndex = reducedIDs.firstIndex(of: targetID) else {
                return ids.map { .profile($0) }
            }
            items.insert(.spacerAfter(targetID), at: min(items.count, targetIndex + 1))
        }
        return items
    }

    /// Maximum number of smart buttons shown in the menu bar.
    private var smartButtonLimit: Int {
        max(4, min(16, settingsStore.settings.menuBarSmartButtonsLimit))
    }

    /// Grid of smart profile buttons laid out in 4 columns.
    private func smartButtonsSection(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "Smart Buttons"))
            if smartButtonProfiles.isEmpty {
                Text(String(localized: "No smart buttons yet. Save profiles in Settings and enable \"Show as smart button\"."))
                    .font(.caption)
                    .foregroundStyle(neutralSecondaryText)
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
                ZStack(alignment: .topLeading) {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                        ForEach(smartButtonGridItems) { item in
                            switch item {
                            case .profile(let profileID):
                                if let profile = smartButtonProfileByID[profileID] {
                                    smartButton(profile, compact: compact)
                                        .opacity(draggedSmartButtonProfileID == profile.id ? 0.02 : 1)
                                        .background(
                                            GeometryReader { geometry in
                                                Color.clear.preference(
                                                    key: SmartButtonFramePreferenceKey.self,
                                                    value: [profile.id: geometry.frame(in: .named(smartButtonsGridCoordinateSpace))]
                                                )
                                            }
                                        )
                                        .gesture(smartButtonReorderGesture(for: profile.id))
                                }
                            case .spacerBefore, .spacerAfter:
                                smartButtonSpacerTile(compact: compact)
                            }
                        }
                    }

                    if let draggedID = draggedSmartButtonProfileID,
                       let draggedProfile = smartButtonProfileByID[draggedID],
                       let draggedFrame = smartButtonDragStartFramesByProfileID[draggedID] {
                        floatingSmartButtonPreview(
                            draggedProfile,
                            compact: compact,
                            size: CGSize(width: draggedFrame.width, height: draggedFrame.height)
                        )
                            .allowsHitTesting(false)
                            .position(x: draggedFrame.midX, y: draggedFrame.midY)
                            .offset(smartButtonDragTranslation)
                            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.32 : 0.18), radius: 6, x: 0, y: 3)
                            .zIndex(10)
                    }
                }
                .coordinateSpace(name: smartButtonsGridCoordinateSpace)
                .onPreferenceChange(SmartButtonFramePreferenceKey.self) { frames in
                    smartButtonFramesByProfileID = frames
                }
                .animation(.spring(response: 0.16, dampingFraction: 0.9), value: smartButtonDropTarget)
                .animation(.spring(response: 0.24, dampingFraction: 0.84), value: profileManager.profiles.map(\.id))
            }
        }
    }

    /// Arc-like shortcut tile for applying a saved profile.
    private func smartButton(_ profile: DisplayProfile, compact: Bool) -> some View {
        let isColorless = settingsStore.settings.menuBarSmartButtonsColorlessMode
        let minHeight: CGFloat = compact ? 24 : 40
        let titleColor: Color = {
            if isColorless {
                return colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.64)
            }
            return Color.white.opacity(colorScheme == .dark ? 0.95 : 0.9)
        }()

        return Text(profile.name)
            .font(.system(size: compact ? 8 : 9.5, weight: .semibold))
            .lineLimit(compact ? 1 : 2)
            .minimumScaleFactor(0.72)
            .multilineTextAlignment(.center)
            .foregroundStyle(titleColor)
            .frame(maxWidth: .infinity)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.vertical, compact ? 0 : 2)
            .padding(.horizontal, compact ? 2 : 3)
            .background(
                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                    .fill(isColorless ? AnyShapeStyle(smartButtonNeutralFill) : AnyShapeStyle(smartButtonGradient(for: profile)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                    .stroke(
                        isColorless ? neutralStroke.opacity(compact ? 0.8 : 0.7) : Color.white.opacity(colorScheme == .dark ? 0.19 : 0.28),
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous))
            .onTapGesture {
                profileManager.apply(profile: profile)
            }
        .help(profile.name)
    }

    /// Fixed-size floating preview tile shown while dragging.
    private func floatingSmartButtonPreview(_ profile: DisplayProfile, compact: Bool, size: CGSize) -> some View {
        let isColorless = settingsStore.settings.menuBarSmartButtonsColorlessMode
        let titleColor: Color = {
            if isColorless {
                return colorScheme == .dark ? Color.white.opacity(0.92) : Color.black.opacity(0.64)
            }
            return Color.white.opacity(colorScheme == .dark ? 0.95 : 0.9)
        }()

        return Text(profile.name)
            .font(.system(size: compact ? 8 : 9.5, weight: .semibold))
            .lineLimit(compact ? 1 : 2)
            .minimumScaleFactor(0.72)
            .multilineTextAlignment(.center)
            .foregroundStyle(titleColor)
            .frame(width: max(24, size.width), height: max(24, size.height))
            .background(
                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                    .fill(isColorless ? AnyShapeStyle(smartButtonNeutralFill) : AnyShapeStyle(smartButtonGradient(for: profile)))
            )
            .overlay(
                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                    .stroke(
                        isColorless ? neutralStroke.opacity(compact ? 0.8 : 0.7) : Color.white.opacity(colorScheme == .dark ? 0.19 : 0.28),
                        lineWidth: 1
                    )
            )
    }

    /// Placeholder tile shown at the potential drop location while dragging.
    private func smartButtonSpacerTile(compact: Bool) -> some View {
        let minHeight: CGFloat = compact ? 24 : 40
        let cornerRadius: CGFloat = compact ? 10 : 12
        return RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(neutralChromeFill.opacity(0.38))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(neutralStroke.opacity(0.96), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            )
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .padding(.vertical, compact ? 0 : 2)
            .padding(.horizontal, compact ? 2 : 3)
    }

    /// Drag gesture used to preview and then commit smart-button reordering.
    private func smartButtonReorderGesture(for profileID: UUID) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named(smartButtonsGridCoordinateSpace))
            .onChanged { value in
                if draggedSmartButtonProfileID != profileID {
                    draggedSmartButtonProfileID = profileID
                    smartButtonDragStartFramesByProfileID = smartButtonFramesByProfileID
                    smartButtonDropTarget = nil
                }
                smartButtonDragTranslation = value.translation
                guard let draggedID = draggedSmartButtonProfileID else { return }
                smartButtonDropTarget = smartButtonDropTarget(for: value.translation, draggedID: draggedID)
            }
            .onEnded { _ in
                applySmartButtonDropIfNeeded()
                draggedSmartButtonProfileID = nil
                smartButtonDragStartFramesByProfileID.removeAll()
                smartButtonDragTranslation = .zero
                smartButtonDropTarget = nil
            }
    }

    /// Commits any pending smart-button drop target to the persisted profile order.
    private func applySmartButtonDropIfNeeded() {
        guard let draggedID = draggedSmartButtonProfileID,
              let smartButtonDropTarget else { return }
        withAnimation(.spring(response: 0.24, dampingFraction: 0.84)) {
            switch smartButtonDropTarget {
            case .before(let targetID):
                profileManager.moveProfile(draggedID, before: targetID)
            case .after(let targetID):
                profileManager.moveProfile(draggedID, after: targetID)
            }
        }
    }

    /// Resolves drop target by fitting the dragged tile rect into virtual grid insertion slots.
    private func smartButtonDropTarget(for translation: CGSize, draggedID: UUID) -> SmartButtonDropTarget? {
        let startFrames = smartButtonDragStartFramesByProfileID.isEmpty ? smartButtonFramesByProfileID : smartButtonDragStartFramesByProfileID
        guard let draggedFrame = startFrames[draggedID] else { return nil }
        if abs(translation.width) < 5 && abs(translation.height) < 5 {
            return nil
        }

        let orderedIDs = smartButtonProfiles.map(\.id)
        guard let fromIndex = orderedIDs.firstIndex(of: draggedID) else { return nil }
        let reducedIDs = orderedIDs.filter { $0 != draggedID }
        guard reducedIDs.isEmpty == false else { return nil }

        let dragRect = draggedFrame.offsetBy(dx: translation.width, dy: translation.height)
        // Keep a generous cancel zone around the original tile location so dropping
        // back in place is easy and predictable.
        let cancelPadding = max(draggedFrame.width, draggedFrame.height) * 0.45
        if draggedFrame.insetBy(dx: -cancelPadding, dy: -cancelPadding).contains(dragRect.center) {
            return nil
        }

        guard let fit = bestSmartButtonInsertionFit(for: dragRect, reducedIDs: reducedIDs) else {
            return nil
        }

        let maxDistance = max(fit.stepX, fit.stepY) * 1.75
        guard fit.distance <= maxDistance else {
            return nil
        }

        if fit.insertionIndex == fromIndex {
            return nil
        }
        if fit.insertionIndex >= reducedIDs.count, let lastID = reducedIDs.last {
            return .after(lastID)
        }
        return .before(reducedIDs[fit.insertionIndex])
    }

    /// Picks the insertion slot where the dragged tile physically fits best.
    private func bestSmartButtonInsertionFit(
        for dragRect: CGRect,
        reducedIDs: [UUID]
    ) -> (insertionIndex: Int, distance: CGFloat, stepX: CGFloat, stepY: CGFloat)? {
        let liveFrames = smartButtonFramesByProfileID
        let startFrames = smartButtonDragStartFramesByProfileID
        let reducedFrames: [CGRect] = reducedIDs.compactMap { id in
            liveFrames[id] ?? startFrames[id]
        }
        guard reducedFrames.count == reducedIDs.count else { return nil }

        let columns = 4
        let width = reducedFrames.map(\.width).median ?? 36
        let height = reducedFrames.map(\.height).median ?? 28
        let stepX = inferredStepX(from: reducedFrames, fallback: width + 8)
        let stepY = inferredStepY(from: reducedFrames, columns: columns, fallback: height + 8)

        let rowBreakTolerance = max(4, height * 0.22)
        let slotRects = smartButtonInsertionSlotRects(
            frames: reducedFrames,
            slotSize: CGSize(width: width, height: height),
            rowBreakTolerance: rowBreakTolerance
        )

        var bestIndex = 0
        var bestOverlap: CGFloat = -1
        var bestDistance = CGFloat.greatestFiniteMagnitude
        let dragCenter = dragRect.center

        for slot in slotRects {
            let slotCenter = slot.rect.center
            let slotRect = slot.rect
            let overlap = dragRect.intersection(slotRect).area
            let distance = dragCenter.distanceSquared(to: slotCenter).squareRoot()
            if overlap > bestOverlap + 0.5 || (abs(overlap - bestOverlap) <= 0.5 && distance < bestDistance) {
                bestOverlap = overlap
                bestDistance = distance
                bestIndex = slot.insertionIndex
            }
        }

        return (bestIndex, bestDistance, stepX, stepY)
    }

    private func smartButtonInsertionSlotRects(
        frames: [CGRect],
        slotSize: CGSize,
        rowBreakTolerance: CGFloat
    ) -> [(insertionIndex: Int, rect: CGRect)] {
        guard frames.isEmpty == false else { return [] }
        var slots: [(insertionIndex: Int, rect: CGRect)] = []

        for insertionIndex in 0...frames.count {
            if insertionIndex == 0 {
                let next = frames[0]
                let center = CGPoint(x: next.minX - (slotSize.width * 0.5), y: next.midY)
                slots.append((insertionIndex, CGRect(center: center, size: slotSize)))
                continue
            }

            if insertionIndex == frames.count {
                let previous = frames[insertionIndex - 1]
                let center = CGPoint(x: previous.maxX + (slotSize.width * 0.5), y: previous.midY)
                slots.append((insertionIndex, CGRect(center: center, size: slotSize)))
                continue
            }

            let previous = frames[insertionIndex - 1]
            let next = frames[insertionIndex]
            let sameRow = abs(previous.midY - next.midY) <= rowBreakTolerance
            if sameRow {
                let center = CGPoint(
                    x: (previous.maxX + next.minX) * 0.5,
                    y: (previous.midY + next.midY) * 0.5
                )
                slots.append((insertionIndex, CGRect(center: center, size: slotSize)))
            } else {
                // For row breaks, keep both candidates for the same insertion index:
                // end of previous row and start of next row.
                let endPreviousRow = CGPoint(x: previous.maxX + (slotSize.width * 0.5), y: previous.midY)
                let startNextRow = CGPoint(x: next.minX - (slotSize.width * 0.5), y: next.midY)
                slots.append((insertionIndex, CGRect(center: endPreviousRow, size: slotSize)))
                slots.append((insertionIndex, CGRect(center: startNextRow, size: slotSize)))
            }
        }

        return slots
    }

    private func inferredStepX(from frames: [CGRect], fallback: CGFloat) -> CGFloat {
        let centers = frames.map { $0.center.x }.sorted()
        let diffs = zip(centers, centers.dropFirst()).map { $1 - $0 }.filter { $0 > 2 }
        return diffs.median ?? fallback
    }

    private func inferredStepY(from frames: [CGRect], columns: Int, fallback: CGFloat) -> CGFloat {
        guard frames.count > columns else { return fallback }
        let centers = frames.map { $0.center.y }.sorted()
        let diffs = zip(centers, centers.dropFirst()).map { $1 - $0 }.filter { $0 > 2 }
        return diffs.median ?? fallback
    }

    private var smartButtonNeutralFill: Color {
        colorScheme == .dark ? Color.white.opacity(0.1) : Color.black.opacity(0.06)
    }

    /// Resolved gradient used by smart buttons (manual preset or deterministic auto).
    private func smartButtonGradient(for profile: DisplayProfile) -> LinearGradient {
        let preset = profile.smartButtonColorPreset ?? autoSmartButtonColorPreset(for: profile)
        let colors = smartButtonGradientColors(for: preset)
        let opacity: Double = colorScheme == .dark ? 0.75 : 0.93
        return LinearGradient(
            colors: [colors.0.opacity(opacity), colors.1.opacity(opacity)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Chooses a stable auto color preset from profile metadata.
    private func autoSmartButtonColorPreset(for profile: DisplayProfile) -> SmartButtonColorPreset {
        let seed = "\(profile.id.uuidString.lowercased())|\(profile.name.lowercased())"
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        let presets = SmartButtonColorPreset.allCases
        let index = Int(hash % UInt64(presets.count))
        return presets[index]
    }

    /// Defines gradient color pairs for each curated smart button preset.
    private func smartButtonGradientColors(for preset: SmartButtonColorPreset) -> (Color, Color) {
        switch preset {
        case .sunset:
            return (Color(red: 0.95, green: 0.45, blue: 0.12), Color(red: 0.85, green: 0.18, blue: 0.48))
        case .ocean:
            return (Color(red: 0.07, green: 0.65, blue: 0.92), Color(red: 0.14, green: 0.39, blue: 0.89))
        case .mint:
            return (Color(red: 0.06, green: 0.73, blue: 0.52), Color(red: 0.05, green: 0.63, blue: 0.75))
        case .violet:
            return (Color(red: 0.55, green: 0.37, blue: 0.96), Color(red: 0.39, green: 0.40, blue: 0.95))
        case .amber:
            return (Color(red: 0.96, green: 0.62, blue: 0.06), Color(red: 0.92, green: 0.27, blue: 0.20))
        case .rose:
            return (Color(red: 0.93, green: 0.29, blue: 0.60), Color(red: 0.91, green: 0.25, blue: 0.45))
        case .lime:
            return (Color(red: 0.49, green: 0.77, blue: 0.14), Color(red: 0.10, green: 0.64, blue: 0.36))
        case .slate:
            return (Color(red: 0.40, green: 0.47, blue: 0.56), Color(red: 0.20, green: 0.26, blue: 0.33))
        case .teal:
            return (Color(red: 0.05, green: 0.66, blue: 0.63), Color(red: 0.08, green: 0.48, blue: 0.55))
        case .indigo:
            return (Color(red: 0.35, green: 0.40, blue: 0.94), Color(red: 0.22, green: 0.27, blue: 0.78))
        case .coral:
            return (Color(red: 0.96, green: 0.47, blue: 0.39), Color(red: 0.89, green: 0.29, blue: 0.34))
        case .copper:
            return (Color(red: 0.79, green: 0.47, blue: 0.24), Color(red: 0.56, green: 0.32, blue: 0.18))
        case .emerald:
            return (Color(red: 0.07, green: 0.71, blue: 0.41), Color(red: 0.04, green: 0.50, blue: 0.30))
        case .sky:
            return (Color(red: 0.35, green: 0.76, blue: 0.98), Color(red: 0.20, green: 0.55, blue: 0.93))
        case .magenta:
            return (Color(red: 0.86, green: 0.29, blue: 0.86), Color(red: 0.63, green: 0.21, blue: 0.79))
        case .gold:
            return (Color(red: 0.95, green: 0.76, blue: 0.20), Color(red: 0.86, green: 0.58, blue: 0.08))
        }
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
        let rowShape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let isExpanded = isBrightnessPanelExpanded(for: display)

        return VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            displayRowHeader(display, includeMenu: includeMenu, isExpanded: isExpanded)
            if isExpanded {
                brightnessDropdown(for: display)
            }
        }
        .padding(8)
        .background(neutralCardFill)
        .overlay(
            rowShape
                .stroke(neutralStroke.opacity(0.78), lineWidth: 1)
        )
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
                        .foregroundStyle(neutralPrimaryText)
                    Image(systemName: isExpanded ? "chevron.down.circle.fill" : "chevron.right.circle")
                        .font(.caption)
                        .foregroundStyle(neutralTertiaryText)
                    if !isExpanded {
                        Text(brightnessText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(neutralSecondaryText)
                    }
                }
                HStack(spacing: 6) {
                    Text(String(format: String(localized: "DisplayRowStatusFormat"), display.resolution, ddcState, status))
                        .font(.caption)
                        .foregroundStyle(neutralSecondaryText)
                    Text(marker)
                        .font(.caption2)
                        .foregroundStyle(neutralTertiaryText)
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
                            .foregroundStyle(neutralSecondaryText)
                            .frame(width: 26, height: 26)
                            .background(
                                Circle()
                                    .fill(neutralChromeFill)
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
                    .foregroundStyle(neutralSecondaryText)
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
                .foregroundStyle(neutralSecondaryText)
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
                .foregroundStyle(neutralSecondaryText)
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
        .foregroundStyle(neutralSecondaryText)
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

    /// Minimal app actions shown in short mode.
    private var shortModeAppActionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(String(localized: "App"))
            HStack(spacing: 8) {
                Button(role: .destructive) {
                    NSApp.terminate(nil)
                } label: {
                    Label(String(localized: "Quit Dimly"), systemImage: "power")
                }
                .overlay(alignment: .topTrailing) {
                    shortModeUpdatesBadge
                        .offset(x: 7, y: -7)
                }
                Spacer(minLength: 0)
                applyProfileMenuButton()
                    .overlay(alignment: .topTrailing) {
                        shortModeSettingsBadge
                            .offset(x: 7, y: -7)
                    }
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    /// Tiny settings launcher shown as an overlay badge in short mode.
    private var shortModeSettingsBadge: some View {
        SettingsLink {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(neutralSecondaryText)
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(neutralChromeFill.opacity(0.94))
                )
                .overlay(
                    Circle()
                        .stroke(neutralStroke.opacity(0.9), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .help(String(localized: "Settings..."))
    }

    /// Tiny update-check launcher shown as an overlay badge in short mode.
    private var shortModeUpdatesBadge: some View {
        Button {
            updaterController.checkForUpdates(nil)
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(neutralSecondaryText)
                .frame(width: 16, height: 16)
                .background(
                    Circle()
                        .fill(neutralChromeFill.opacity(0.94))
                )
                .overlay(
                    Circle()
                        .stroke(neutralStroke.opacity(0.9), lineWidth: 0.8)
                )
        }
        .buttonStyle(.plain)
        .help(String(localized: "Check for Updates..."))
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
            .foregroundStyle(neutralSecondaryText)
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

    /// Applies user visibility rules to decide whether a display appears in Dimly lists.
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

    /// Captures smart button frame rectangles for drag hit-testing.
    private struct SmartButtonFramePreferenceKey: PreferenceKey {
        static let defaultValue: [UUID: CGRect] = [:]

        static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
            value.merge(nextValue()) { _, new in new }
        }
    }
}

private extension CGRect {
    init(center: CGPoint, size: CGSize) {
        self.init(
            x: center.x - (size.width * 0.5),
            y: center.y - (size.height * 0.5),
            width: size.width,
            height: size.height
        )
    }

    var center: CGPoint {
        CGPoint(x: midX, y: midY)
    }

    var area: CGFloat {
        guard isNull == false, isInfinite == false else { return 0 }
        return max(0, width) * max(0, height)
    }
}

private extension CGPoint {
    func offsetBy(dx: CGFloat, dy: CGFloat) -> CGPoint {
        CGPoint(x: x + dx, y: y + dy)
    }

    func distanceSquared(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx) + (dy * dy)
    }
}

private extension Array where Element == CGFloat {
    var median: CGFloat? {
        guard isEmpty == false else { return nil }
        let sorted = self.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) * 0.5
        }
        return sorted[mid]
    }
}

/// Button style that keeps icon colors stable during pressed state (no accent flash).
private struct StaticIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}
