// MARK: - Settings Window
// Sidebar-based SwiftUI surface for global preferences, shortcuts, profiles, and about info.
import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Settings window root with sidebar navigation.
struct SettingsRootView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var profileManager: ProfileManager
    @ObservedObject var ddcManager: DDCManager
    @ObservedObject var blackoutManager: BlackoutManager
    @ObservedObject var engine: DimlyEngine
    @ObservedObject var scheduleManager: ScheduleManager
    @State private var introWindowController: IntroWindowController?
    @State private var selection: SettingsDestination = .general
    @State private var proposedProfileName: String = ""

    enum SettingsDestination: Hashable {
        case general
        case displays
        case visuals
        case shortcuts
        case profiles
        case schedule
        case about
    }

    /// Settings UI with sidebar navigation.
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                Section(String(localized: "AppName")) {
                    Label(String(localized: "SettingsTabGeneralLabel"), systemImage: "gearshape")
                        .tag(SettingsDestination.general)
                    Label(String(localized: "SettingsTabDisplaysLabel"), systemImage: "display")
                        .tag(SettingsDestination.displays)
                    Label(String(localized: "SettingsTabVisualsLabel"), systemImage: "paintbrush")
                        .tag(SettingsDestination.visuals)
                    Label(String(localized: "SettingsTabShortcutsLabel"), systemImage: "keyboard")
                        .tag(SettingsDestination.shortcuts)
                    Label(String(localized: "ProfilesSectionTitle"), systemImage: "rectangle.3.group")
                        .tag(SettingsDestination.profiles)
                    Label(String(localized: "ScheduleTabLabel"), systemImage: "clock")
                        .tag(SettingsDestination.schedule)
                    Label(String(localized: "SettingsTabAboutLabel"), systemImage: "info.circle")
                        .tag(SettingsDestination.about)
                }
            }
            .listStyle(.sidebar)
            .frame(minWidth: 210)
        } detail: {
            SettingsDetailView(
                selection: selection,
                settingsStore: settingsStore,
                displayManager: displayManager,
                profileManager: profileManager,
                ddcManager: ddcManager,
                engine: engine,
                scheduleManager: scheduleManager,
                proposedProfileName: $proposedProfileName,
                renameProfile: renameProfile,
                showIntroAgain: showIntroAgain,
                displayRow: { display in AnyView(displayRowView(for: display)) }
            )
        }
        .frame(minWidth: 900, minHeight: 580)
        .hideSettingsToolbar()
        .onAppear {
            engine.refreshBuiltinBrightnessSnapshots(reason: "settingsAppear", persistToSettings: false)
        }
        .preferredColorScheme(settingsStore.effectiveColorScheme)
    }

    /// Forces the intro window to reappear for the current session.
    private func showIntroAgain() {
        UserDefaults.standard.set(false, forKey: AppDelegate.introShownKey)
        if introWindowController == nil {
            introWindowController = IntroWindowController {
                introWindowController = nil
            }
        }
        introWindowController?.showWindow(nil)
        introWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Prompts the user to rename an existing profile.
    private func renameProfile(_ profile: DisplayProfile) {
        let alert = NSAlert()
        alert.messageText = String(localized: "RenameProfileAlertTitle")
        alert.informativeText = String(localized: "RenameProfileAlertSubtitle")
        alert.addButton(withTitle: String(localized: "ActionSaveButton"))
        alert.addButton(withTitle: String(localized: "ActionCancelButton"))
        let input = NSTextField(string: profile.name)
        input.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = input
        let response = AlertPresentation.runModalOnCursorScreen(alert)
        if response == .alertFirstButtonReturn {
            profileManager.rename(profile: profile, to: input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    /// Resolves display names using the shared label resolver.
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

    /// Computes the human-friendly status text for a display.
    private func displayStatus(for display: DisplayInfo) -> String {
        if blackoutManager.activeDisplayIDs.contains(display.stableIdentity) {
            return String(localized: "DisplayStatusBlackoutLabel")
        }
        if settingsStore.settings.overlayOnlyDisplayIDs.contains(display.stableIdentity) == false,
           engine.ddcManager.states[display.stableIdentity]?.lastCommand == .standby {
            return String(localized: "DisplayStatusSleepLabel")
        }
        return String(localized: "DisplayStatusVisibleLabel")
    }

    /// External display numbering map used for labels and markers.
    private var externalIndexMap: [String: Int] {
        indexMap(for: displayManager.displays.filter { $0.isExternal })
    }

    /// Internal display numbering map used for labels and markers.
    private var internalIndexMap: [String: Int] {
        indexMap(for: displayManager.displays.filter { $0.isBuiltin })
    }

    /// Number of built-in panels currently visible to the app.
    private var internalDisplayCount: Int {
        displayManager.displays.filter { $0.isBuiltin }.count
    }

    /// Generates a consistent index map for display numbering.
    private func indexMap(for displays: [DisplayInfo]) -> [String: Int] {
        let ordered = displays.sorted { $0.displayID < $1.displayID }
        var mapping: [String: Int] = [:]
        for (index, display) in ordered.enumerated() {
            mapping[display.stableIdentity] = index + 1
        }
        return mapping
    }

    /// Prompts to rename a display and persists the alias in settings.
    private func renameDisplay(_ display: DisplayInfo, currentName: String) {
        let alert = NSAlert()
        alert.messageText = String(localized: "RenameDisplayAlertTitle")
        alert.informativeText = String(localized: "RenameDisplayAlertSubtitle")
        alert.addButton(withTitle: String(localized: "ActionSaveButton"))
        alert.addButton(withTitle: String(localized: "ActionCancelButton"))
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

    /// Renders a detailed row for a single display in Settings.
    @ViewBuilder
    private func displayRowView(for display: DisplayInfo) -> some View {
        let name = displayName(for: display)
        let status = displayStatus(for: display)
        let typeLabel = display.isBuiltin ? String(localized: "DisplayTypeInternalLabel") : String(localized: "DisplayTypeExternalLabel")
        let state = ddcManager.states[display.stableIdentity] ?? DDCState(status: .unknown, lastError: nil, lastCommand: nil, lastCommandAt: nil)
        let ddcSupported = state.status == .supported
        let overlayOnly = settingsStore.settings.overlayOnlyDisplayIDs.contains(display.stableIdentity)
        let fallbackActive = (!ddcSupported || overlayOnly) && blackoutManager.activeDisplayIDs.contains(display.stableIdentity)
        let controlTint: Color = (ddcSupported && !overlayOnly) ? .green : (fallbackActive ? .blue : .secondary)
        let canControl = display.isExternal
        let brightnessMode = engine.brightnessMode(for: display)
        let brightnessPresentation: (Color, String) = {
            switch brightnessMode {
            case .ddc:
                return (.green, String(localized: "DDC"))
            case .fallback:
                return (.blue, String(localized: "DisplayModeOverlayLabel"))
            case .checking:
                return (.orange, String(localized: "DDCCheckingLabel"))
            }
        }()
        let brightnessTint = brightnessPresentation.0
        let brightnessModeLabel = brightnessPresentation.1
        let isShownInDimly: Bool = {
            if display.isBuiltin {
                return settingsStore.settings.menuBarIncludedInternalDisplayIDs.contains(display.stableIdentity)
            }
            return settingsStore.settings.menuBarExcludedDisplayIDs.contains(display.stableIdentity) == false
        }()
        let currentBrightness = brightnessPercent(for: display)

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                SettingsIcon(systemName: display.isBuiltin ? "laptopcomputer" : "display")
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.callout.weight(.semibold))
                        Text(String(format: String(localized: "DisplayTypeResolutionFormat"), typeLabel, display.resolution))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(String(localized: "ActionRenameLabel")) {
                        renameDisplay(display, currentName: name)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

            }

            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    Label(
                        String(format: String(localized: "DDCStatusFormat"), state.status.localizedDescription),
                        systemImage: state.status == .supported ? "antenna.radiowaves.left.and.right" : "nosign"
                    )
                    .font(.caption)
                    .foregroundStyle(state.status == .supported ? .green : .secondary)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let hz = display.refreshRateHz {
                        Text(String(format: String(localized: "RefreshRateFormat"), hz))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack(spacing: 8) {
                    Label(
                        String(format: String(localized: "DDCStatusFormat"), state.status.localizedDescription),
                        systemImage: state.status == .supported ? "antenna.radiowaves.left.and.right" : "nosign"
                    )
                    .font(.caption)
                    .foregroundStyle(state.status == .supported ? .green : .secondary)
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let error = state.lastError {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            if let uuid = display.uuid {
                Text(String(format: String(localized: "DisplayIDFormat"), uuid))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else if let serial = display.serialNumber {
                Text(String(format: String(localized: "DisplaySerialFormat"), String(serial)))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 8) {
                Button(String(localized: "ActionStandbyButton")) { engine.standby(display: display) }
                    .tint(controlTint)
                    .disabled(!canControl)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Button(String(localized: "ActionWakeButton")) { engine.wake(display: display) }
                    .tint(controlTint)
                    .disabled(!canControl)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                Spacer()
            }

            if display.isExternal || display.isBuiltin {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Label(String(localized: "BrightnessSectionLabel"), systemImage: "sun.max.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(brightnessTint)
                        Spacer()
                        Text(
                            String.localizedStringWithFormat(
                                String(localized: "BrightnessPercentFormat"),
                                Int64(currentBrightness)
                            )
                        )
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        if display.isExternal {
                            Text(brightnessModeLabel)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(brightnessTint.opacity(0.18))
                                .foregroundStyle(brightnessTint)
                                .clipShape(Capsule())
                        }
                    }

                    HStack(spacing: 8) {
                        Button {
                            nudgeBrightness(for: display, delta: -1)
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(FluentPressButtonStyle(pressedScale: 0.84, pressedOpacity: 0.82))
                        .foregroundStyle(.secondary)
                        .help(String(localized: "ActionDecreaseBrightnessHint"))

                        Slider(
                            value: Binding(
                                get: { Double(brightnessPercent(for: display)) },
                                set: { newValue in
                                    setBrightness(Int(newValue.rounded()), for: display)
                                }
                            ),
                            in: 0...100
                        )
                        .tint(brightnessTint)

                        Button {
                            nudgeBrightness(for: display, delta: 1)
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 18, height: 18)
                        }
                        .buttonStyle(FluentPressButtonStyle(pressedScale: 0.84, pressedOpacity: 0.82))
                        .foregroundStyle(.secondary)
                        .help(String(localized: "ActionIncreaseBrightnessHint"))
                    }
                }
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(brightnessTint.opacity(0.09))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(brightnessTint.opacity(0.28), lineWidth: 1)
                )

                if display.isExternal {
                    Divider()

                    HStack(spacing: 10) {
                        Text(String(localized: "DisplayOverlayOnlyLabel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Toggle("", isOn: Binding(
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
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.large)
                    }
                }

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "DisplayShowInDimlyTitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "DisplayShowInDimlySubtitle"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { isShownInDimly },
                        set: { enabled in
                            settingsStore.update { settings in
                                if display.isBuiltin {
                                    if enabled {
                                        if settings.menuBarIncludedInternalDisplayIDs.contains(display.stableIdentity) == false {
                                            settings.menuBarIncludedInternalDisplayIDs.append(display.stableIdentity)
                                        }
                                    } else {
                                        settings.menuBarIncludedInternalDisplayIDs.removeAll { $0 == display.stableIdentity }
                                    }
                                } else {
                                    if enabled {
                                        settings.menuBarExcludedDisplayIDs.removeAll { $0 == display.stableIdentity }
                                    } else if settings.menuBarExcludedDisplayIDs.contains(display.stableIdentity) == false {
                                        settings.menuBarExcludedDisplayIDs.append(display.stableIdentity)
                                    }
                                }
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.primary.opacity(0.13), lineWidth: 1)
        )
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
        engine.brightnessPercent(for: display)
    }

    /// Applies display brightness to the right backend for this display type.
    private func setBrightness(_ percent: Int, for display: DisplayInfo) {
        let clamped = max(0, min(100, percent))
        engine.setBrightness(clamped, for: display, source: .slider)
    }

    // MARK: - Detail Views

    private struct SettingsDetailView: View {
        let selection: SettingsDestination
        @ObservedObject var settingsStore: AppSettingsStore
        @ObservedObject var displayManager: DisplayManager
        @ObservedObject var profileManager: ProfileManager
        @ObservedObject var ddcManager: DDCManager
        let engine: DimlyEngine
        @ObservedObject var scheduleManager: ScheduleManager
        @Binding var proposedProfileName: String
        let renameProfile: (DisplayProfile) -> Void
        let showIntroAgain: () -> Void
        let displayRow: (DisplayInfo) -> AnyView
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var includeGeneralSettings = true
        @State private var includeMonitorSettings = true
        @State private var showManualEntry = false
        @State private var manualLatText = ""
        @State private var manualLonText = ""
        @State private var manualEntryError: String? = nil
        @State private var draggedProfileID: UUID?
        @State private var profileSwapTargetID: UUID?
        @State private var profileFramesByID: [UUID: CGRect] = [:]
        @State private var profileDragStartFramesByID: [UUID: CGRect] = [:]
        @State private var profileDragTranslation: CGSize = .zero
        private let profileGridCoordinateSpace = "settings-profiles-grid-coordinate-space"

        private var reorderAnimation: Animation? {
            reduceMotion ? nil : DimlyMotion.reorderSpring
        }

        /// Runs animated state changes unless Reduce Motion is enabled.
        private func runMotion(_ animation: Animation, updates: @escaping () -> Void) {
            if reduceMotion {
                updates()
            } else {
                withAnimation(animation, updates)
            }
        }

        var body: some View {
            switch selection {
            case .general:
                generalDetail
            case .displays:
                displaysDetail
            case .visuals:
                visualsDetail
            case .shortcuts:
                shortcutsDetail
            case .profiles:
                profilesDetail
            case .schedule:
                scheduleDetail
            case .about:
                aboutDetail
            }
        }

        private var generalDetail: some View {
            SettingsScrollView(title: String(localized: "SettingsSectionTitle"), subtitle: nil, contentMaxWidth: 980) {
                SettingsCard(title: String(localized: "SettingsTabGeneralLabel"), subtitle: nil) {
                    SettingsToggleRow(
                        title: String(localized: "GeneralAutostartTitle"),
                        subtitle: String(localized: "GeneralAutostartSubtitle"),
                        systemImage: "power.circle",
                        isOn: Binding(
                            get: { settingsStore.settings.launchAtLogin },
                            set: { newValue in settingsStore.update { $0.launchAtLogin = newValue } }
                        )
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: String(localized: "GeneralMenuBarIconTitle"),
                        subtitle: nil,
                        systemImage: "menubar.rectangle",
                        isOn: Binding(
                            get: { settingsStore.settings.showMenuBarIcon },
                            set: { newValue in settingsStore.update { $0.showMenuBarIcon = newValue } }
                        )
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: String(localized: "GeneralHideDockIconTitle"),
                        subtitle: nil,
                        systemImage: "dock.rectangle",
                        isOn: Binding(
                            get: { settingsStore.settings.hideDockIcon },
                            set: { newValue in settingsStore.update { $0.hideDockIcon = newValue } }
                        )
                    )
                    SettingsDivider()
                    SettingsRow(
                        title: String(localized: "GeneralQuickActionsVisibilityTitle"),
                        subtitle: String(localized: "GeneralQuickActionsVisibilitySubtitle"),
                        systemImage: "bolt.badge.clock"
                    ) {
                        Picker(
                            String(localized: "GeneralQuickActionsVisibilityTitle"),
                            selection: Binding(
                                get: { settingsStore.settings.fastActionsVisibilityMode },
                                set: { newValue in settingsStore.update { $0.fastActionsVisibilityMode = newValue } }
                            )
                        ) {
                            ForEach(DimlySettings.FastActionsVisibilityMode.allCases) { mode in
                                Text(mode.localizedTitle)
                                    .tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                    SettingsDivider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "GeneralHideDockIconNote"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "GeneralMenuBarIconHiddenNote"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    SettingsDivider()
                    Button(String(localized: "GeneralShowIntroButton")) {
                        showIntroAgain()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                SettingsCard(title: String(localized: "GeneralBackupTitle"), subtitle: String(localized: "GeneralBackupSubtitle")) {
                    HStack(alignment: .top, spacing: 10) {
                        backupSelectionTile(
                            title: String(localized: "BackupGeneralSettingsTitle"),
                            details: String(localized: "BackupGeneralRowDetails"),
                            systemImage: "gearshape.2",
                            isOn: $includeGeneralSettings
                        )
                        backupSelectionTile(
                            title: String(localized: "BackupMonitorSettingsTitle"),
                            details: String(localized: "BackupMonitorRowDetails"),
                            systemImage: "display.2",
                            isOn: $includeMonitorSettings
                        )
                    }

                    HStack(alignment: .top, spacing: 10) {
                        backupActionTile(
                            title: String(localized: "BackupImportActionTitle"),
                            systemImage: "square.and.arrow.down",
                            buttonTitle: String(localized: "ActionImportButton"),
                            disabled: selectedBackupType == nil,
                            action: importSelectedSettings
                        )
                        backupActionTile(
                            title: String(localized: "BackupExportActionTitle"),
                            systemImage: "square.and.arrow.up",
                            buttonTitle: String(localized: "ActionExportButton"),
                            disabled: selectedBackupType == nil,
                            action: exportSelectedSettings
                        )
                    }

                    if selectedBackupType == nil {
                        Text(String(localized: "BackupSelectCategoryError"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        private var displaysDetail: some View {
            SettingsScrollView(title: String(localized: "SettingsTabDisplaysLabel"), subtitle: nil) {
                SettingsCard(title: String(localized: "SettingsTabDisplaysLabel"), subtitle: nil) {
                    SettingsToggleRow(
                        title: String(localized: "DisplaysShowNumbersTitle"),
                        subtitle: nil,
                        systemImage: "number",
                        isOn: Binding(
                            get: { settingsStore.settings.showDisplayNumbers },
                            set: { newValue in settingsStore.update { $0.showDisplayNumbers = newValue } }
                        )
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: String(localized: "DisplaysMergeOrderTitle"),
                        subtitle: nil,
                        systemImage: "rectangle.3.group.bubble.left",
                        isOn: Binding(
                            get: { settingsStore.settings.mergeInternalAndExternalDisplays },
                            set: { newValue in settingsStore.update { $0.mergeInternalAndExternalDisplays = newValue } }
                        )
                    )
                    SettingsDivider()
                    Text(String(localized: "DisplaysMergeOrderTip"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SettingsDivider()
                    if displayManager.displays.isEmpty {
                        Text(String(localized: "DisplaysEmptyLabel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        let displays = displayRows()

                        ForEach(Array(displayPairs(displays).enumerated()), id: \.offset) { _, pair in
                            HStack(alignment: .top, spacing: 12) {
                                displayRow(pair[0])
                                    .frame(maxWidth: .infinity, alignment: .topLeading)

                                if pair.count == 2 {
                                    Rectangle()
                                        .fill(Color.primary.opacity(0.12))
                                        .frame(width: 1)
                                        .padding(.vertical, 10)

                                    displayRow(pair[1])
                                        .frame(maxWidth: .infinity, alignment: .topLeading)
                                } else {
                                    Spacer(minLength: 0)
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
            }
        }

        /// Groups displays into two-column rows for the settings grid.
        private func displayPairs(_ displays: [DisplayInfo]) -> [[DisplayInfo]] {
            guard displays.isEmpty == false else { return [] }
            var pairs: [[DisplayInfo]] = []
            var index = 0
            while index < displays.count {
                let next = min(index + 2, displays.count)
                pairs.append(Array(displays[index..<next]))
                index += 2
            }
            return pairs
        }

        /// Returns display ordering based on merged/separate settings preferences.
        private func displayRows() -> [DisplayInfo] {
            let allDisplays = displayManager.displays
            guard settingsStore.settings.mergeInternalAndExternalDisplays else {
                let externalDisplays = allDisplays.filter(\.isExternal)
                let internalDisplays = allDisplays.filter(\.isBuiltin)
                return externalDisplays + internalDisplays
            }

            let order = settingsStore.settings.mergedDisplayOrder
            let byID = Dictionary(uniqueKeysWithValues: allDisplays.map { ($0.stableIdentity, $0) })
            let ordered = order.compactMap { byID[$0] }
            let remaining = allDisplays.filter { order.contains($0.stableIdentity) == false }
                .sorted { $0.displayID < $1.displayID }
            return ordered + remaining
        }

        private var visualsDetail: some View {
            SettingsScrollView(title: String(localized: "SettingsTabVisualsLabel"), subtitle: nil) {
                SettingsCard(title: String(localized: "VisualsAppearanceTitle"), subtitle: nil) {
                    SettingsRow(
                        title: String(localized: "VisualsAppearanceTitle"),
                        subtitle: String(localized: "VisualsAppearanceSubtitle"),
                        systemImage: "circle.lefthalf.filled"
                    ) {
                        Picker(
                            String(localized: "VisualsAppearanceTitle"),
                            selection: Binding(
                                get: { settingsStore.settings.appAppearancePreference },
                                set: { newValue in settingsStore.update { $0.appAppearancePreference = newValue } }
                            )
                        ) {
                            ForEach(AppAppearancePreference.allCases) { preference in
                                Text(preference.localizedTitle)
                                    .tag(preference)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                }

                SettingsCard(title: String(localized: "VisualsTransitionsTitle"), subtitle: nil) {
                    SettingsRow(
                        title: String(localized: "VisualsTransitionSpeedTitle"),
                        subtitle: String(localized: "VisualsTransitionSpeedSubtitle"),
                        systemImage: "slider.horizontal.3"
                    ) {
                        transitionSpeedSlider
                    }
                    SettingsDivider()
                    SettingsToggleRow(
                        title: String(localized: "VisualsTransitionFadeOutTitle"),
                        subtitle: nil,
                        systemImage: "moon.zzz",
                        isOn: Binding(
                            get: { settingsStore.settings.fadeOutAnimationEnabled },
                            set: { newValue in settingsStore.update { $0.fadeOutAnimationEnabled = newValue } }
                        )
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: String(localized: "VisualsTransitionFadeInTitle"),
                        subtitle: nil,
                        systemImage: "sun.max",
                        isOn: Binding(
                            get: { settingsStore.settings.fadeInAnimationEnabled },
                            set: { newValue in settingsStore.update { $0.fadeInAnimationEnabled = newValue } }
                        )
                    )
                }

                SettingsCard(title: String(localized: "SmartButtonsSectionTitle"), subtitle: nil) {
                    smartButtonsConfigurationSection
                }
            }
        }

        private var transitionSpeedSlider: some View {
            let allCases = TransitionSpeed.allCases
            let speedBinding = Binding<Double>(
                get: {
                    Double(allCases.firstIndex(of: settingsStore.settings.transitionSpeed) ?? 2)
                },
                set: { newValue in
                    let index = max(0, min(allCases.count - 1, Int(newValue.rounded())))
                    settingsStore.update { $0.transitionSpeed = allCases[index] }
                }
            )
            return VStack(alignment: .leading, spacing: 4) {
                Slider(value: speedBinding, in: 0...Double(allCases.count - 1), step: 1)
                    .frame(width: 200)
                HStack(spacing: 0) {
                    ForEach(allCases) { speed in
                        Text(speed.localizedTitle)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .frame(width: 200)
            }
        }

        private var shortcutsDetail: some View {
            SettingsScrollView(title: String(localized: "SettingsTabShortcutsLabel"), subtitle: nil, contentMaxWidth: 980) {
                SettingsCard(title: String(localized: "ShortcutsGlobalTitle"), subtitle: nil) {
                    if settingsStore.settings.hotkeyBindings.isEmpty {
                        emptyHotkeysCard
                    } else {
                        ForEach(settingsStore.settings.hotkeyBindings, id: \.id) { binding in
                            HotkeyBindingRow(
                                binding: Binding(
                                    get: {
                                        settingsStore.settings.hotkeyBindings.first { $0.id == binding.id }
                                            ?? HotkeyBinding(id: binding.id, action: .toggleBlackout, target: .allExternalDisplays, descriptor: nil)
                                    },
                                    set: { updated in
                                        settingsStore.update { settings in
                                            guard let index = settings.hotkeyBindings.firstIndex(where: { $0.id == binding.id }) else { return }
                                            settings.hotkeyBindings[index] = updated
                                        }
                                    }
                                ),
                                displayOptions: displayOptions(for: binding),
                                onDelete: { settingsStore.update { settings in
                                    settings.hotkeyBindings.removeAll { $0.id == binding.id }
                                } }
                            )
                            if binding.id != settingsStore.settings.hotkeyBindings.last?.id {
                                SettingsDivider()
                            }
                        }
                    }

                    SettingsDivider()

                    Button {
                        settingsStore.update { settings in
                            settings.hotkeyBindings.append(
                                HotkeyBinding(
                                    action: .toggleBlackout,
                                    target: .allExternalDisplays,
                                    descriptor: nil
                                )
                            )
                        }
                    } label: {
                        Label(String(localized: "ActionAddHotkeyButton"), systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    SettingsDivider()

                    SettingsRow(
                        title: String(localized: "ShortcutsPanicHotkeyLabel"),
                        subtitle: nil,
                        systemImage: "bolt.fill"
                    ) {
                        Text(HotkeyDescriptor.panicDefault.displayString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        private var emptyHotkeysCard: some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(String(localized: "ShortcutsEmptyLabel"))
                    .font(.callout.weight(.semibold))
                Text(String(localized: "ShortcutsEmptyHint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        private var profileByID: [UUID: DisplayProfile] {
            Dictionary(uniqueKeysWithValues: profileManager.profiles.map { ($0.id, $0) })
        }

        /// Drag-preview order used to animate neighboring cards before the swap is committed.
        private var displayedProfiles: [DisplayProfile] {
            profileManager.profiles.swappingProfiles(draggedProfileID, with: profileSwapTargetID)
        }

        private var profilesDetail: some View {
            SettingsScrollView(title: String(localized: "ProfilesSectionTitle"), subtitle: nil, contentMaxWidth: 980) {
                SettingsCard(title: String(localized: "ProfilesSectionTitle"), subtitle: nil) {
                    HStack(alignment: .center, spacing: 8) {
                        Button(String(localized: "ActionSaveCurrentSetupButton")) {
                            profileManager.saveCurrentProfile(named: proposedProfileName)
                            proposedProfileName = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        TextField(String(localized: "ProfileNamePlaceholder"), text: $proposedProfileName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 210)
                    }

                    SettingsDivider()

                    if profileManager.profiles.isEmpty {
                        Text(String(localized: "ProfilesSettingsEmptyLabel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ZStack(alignment: .topLeading) {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(), spacing: 10),
                                    GridItem(.flexible(), spacing: 10)
                                ],
                                alignment: .leading,
                                spacing: 10
                            ) {
                                ForEach(displayedProfiles) { profile in
                                    let isDragged = draggedProfileID == profile.id
                                    let isTargeted = draggedProfileID != nil && profileSwapTargetID == profile.id
                                    profileTile(profile)
                                        .id(profile.id)
                                        .opacity(isDragged ? 0.12 : 1)
                                        .scaleEffect(isTargeted && reduceMotion == false ? 1.016 : 1)
                                        .offset(y: isTargeted && reduceMotion == false ? -2 : 0)
                                        .background(
                                            GeometryReader { geometry in
                                                Color.clear.preference(
                                                    key: ProfileTileFramePreferenceKey.self,
                                                    value: [profile.id: geometry.frame(in: .named(profileGridCoordinateSpace))]
                                                )
                                            }
                                        )
                                        .simultaneousGesture(profileReorderGesture(for: profile.id))
                                }
                            }
                            if let draggedID = draggedProfileID,
                               let draggedProfile = profileByID[draggedID],
                               let draggedFrame = profileDragStartFramesByID[draggedID] ?? profileFramesByID[draggedID] {
                                floatingProfilePreview(draggedProfile, size: draggedFrame.size)
                                    .allowsHitTesting(false)
                                    .position(x: draggedFrame.midX, y: draggedFrame.midY)
                                    .offset(profileDragTranslation)
                                    .scaleEffect(reduceMotion ? 1 : 1.018)
                                    .rotationEffect(.degrees(profilePreviewTilt))
                                    .shadow(color: Color.black.opacity(0.2), radius: 14, x: 0, y: 8)
                                    .zIndex(12)
                            }
                        }
                        .coordinateSpace(name: profileGridCoordinateSpace)
                        .onPreferenceChange(ProfileTileFramePreferenceKey.self) { frames in
                            profileFramesByID = frames
                        }
                        .animation(reorderAnimation, value: profileSwapTargetID)
                        .animation(reorderAnimation, value: displayedProfiles.map(\.id))
                        .animation(reorderAnimation, value: draggedProfileID)
                        Text(String(localized: "ProfileReorderTip"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    SettingsDivider()
                    automationSection
                }
            }
        }

        /// Interactive card used in the profile grid (apply, reorder, visibility controls).
        private func profileTile(_ profile: DisplayProfile) -> some View {
            let index = profileManager.profiles.firstIndex(where: { $0.id == profile.id }) ?? 0
            let canMoveUp = index > 0
            let canMoveDown = index < (profileManager.profiles.count - 1)
            let enabledArrowColor = Color.secondary
            let disabledArrowColor = Color.secondary.opacity(0.45)

            return VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                        Text(profile.createdAt, style: .date)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 6)
                    VStack(spacing: 3) {
                        Button {
                            runMotion(DimlyMotion.standardSpring) {
                                profileManager.moveProfileUp(profile)
                            }
                        } label: {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 16, height: 11)
                        }
                        .buttonStyle(FluentPressButtonStyle(pressedScale: 0.84, pressedOpacity: 0.82))
                        .foregroundStyle(canMoveUp ? enabledArrowColor : disabledArrowColor)
                        .opacity(canMoveUp ? 1 : 0.5)
                        .disabled(!canMoveUp)

                        Button {
                            runMotion(DimlyMotion.standardSpring) {
                                profileManager.moveProfileDown(profile)
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9, weight: .semibold))
                                .frame(width: 16, height: 11)
                        }
                        .buttonStyle(FluentPressButtonStyle(pressedScale: 0.84, pressedOpacity: 0.82))
                        .foregroundStyle(canMoveDown ? enabledArrowColor : disabledArrowColor)
                        .opacity(canMoveDown ? 1 : 0.5)
                        .disabled(!canMoveDown)
                    }
                }
                Text(String(format: String(localized: "ProfileDisplayCountFormat"), Int64(profile.displays.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(isOn: Binding(
                    get: { profile.showInSmartButtons },
                    set: { newValue in
                        profileManager.setSmartButtonVisibility(for: profile, isVisible: newValue)
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(localized: "ProfileSmartButtonToggleTitle"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "ProfileSmartButtonToggleSubtitle"))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)

                HStack(spacing: 8) {
                    Text(String(localized: "SmartButtonColorPickerLabel"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Picker(
                        String(localized: "SmartButtonColorPickerLabel"),
                        selection: Binding<SmartButtonColorPreset?>(
                            get: { profile.smartButtonColorPreset },
                            set: { newValue in
                                profileManager.setSmartButtonColorPreset(for: profile, preset: newValue)
                            }
                        )
                    ) {
                        Text(String(localized: "SmartButtonColorAutoLabel")).tag(Optional<SmartButtonColorPreset>.none)
                        ForEach(SmartButtonColorPreset.allCases) { preset in
                            Text(preset.localizedTitle).tag(Optional(preset))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 128)
                    .controlSize(.small)
                }
                .disabled(!profile.showInSmartButtons)
                .opacity(profile.showInSmartButtons ? 1 : 0.58)

                HStack(spacing: 6) {
                    Button(String(localized: "ActionApplyButton")) { profileManager.apply(profile: profile) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    Button(String(localized: "ActionRenameLabel")) {
                        renameProfile(profile)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button(String(localized: "ActionOverwriteButton")) {
                        confirmAndOverwriteProfile(profile)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Spacer(minLength: 0)
                    Button(role: .destructive, action: { profileManager.delete(profile: profile) }) {
                        Text(String(localized: "ActionDeleteButton"))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.1), lineWidth: 1)
            )
        }

        /// Confirms profile overwrite before replacing saved values with current settings.
        private func confirmAndOverwriteProfile(_ profile: DisplayProfile) {
            let alert = NSAlert()
            alert.messageText = String(localized: "ActionOverwriteProfileMenuLabel")
            alert.informativeText = profile.name
            alert.addButton(withTitle: String(localized: "ActionOverwriteButton"))
            alert.addButton(withTitle: String(localized: "ActionCancelButton"))
            if AlertPresentation.runModalOnCursorScreen(alert) == .alertFirstButtonReturn {
                profileManager.overwriteProfileWithCurrentSettings(profile)
            }
        }

        private var smartButtonsConfigurationSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                SettingsRow(
                    title: String(localized: "SmartButtonsToggleTitle"),
                    subtitle: String(localized: "SmartButtonsSubtitle"),
                    systemImage: "square.grid.2x2"
                ) {
                    Picker(
                        String(localized: "SmartButtonsToggleTitle"),
                        selection: Binding(
                            get: { max(4, min(16, settingsStore.settings.menuBarSmartButtonsLimit)) },
                            set: { newValue in
                                settingsStore.update { settings in
                                    settings.menuBarSmartButtonsLimit = max(4, min(16, newValue))
                                }
                            }
                        )
                    ) {
                        Text("4").tag(4)
                        Text("8").tag(8)
                        Text("12").tag(12)
                        Text("16").tag(16)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 88)
                }
                HStack(spacing: 8) {
                    Text(String(localized: "SmartButtonColorlessLabel"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { settingsStore.settings.menuBarSmartButtonsColorlessMode },
                        set: { newValue in
                            settingsStore.update { settings in
                                settings.menuBarSmartButtonsColorlessMode = newValue
                            }
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                Text(String(localized: "SmartButtonsOrderNote"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        /// Floating tile used while dragging a profile card.
        private func floatingProfilePreview(_ profile: DisplayProfile, size: CGSize) -> some View {
            profileTile(profile)
                .frame(width: size.width, height: size.height, alignment: .topLeading)
        }

        /// Keeps the dragged profile preview from feeling mechanically flat.
        private var profilePreviewTilt: Double {
            guard reduceMotion == false else { return 0 }
            return max(-2.5, min(2.5, profileDragTranslation.width / 40))
        }

        /// Drag gesture that tracks profile reordering and computes live drop targets.
        private func profileReorderGesture(for profileID: UUID) -> some Gesture {
            DragGesture(minimumDistance: 3, coordinateSpace: .named(profileGridCoordinateSpace))
                .onChanged { value in
                    if draggedProfileID != profileID {
                        draggedProfileID = profileID
                        profileDragStartFramesByID = profileFramesByID
                        profileSwapTargetID = nil
                    }
                    profileDragTranslation = value.translation
                    guard let draggedID = draggedProfileID else { return }
                    profileSwapTargetID = profileSwapTarget(for: value.translation, draggedID: draggedID)
                }
                .onEnded { _ in
                    applyProfileSwapIfNeeded()
                    draggedProfileID = nil
                    profileDragStartFramesByID.removeAll()
                    profileDragTranslation = .zero
                    profileSwapTargetID = nil
                }
        }

        /// Commits the queued profile swap operation when drag ends.
        private func applyProfileSwapIfNeeded() {
            guard let draggedID = draggedProfileID,
                  let targetID = profileSwapTargetID,
                  targetID != draggedID else { return }
            runMotion(DimlyMotion.reorderSettleSpring) {
                profileManager.swapProfiles(draggedID, with: targetID)
            }
        }

        /// Resolves which profile tile should swap with the dragged tile.
        private func profileSwapTarget(for translation: CGSize, draggedID: UUID) -> UUID? {
            let startFrames = profileDragStartFramesByID.isEmpty ? profileFramesByID : profileDragStartFramesByID
            guard let draggedFrame = startFrames[draggedID] else { return nil }
            if abs(translation.width) < 5 && abs(translation.height) < 5 {
                return nil
            }

            let dragRect = draggedFrame.offsetBy(dx: translation.width, dy: translation.height)
            let cancelPadding = max(draggedFrame.width, draggedFrame.height) * 0.45
            if draggedFrame.insetBy(dx: -cancelPadding, dy: -cancelPadding).contains(dragRect.center) {
                return nil
            }

            let orderedIDs = profileManager.profiles.map(\.id).filter { $0 != draggedID }
            let candidates: [(id: UUID, frame: CGRect)] = orderedIDs.compactMap { id in
                guard let frame = startFrames[id] ?? profileFramesByID[id] else { return nil }
                return (id: id, frame: frame)
            }
            guard candidates.isEmpty == false else {
                return nil
            }

            let frames = candidates.map(\.frame)
            let fallbackStepY = (frames.map(\.height).median ?? draggedFrame.height) + 10
            let stepY = inferredProfileStepY(from: frames, fallback: fallbackStepY)

            // Keep swaps in-row unless vertical intent is explicit.
            let laneLockThreshold = max(10, stepY * 0.55)
            let sameRowTolerance = max(6, stepY * 0.34)
            let scopedCandidates: [(id: UUID, frame: CGRect)] = {
                guard abs(translation.height) < laneLockThreshold else { return candidates }
                let sameRow = candidates.filter { abs($0.frame.midY - draggedFrame.midY) <= sameRowTolerance }
                return sameRow.isEmpty ? candidates : sameRow
            }()

            let overlapThreshold: CGFloat = 0.22
            let stickinessThreshold: CGFloat = 0.14
            let overlapScores: [(id: UUID, overlap: CGFloat)] = scopedCandidates.map { candidate in
                (id: candidate.id, overlap: dragRect.overlapRatio(with: candidate.frame))
            }

            if let currentTargetID = profileSwapTargetID,
               currentTargetID != draggedID,
               let currentScore = overlapScores.first(where: { $0.id == currentTargetID })?.overlap,
               currentScore >= stickinessThreshold {
                return currentTargetID
            }

            guard let strongest = overlapScores.max(by: { lhs, rhs in
                if abs(lhs.overlap - rhs.overlap) < 0.01 {
                    guard let lhsFrame = scopedCandidates.first(where: { $0.id == lhs.id })?.frame,
                          let rhsFrame = scopedCandidates.first(where: { $0.id == rhs.id })?.frame else {
                        return false
                    }
                    return dragRect.center.distanceSquared(to: lhsFrame.center) > dragRect.center.distanceSquared(to: rhsFrame.center)
                }
                return lhs.overlap < rhs.overlap
            }) else {
                return nil
            }

            return strongest.overlap >= overlapThreshold ? strongest.id : nil
        }

        /// Infers horizontal tile spacing for drag threshold calculations.
        private func inferredProfileStepX(from frames: [CGRect], fallback: CGFloat) -> CGFloat {
            let centers = frames.map { $0.center.x }.sorted()
            let diffs = zip(centers, centers.dropFirst()).map { $1 - $0 }.filter { $0 > 2 }
            return diffs.median ?? fallback
        }

        /// Infers vertical row spacing for drag threshold calculations.
        private func inferredProfileStepY(from frames: [CGRect], fallback: CGFloat) -> CGFloat {
            let centers = frames.map { $0.center.y }.sorted()
            let diffs = zip(centers, centers.dropFirst()).map { $1 - $0 }.filter { $0 > 2 }
            return diffs.median ?? fallback
        }

        private struct ProfileTileFramePreferenceKey: PreferenceKey {
            static let defaultValue: [UUID: CGRect] = [:]

            /// Merges profile tile frame snapshots for drag/drop calculations.
            static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
                value.merge(nextValue()) { _, new in new }
            }
        }

        private var automationSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(String(localized: "ProfileAutoApplyTitle"), isOn: $profileManager.automationEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.large)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach($profileManager.connectionRules) { $rule in
                        ConnectionRuleRow(
                            rule: $rule,
                            profiles: profileManager.profiles,
                            displayOptions: connectionRuleDisplayOptions(currentRuleID: rule.displayID),
                            onDelete: { profileManager.removeConnectionRule(id: rule.id) }
                        )
                        if rule.id != profileManager.connectionRules.last?.id {
                            SettingsDivider()
                        }
                    }
                    if !profileManager.connectionRules.isEmpty {
                        SettingsDivider()
                    }
                    Button {
                        profileManager.addConnectionRule()
                    } label: {
                        Label(String(localized: "ActionAddConnectionRuleButton"), systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(profileManager.profiles.isEmpty)
                    .padding(.top, profileManager.connectionRules.isEmpty ? 0 : 6)
                }
                .disabled(!profileManager.automationEnabled)
                .opacity(profileManager.automationEnabled ? 1 : 0.55)

                if let applied = profileManager.lastAppliedProfileName {
                    Text(String(format: String(localized: "LastAppliedFormat"), applied))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        /// Builds the display options list for a connection rule picker.
        /// Includes currently connected external displays and any offline displays from saved profiles.
        private func connectionRuleDisplayOptions(currentRuleID: String) -> [(id: String, label: String)] {
            var options: [(id: String, label: String)] = [
                (id: "", label: String(localized: "ProfileAutoApplyAnyMonitorLabel"))
            ]
            var seen = Set<String>()

            // Live displays: alias → hardware name → "External N" — no bullet marker needed in a picker.
            let sortedExternals = displayManager.displays.filter { $0.isExternal }.sorted { $0.displayID < $1.displayID }
            for (index, display) in sortedExternals.enumerated() {
                let id = display.stableIdentity
                if seen.insert(id).inserted {
                    let label = DisplayLabelResolver.displayName(
                        for: display,
                        settings: settingsStore.settings,
                        externalIndex: index + 1,
                        internalIndex: 1
                    )
                    options.append((id: id, label: label))
                }
            }

            // Offline displays sourced from saved profiles: alias → hardware name → generic "External".
            for profile in profileManager.profiles {
                for snapshot in profile.displays where snapshot.isBuiltin != true {
                    let id = snapshot.id
                    if seen.insert(id).inserted {
                        let label = settingsStore.settings.displayAliases[id]
                            .flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
                            ?? snapshot.name
                            ?? String(localized: "DisplayTypeExternalLabel")
                        options.append((id: id, label: label))
                    }
                }
            }

            // Preserve an unrecognised stale ID currently selected in this rule.
            if !currentRuleID.isEmpty, !seen.contains(currentRuleID) {
                options.append((id: currentRuleID, label: String(format: String(localized: "MissingDisplayFormat"), currentRuleID)))
            }

            return options
        }

        // MARK: - Schedule Tab

        private var scheduleDetail: some View {
            SettingsScrollView(
                title: String(localized: "ScheduleTabLabel"),
                subtitle: String(localized: "ScheduleTabSubtitle"),
                contentMaxWidth: 980
            ) {
                SettingsCard(title: String(localized: "ScheduleCardTitle"), subtitle: nil) {
                    SettingsToggleRow(
                        title: String(localized: "ScheduleEnableTitle"),
                        subtitle: String(localized: "ScheduleEnableSubtitle"),
                        systemImage: "clock.badge.checkmark",
                        isOn: Binding(
                            get: { scheduleManager.schedulingEnabled },
                            set: { scheduleManager.schedulingEnabled = $0 }
                        )
                    )
                    SettingsDivider()
                    if scheduleManager.entries.isEmpty {
                        Text(String(localized: "ScheduleEmptyLabel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach($scheduleManager.entries) { $entry in
                            ScheduleEntryRow(
                                entry: $entry,
                                profiles: profileManager.profiles,
                                onDelete: { scheduleManager.remove(id: entry.id) }
                            )
                            if entry.id != scheduleManager.entries.last?.id {
                                SettingsDivider()
                            }
                        }
                    }
                    SettingsDivider()
                    Button {
                        let defaultProfileID = profileManager.profiles.first?.id ?? UUID()
                        scheduleManager.addEntry(ScheduleEntry(
                            id: UUID(),
                            isEnabled: true,
                            profileID: defaultProfileID,
                            trigger: .clockTime(hour: 8, minute: 0),
                            daysOfWeek: []
                        ))
                    } label: {
                        Label(String(localized: "ActionAddScheduleButton"), systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(profileManager.profiles.isEmpty)
                    if profileManager.profiles.isEmpty {
                        Text(String(localized: "ScheduleNoProfilesLabel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Location card — only when at least one entry uses a solar trigger
                let hasSolarEntry = scheduleManager.entries.contains {
                    if case .sunrise = $0.trigger { return true }
                    if case .sunset = $0.trigger { return true }
                    return false
                }
                if hasSolarEntry {
                    SettingsCard(
                        title: String(localized: "ScheduleLocationTitle"),
                        subtitle: String(localized: "ScheduleLocationSubtitle")
                    ) {
                        SettingsRow(
                            title: String(localized: "ScheduleLocationRowTitle"),
                            subtitle: scheduleLocationSubtitle,
                            systemImage: "location.circle"
                        ) {
                            Button(String(localized: "ActionUseMyLocationButton")) {
                                scheduleManager.requestLocation()
                                showManualEntry = false
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .disabled(scheduleManager.isRequestingLocation)
                        }
                        if scheduleManager.isRequestingLocation {
                            Text(String(localized: "ScheduleLocationRequestingLabel"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Divider().opacity(0.5)
                        Button {
                            showManualEntry.toggle()
                            if showManualEntry {
                                if let c = scheduleManager.savedCoordinate {
                                    manualLatText = String(format: "%.4f", c.latitude)
                                    manualLonText = String(format: "%.4f", c.longitude)
                                } else {
                                    manualLatText = ""
                                    manualLonText = ""
                                }
                                manualEntryError = nil
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: showManualEntry ? "chevron.down" : "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(String(localized: "ManualCoordDisclosureLabel"))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .buttonStyle(.plain)
                        if showManualEntry {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(String(localized: "ManualCoordLatLabel"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextField("0.0000", text: $manualLatText)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 110)
                                            .onSubmit { applyManualCoordinates() }
                                    }
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(String(localized: "ManualCoordLonLabel"))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        TextField("0.0000", text: $manualLonText)
                                            .textFieldStyle(.roundedBorder)
                                            .frame(width: 110)
                                            .onSubmit { applyManualCoordinates() }
                                    }
                                    Spacer()
                                    Button(String(localized: "ManualCoordSaveButton")) {
                                        applyManualCoordinates()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                                if let err = manualEntryError {
                                    Text(err)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                                Text(String(localized: "ManualCoordHelpText"))
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
        }

        private func applyManualCoordinates() {
            manualEntryError = nil
            let latStr = manualLatText.replacingOccurrences(of: ",", with: ".")
            let lonStr = manualLonText.replacingOccurrences(of: ",", with: ".")
            guard let lat = Double(latStr) else {
                manualEntryError = String(localized: "ManualCoordErrorLatInvalid")
                return
            }
            guard let lon = Double(lonStr) else {
                manualEntryError = String(localized: "ManualCoordErrorLonInvalid")
                return
            }
            guard (-90...90).contains(lat) else {
                manualEntryError = String(localized: "ManualCoordErrorLatRange")
                return
            }
            guard (-180...180).contains(lon) else {
                manualEntryError = String(localized: "ManualCoordErrorLonRange")
                return
            }
            scheduleManager.setManualCoordinate(latitude: lat, longitude: lon)
            showManualEntry = false
        }

        private var scheduleLocationSubtitle: String {
            guard let coord = scheduleManager.savedCoordinate else {
                return String(localized: "HotkeyNotSetLabel")
            }
            let fmt = DateFormatter()
            fmt.dateStyle = .short
            fmt.timeStyle = .short
            return String(format: String(localized: "ScheduleLocationUpdatedFormat"), fmt.string(from: coord.updatedAt))
        }

        /// A single schedule entry row with trigger, time, profile and day pickers.
        private struct ConnectionRuleRow: View {
            @Binding var rule: DisplayConnectionRule
            let profiles: [DisplayProfile]
            let displayOptions: [(id: String, label: String)]
            let onDelete: () -> Void

            var body: some View {
                HStack(alignment: .center, spacing: 8) {
                    Toggle("", isOn: $rule.isEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)

                    Picker("", selection: $rule.displayID) {
                        ForEach(displayOptions, id: \.id) { option in
                            Text(option.label).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 130, maxWidth: 180)

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $rule.profileID) {
                        ForEach(profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(minWidth: 110, maxWidth: 160)
                    .disabled(profiles.isEmpty)

                    Spacer(minLength: 0)

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(String(localized: "ActionDeleteButton"))
                }
                .padding(.vertical, 4)
                .opacity(rule.isEnabled ? 1 : 0.55)
            }
        }

        private struct ScheduleEntryRow: View {
            @Binding var entry: ScheduleEntry
            let profiles: [DisplayProfile]
            let onDelete: () -> Void

            var body: some View {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .center, spacing: 10) {
                        Toggle("", isOn: $entry.isEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .controlSize(.small)

                        // Profile picker
                        Picker(String(localized: "ProfileAutoApplyPickerLabel"), selection: $entry.profileID) {
                            ForEach(profiles) { profile in
                                Text(profile.name).tag(profile.id)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(minWidth: 120, maxWidth: 180)
                        .disabled(profiles.isEmpty)

                        Spacer(minLength: 0)

                        // Delete button
                        Button {
                            onDelete()
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "ActionDeleteScheduleHint"))
                    }

                    HStack(alignment: .center, spacing: 8) {
                        // Trigger type picker
                        Picker(String(localized: "ScheduleTriggerTypePickerLabel"), selection: triggerTypePicker) {
                            ForEach(ScheduleTriggerType.allCases) { type in
                                Text(type.localizedTitle).tag(type)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(width: 100)

                        // Time / offset controls
                        switch entry.trigger {
                        case .clockTime:
                            DatePicker("", selection: clockDateBinding, displayedComponents: .hourAndMinute)
                                .labelsHidden()
                                .frame(width: 90)
                        case .sunrise(let offset), .sunset(let offset):
                            HStack(spacing: 4) {
                                Stepper(
                                    offsetLabel(offset),
                                    value: offsetBinding,
                                    in: -180...180
                                )
                                .frame(minWidth: 160)
                            }
                        }
                        Spacer(minLength: 0)
                    }

                    // Day-of-week picker
                    DayOfWeekPicker(selection: $entry.daysOfWeek)
                }
                .opacity(entry.isEnabled ? 1 : 0.55)
            }

            // MARK: Trigger type binding (maps flat enum ↔ enum with associated values)

            private var triggerTypePicker: Binding<ScheduleTriggerType> {
                Binding(
                    get: { entry.trigger.triggerType },
                    set: { newType in
                        switch newType {
                        case .clockTime:
                            entry.trigger = .clockTime(hour: 8, minute: 0)
                        case .sunrise:
                            entry.trigger = .sunrise(offsetMinutes: 0)
                        case .sunset:
                            entry.trigger = .sunset(offsetMinutes: 0)
                        }
                    }
                )
            }

            // MARK: Clock time DatePicker binding (Date ↔ hour+minute components)

            private var clockDateBinding: Binding<Date> {
                Binding(
                    get: {
                        guard case .clockTime(let h, let m) = entry.trigger else {
                            return Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date()) ?? Date()
                        }
                        return Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
                    },
                    set: { date in
                        let cal = Calendar.current
                        let h = cal.component(.hour, from: date)
                        let m = cal.component(.minute, from: date)
                        entry.trigger = .clockTime(hour: h, minute: m)
                    }
                )
            }

            // MARK: Solar offset binding

            private var offsetBinding: Binding<Int> {
                Binding(
                    get: {
                        switch entry.trigger {
                        case .sunrise(let o), .sunset(let o): return o
                        default: return 0
                        }
                    },
                    set: { newOffset in
                        switch entry.trigger {
                        case .sunrise: entry.trigger = .sunrise(offsetMinutes: newOffset)
                        case .sunset: entry.trigger = .sunset(offsetMinutes: newOffset)
                        default: break
                        }
                    }
                )
            }

            private func offsetLabel(_ offset: Int) -> String {
                if offset == 0 { return "±0 min" }
                let key = offset > 0 ? "ScheduleOffsetAfterFormat" : "ScheduleOffsetBeforeFormat"
                return String(format: String(localized: String.LocalizationValue(key)), abs(offset))
            }
        }

        /// A row of day-of-week toggle buttons that respects the locale's first weekday and symbols.
        private struct DayOfWeekPicker: View {
            @Binding var selection: [Int]  // 1=Sun…7=Sat (Calendar.weekday)

            /// Days ordered starting from the locale's first weekday (e.g. Sunday in US, Monday in Europe).
            private var orderedWeekdays: [Int] {
                let first = Calendar.current.firstWeekday
                return (0..<7).map { offset in ((first - 1 + offset) % 7) + 1 }
            }

            /// OS-localized very short day symbols (index 0 = Sunday, 6 = Saturday).
            private var symbols: [String] {
                Calendar.current.veryShortWeekdaySymbols
            }

            var body: some View {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        ForEach(orderedWeekdays, id: \.self) { day in
                            let isOn = selection.contains(day)
                            Button(symbols[day - 1]) {
                                if isOn {
                                    selection.removeAll { $0 == day }
                                } else {
                                    selection.append(day)
                                }
                            }
                            .buttonStyle(.plain)
                            .font(.caption2.weight(.semibold))
                            .frame(width: 22, height: 22)
                            .background(
                                Circle().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.15))
                            )
                            .foregroundStyle(isOn ? Color.white : Color.secondary)
                        }
                    }
                    if selection.isEmpty {
                        Text(String(localized: "ScheduleRecurrenceEveryDayLabel"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }

        private var aboutDetail: some View {
            SettingsScrollView(title: String(localized: "SettingsTabAboutLabel"), subtitle: nil, contentMaxWidth: 980) {
                SettingsCard(title: String(localized: "AppName"), subtitle: nil) {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
                    let versionLabel: String = {
                        if version.isEmpty { return build }
                        if build.isEmpty { return version }
                        let formatted = String(format: String(localized: "VersionFormat"), version, build)
                        if build == version {
                            return formatted.replacingOccurrences(of: " (\(build))", with: "")
                        }
                        return formatted
                    }()
                    HStack(alignment: .center, spacing: 14) {
                        if let icon = NSApp.applicationIconImage {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(radius: 6, y: 2)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "AppName"))
                                .font(.title2.bold())
                            Text(versionLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "AboutCopyrightLabel"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "AboutDescriptionText"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "AboutMadeByText"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsCard(
                    title: String(localized: "AboutCommunityTitle"),
                    subtitle: String(localized: "AboutCommunitySubtitle")
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(.white.opacity(0.22))
                                    )
                                Text(String(localized: "AboutBuiltOnGitHubLabel"))
                                    .font(.callout.weight(.semibold))
                                    .foregroundStyle(.white)
                                Spacer()
                            }
                            Text(String(localized: "AboutGitHubFollowText"))
                                .font(.caption)
                                .foregroundStyle(.white.opacity(0.9))
                        }
                        .padding(12)
                        .background(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.11, green: 0.47, blue: 0.89),
                                    Color(red: 0.12, green: 0.69, blue: 0.62)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                        Link(destination: URL(string: "https://github.com/Punshnut/macos-dimly")!) {
                            aboutActionTile(
                                title: String(localized: "AboutGitHubRepoTitle"),
                                subtitle: String(localized: "AboutGitHubRepoSubtitle"),
                                systemImage: "chevron.left.forwardslash.chevron.right",
                                tint: Color(red: 0.16, green: 0.50, blue: 0.89)
                            )
                        }
                        .buttonStyle(FluentPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.94))
                        .dimlyHoverLift(hoverScale: 1.01, shadowOpacity: 0.08)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) {
                                Link(destination: URL(string: "https://github.com/Punshnut/macos-dimly/issues/new")!) {
                                    aboutActionTile(
                                        title: String(localized: "AboutReportIssueTitle"),
                                        subtitle: String(localized: "AboutReportIssueSubtitle"),
                                        systemImage: "exclamationmark.bubble.fill",
                                        tint: Color(red: 0.93, green: 0.52, blue: 0.19)
                                    )
                                }
                                .buttonStyle(FluentPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.94))
                                .dimlyHoverLift(hoverScale: 1.01, shadowOpacity: 0.08)

                                Link(destination: URL(string: "https://ko-fi.com/janfeuerbacher")!) {
                                    aboutActionTile(
                                        title: String(localized: "AboutDonateTitle"),
                                        subtitle: String(localized: "AboutDonateSubtitle"),
                                        systemImage: "heart.fill",
                                        tint: Color(red: 0.86, green: 0.26, blue: 0.35)
                                    )
                                }
                                .buttonStyle(FluentPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.94))
                                .dimlyHoverLift(hoverScale: 1.01, shadowOpacity: 0.08)
                            }

                            VStack(spacing: 10) {
                                Link(destination: URL(string: "https://github.com/Punshnut/macos-dimly/issues/new")!) {
                                    aboutActionTile(
                                        title: String(localized: "AboutReportIssueTitle"),
                                        subtitle: String(localized: "AboutReportIssueSubtitle"),
                                        systemImage: "exclamationmark.bubble.fill",
                                        tint: Color(red: 0.93, green: 0.52, blue: 0.19)
                                    )
                                }
                                .buttonStyle(FluentPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.94))
                                .dimlyHoverLift(hoverScale: 1.01, shadowOpacity: 0.08)

                                Link(destination: URL(string: "https://ko-fi.com/janfeuerbacher")!) {
                                    aboutActionTile(
                                        title: String(localized: "AboutDonateTitle"),
                                        subtitle: String(localized: "AboutDonateSubtitle"),
                                        systemImage: "heart.fill",
                                        tint: Color(red: 0.86, green: 0.26, blue: 0.35)
                                    )
                                }
                                .buttonStyle(FluentPressButtonStyle(pressedScale: 0.985, pressedOpacity: 0.94))
                                .dimlyHoverLift(hoverScale: 1.01, shadowOpacity: 0.08)
                            }
                        }
                    }
                }
            }
        }

        /// Shared tile style for external about/support links.
        private func aboutActionTile(
            title: String,
            subtitle: String,
            systemImage: String,
            tint: Color
        ) -> some View {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemImage)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(tint.opacity(0.14))
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .stroke(Color.primary.opacity(0.10), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        }

        /// Computes the selected backup scope from the two category checkboxes.
        private var selectedBackupType: SettingsBackupType? {
            SettingsBackupType(includeGeneral: includeGeneralSettings, includeMonitor: includeMonitorSettings)
        }

        /// Custom file type used for exported backup files.
        private var backupContentType: UTType {
            UTType(filenameExtension: "backup") ?? .data
        }

        private static let backupFilenameDateFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = .current
            formatter.dateFormat = "yyyyMMdd"
            return formatter
        }()

        /// Builds a stable, sortable backup filename with date + scope token.
        private func backupFileName(for type: SettingsBackupType, date: Date) -> String {
            let formattedDate = Self.backupFilenameDateFormatter.string(from: date)
            return "DimlySettings\(formattedDate)\(type.fileToken).backup"
        }

        /// Reusable card UI for selecting which settings categories to include.
        private func backupSelectionTile(
            title: String,
            details: String,
            systemImage: String,
            isOn: Binding<Bool>
        ) -> some View {
            backupTileContainer {
                HStack(alignment: .center, spacing: 10) {
                    SettingsIcon(systemName: systemImage)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.callout.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.9)
                        Text(details)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Spacer(minLength: 8)
                    Toggle("", isOn: isOn)
                        .labelsHidden()
                        .toggleStyle(.checkbox)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// Reusable action card for import/export controls in the backup section.
        private func backupActionTile(
            title: String,
            systemImage: String,
            buttonTitle: String,
            disabled: Bool,
            action: @escaping () -> Void
        ) -> some View {
            backupTileContainer {
                HStack(alignment: .center, spacing: 10) {
                    SettingsIcon(systemName: systemImage)
                    Text(title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.86)
                    Spacer(minLength: 8)
                    Button(buttonTitle, action: action)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(disabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        /// Visual container shared by all backup cards for consistent spacing and chrome.
        private func backupTileContainer<Content: View>(
            @ViewBuilder content: () -> Content
        ) -> some View {
            content()
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
        }

        /// Imports a selected backup file and merges selected categories into live settings.
        private func importSelectedSettings() {
            guard selectedBackupType != nil else {
                showBackupAlert(
                    title: String(localized: "BackupImportErrorTitle"),
                    message: String(localized: "BackupSelectCategoryError")
                )
                return
            }

            let panel = NSOpenPanel()
            panel.canChooseFiles = true
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.allowedContentTypes = [backupContentType, .json]
            panel.message = String(localized: "BackupImportFilePrompt")

            guard panel.runModal() == .OK, let url = panel.url else { return }

            do {
                let data = try Data(contentsOf: url)
                let backup = try decodeBackup(from: data)
                let updated = try backup.applying(
                    to: settingsStore.settings,
                    includeGeneral: includeGeneralSettings,
                    includeMonitor: includeMonitorSettings
                )
                if updated != settingsStore.settings {
                    settingsStore.settings = updated
                }
                if let importedProfiles = backup.importedProfileState(includeMonitor: includeMonitorSettings) {
                    profileManager.importState(importedProfiles)
                }
            } catch SettingsBackupApplyError.missingGeneralSettings {
                showBackupAlert(
                    title: String(localized: "BackupImportErrorTitle"),
                    message: String(localized: "BackupImportMissingGeneralError")
                )
            } catch SettingsBackupApplyError.missingMonitorSettings {
                showBackupAlert(
                    title: String(localized: "BackupImportErrorTitle"),
                    message: String(localized: "BackupImportMissingMonitorError")
                )
            } catch {
                showBackupAlert(
                    title: String(localized: "BackupImportErrorTitle"),
                    message: String(localized: "BackupImportDecodeError")
                )
            }
        }

        /// Exports selected settings/profile state to a user-chosen backup file.
        private func exportSelectedSettings() {
            guard let selectedBackupType else {
                showBackupAlert(
                    title: String(localized: "BackupExportErrorTitle"),
                    message: String(localized: "BackupSelectCategoryError")
                )
                return
            }

            let backup = DimlySettingsBackup(
                settings: settingsStore.settings,
                type: selectedBackupType,
                profileState: profileManager.exportState()
            )
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                encoder.dateEncodingStrategy = .iso8601
                let data = try encoder.encode(backup)

                let panel = NSSavePanel()
                panel.allowedContentTypes = [backupContentType]
                panel.nameFieldStringValue = backupFileName(for: selectedBackupType, date: backup.exportedAt)
                panel.canCreateDirectories = true
                panel.isExtensionHidden = false

                guard panel.runModal() == .OK, let destinationURL = panel.url else { return }
                try data.write(to: destinationURL, options: .atomic)
            } catch {
                showBackupAlert(
                    title: String(localized: "BackupExportErrorTitle"),
                    message: String(localized: "BackupExportSaveError")
                )
            }
        }

        /// Decodes modern backup payloads and transparently upgrades legacy raw-settings files.
        private func decodeBackup(from data: Data) throws -> DimlySettingsBackup {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let backup = try? decoder.decode(DimlySettingsBackup.self, from: data) {
                return backup
            }
            let legacySettings = try decoder.decode(DimlySettings.self, from: data)
            return DimlySettingsBackup(settings: legacySettings, type: .generalAndMonitor)
        }

        /// Displays a modal warning used by backup import/export error paths.
        private func showBackupAlert(title: String, message: String) {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = title
            alert.informativeText = message
            alert.runModal()
        }

        /// Returns picker options for a hotkey target, including stale IDs still referenced in settings.
        private func displayOptions(for binding: HotkeyBinding) -> [DisplayOption] {
            externalDisplayOptions(includingMissingTarget: binding.target)
        }

        /// Returns picker options for profile automation trigger target.
        private func automationDisplayOptions(for target: HotkeyTarget) -> [DisplayOption] {
            externalDisplayOptions(includingMissingTarget: target)
                .map { option in
                    guard option.id == .allExternalDisplays else { return option }
                    return DisplayOption(
                        id: option.id,
                        label: String(localized: "ProfileAutoApplyAnyMonitorLabel")
                    )
                }
        }

        /// Returns external display picker options plus stale IDs if the selected target is missing.
        private func externalDisplayOptions(includingMissingTarget target: HotkeyTarget) -> [DisplayOption] {
            var options: [DisplayOption] = [
                DisplayOption(id: .allExternalDisplays, label: String(localized: "HotkeyTargetAllExternalLabel"))
            ]
            let externals = displayManager.displays.filter { $0.isExternal }
            options.append(contentsOf: externals.map { display in
                DisplayOption(
                    id: .display(id: display.stableIdentity),
                    label: displayOptionLabel(for: display)
                )
            })
            if case .display(let id) = target,
               options.contains(where: { $0.id == target }) == false {
                let label = String(format: String(localized: "MissingDisplayFormat"), id)
                options.append(DisplayOption(id: target, label: label))
            }
            return options
        }

        /// Formats display option labels with resolved display name and overlay marker.
        private func displayOptionLabel(for display: DisplayInfo) -> String {
            let externalIndex = displayManager.displays.filter { $0.isExternal }.sorted { $0.displayID < $1.displayID }
                .firstIndex(where: { $0.stableIdentity == display.stableIdentity }).map { $0 + 1 } ?? 1
            let internalIndex = displayManager.displays.filter { $0.isBuiltin }.sorted { $0.displayID < $1.displayID }
                .firstIndex(where: { $0.stableIdentity == display.stableIdentity }).map { $0 + 1 } ?? 1
            let marker = DisplayLabelResolver.overlayMarker(
                for: display,
                externalIndex: externalIndex,
                internalIndex: internalIndex,
                internalCount: displayManager.displays.filter { $0.isBuiltin }.count
            )
            let name = DisplayLabelResolver.displayName(
                for: display,
                settings: settingsStore.settings,
                externalIndex: externalIndex,
                internalIndex: internalIndex
            )
            return String(format: String(localized: "DisplayTypeResolutionFormat"), name, marker)
        }
    }
}

private extension AppAppearancePreference {
    var preferredColorScheme: ColorScheme? {
        switch self {
        case .system:
            nil
        case .light:
            .light
        case .dark:
            .dark
        }
    }

    var localizedTitle: String {
        switch self {
        case .system:
            String(localized: "AppearanceSystemLabel")
        case .light:
            String(localized: "AppearanceLightLabel")
        case .dark:
            String(localized: "AppearanceDarkLabel")
        }
    }
}

// MARK: - Hotkey Bindings UI

/// Picker option for mapping hotkeys to a display target.
private struct DisplayOption: Identifiable, Hashable {
    let id: HotkeyTarget
    let label: String
}

/// Row UI for a single hotkey binding.
private struct HotkeyBindingRow: View {
    @Binding var binding: HotkeyBinding
    let displayOptions: [DisplayOption]
    let onDelete: () -> Void

    /// Layout for the hotkey binding row.
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            SettingsIcon(systemName: "command")
            VStack(alignment: .leading, spacing: 8) {
                Picker(String(localized: "HotkeyDisplayPickerLabel"), selection: $binding.target) {
                    ForEach(displayOptions) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .disabled(binding.action.usesTarget == false)
                .opacity(binding.action.usesTarget ? 1.0 : 0.5)
                Picker(String(localized: "HotkeyActionPickerLabel"), selection: $binding.action) {
                    ForEach(HotkeyAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                Text(binding.descriptor?.displayString ?? String(localized: "HotkeyNotSetLabel"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HotkeyRecorder(descriptor: $binding.descriptor)
            }
            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 2)
        .onChange(of: binding.action) { _, newValue in
            if newValue.usesTarget == false {
                binding.target = .allExternalDisplays
            }
        }
    }
}

// MARK: - Hotkey Recorder

/// Recorder surface for capturing a new hotkey descriptor.
private struct HotkeyRecorder: View {
    @Binding var descriptor: HotkeyDescriptor?
    @State private var isRecording = false
    @State private var captureMonitor = HotkeyCaptureMonitor()

    /// Recorder UI that toggles capture and displays current binding.
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.12) : Color.clear)
                )
                .frame(width: 170, height: 36)
            HStack(spacing: 8) {
                Image(systemName: isRecording ? "dot.radiowaves.left.and.right" : "record.circle")
                Text(isRecording ? String(localized: "HotkeyRecordingLabel") : String(localized: "ActionChangeButton"))
            }
            .font(.callout)
        }
        .onTapGesture {
            isRecording.toggle()
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                captureMonitor.start { event in
                    guard let captured = HotkeyDescriptor(event: event) else { return }
                    DispatchQueue.main.async {
                        descriptor = captured
                        isRecording = false
                    }
                }
            } else {
                captureMonitor.stop()
            }
        }
        .onDisappear {
            captureMonitor.stop()
        }
    }
}

/// Captures the next key press using local + global event monitors.
private final class HotkeyCaptureMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var didCapture = false

    /// Starts listening for a single key press, then stops automatically.
    func start(handler: @escaping (NSEvent) -> Void) {
        stop()
        didCapture = false
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .systemDefined]) { event in
            guard self.didCapture == false else { return nil }
            self.didCapture = true
            handler(event)
            self.stop()
            return nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.systemDefined]) { event in
            guard self.didCapture == false else { return }
            self.didCapture = true
            handler(event)
            self.stop()
        }
    }

    /// Stops all event monitors and resets capture state.
    func stop() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        localMonitor = nil
        globalMonitor = nil
        didCapture = false
    }

    deinit {
        stop()
    }
}

private extension CGRect {
    /// Convenience initializer used by profile drag previews that are positioned from a center point.
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

    /// Returns how much of the smaller rect is covered by the intersection with another rect.
    func overlapRatio(with other: CGRect) -> CGFloat {
        let intersectionArea = intersection(other).area
        guard intersectionArea > 0 else { return 0 }
        let referenceArea = min(area, other.area)
        guard referenceArea > 0 else { return 0 }
        return intersectionArea / referenceArea
    }
}

private extension CGPoint {
    /// Squared euclidean distance, used for fast nearest-slot comparisons.
    func distanceSquared(to other: CGPoint) -> CGFloat {
        let dx = x - other.x
        let dy = y - other.y
        return (dx * dx) + (dy * dy)
    }
}

private extension Array where Element == CGFloat {
    /// Median value helper for robust spacing estimates in layout heuristics.
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
