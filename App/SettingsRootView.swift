// MARK: - Settings Window
// Sidebar-based SwiftUI surface for global preferences, shortcuts, profiles, and about info.
import SwiftUI
import AppKit

/// Settings window root with sidebar navigation.
struct SettingsRootView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var profileManager: ProfileManager
    @ObservedObject var ddcManager: DDCManager
    let engine: DimlyEngine
    @State private var introWindowController: IntroWindowController?
    @State private var selection: SettingsDestination = .general
    @State private var proposedProfileName: String = ""

    enum SettingsDestination: Hashable {
        case general
        case displays
        case shortcuts
        case profiles
        case about
    }

    /// Settings UI with sidebar navigation.
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(selection: $selection) {
                Section(String(localized: "General")) {
                    Label(String(localized: "General"), systemImage: "gearshape")
                        .tag(SettingsDestination.general)
                    Label(String(localized: "Displays"), systemImage: "display")
                        .tag(SettingsDestination.displays)
                    Label(String(localized: "Shortcuts"), systemImage: "keyboard")
                        .tag(SettingsDestination.shortcuts)
                    Label(String(localized: "Profiles"), systemImage: "rectangle.3.group")
                        .tag(SettingsDestination.profiles)
                    Label(String(localized: "About"), systemImage: "info.circle")
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
                proposedProfileName: $proposedProfileName,
                renameProfile: renameProfile,
                showIntroAgain: showIntroAgain,
                displayRow: { display in AnyView(displayRowView(for: display)) }
            )
        }
        .frame(minWidth: 900, minHeight: 580)
        .hideSettingsToolbar()
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
        alert.messageText = String(localized: "Rename Profile")
        alert.informativeText = String(localized: "Enter a new name for this profile.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let input = NSTextField(string: profile.name)
        input.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = input
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            profileManager.rename(profile: profile, to: input.stringValue)
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
        if engine.blackoutManager.activeDisplayIDs.contains(display.stableIdentity) {
            return String(localized: "Blackout")
        }
        if settingsStore.settings.overlayOnlyDisplayIDs.contains(display.stableIdentity) == false,
           engine.ddcManager.states[display.stableIdentity]?.lastCommand == .standby {
            return String(localized: "Sleep requested")
        }
        return String(localized: "Visible")
    }

    private var externalIndexMap: [String: Int] {
        indexMap(for: displayManager.displays.filter { $0.isExternal })
    }

    private var internalIndexMap: [String: Int] {
        indexMap(for: displayManager.displays.filter { $0.isBuiltin })
    }

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

    /// Renders a detailed row for a single display in Settings.
    @ViewBuilder
    private func displayRowView(for display: DisplayInfo) -> some View {
        let name = displayName(for: display)
        let status = displayStatus(for: display)
        let typeLabel = display.isBuiltin ? String(localized: "Internal") : String(localized: "External")
        let state = ddcManager.states[display.stableIdentity] ?? DDCState(status: .unknown, lastError: nil, lastCommand: nil, lastCommandAt: nil)
        let ddcSupported = state.status == .supported
        let overlayOnly = settingsStore.settings.overlayOnlyDisplayIDs.contains(display.stableIdentity)
        let fallbackActive = (!ddcSupported || overlayOnly) && engine.blackoutManager.activeDisplayIDs.contains(display.stableIdentity)
        let controlTint: Color = (ddcSupported && !overlayOnly) ? .green : (fallbackActive ? .blue : .secondary)
        let canControl = display.isExternal

        HStack(alignment: .top, spacing: 14) {
            SettingsIcon(systemName: display.isBuiltin ? "laptopcomputer" : "display")
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    Text(name)
                        .font(.callout.weight(.semibold))
                    Spacer()
                    Button(String(localized: "Rename")) {
                        renameDisplay(display, currentName: name)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text(String(format: String(localized: "DisplayTypeResolutionFormat"), typeLabel, display.resolution))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let hz = display.refreshRateHz {
                    Text(String(format: String(localized: "RefreshRateFormat"), hz))
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    Button(String(localized: "Standby")) { engine.standby(display: display) }
                        .tint(controlTint)
                        .disabled(!canControl)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(String(localized: "Wake")) { engine.wake(display: display) }
                        .tint(controlTint)
                        .disabled(!canControl)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }

                if display.isExternal {
                    HStack(spacing: 10) {
                        Text(String(localized: "Overlay Only (Never Sleep)"))
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
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: - Detail Views

    private struct SettingsDetailView: View {
        let selection: SettingsDestination
        @ObservedObject var settingsStore: AppSettingsStore
        @ObservedObject var displayManager: DisplayManager
        @ObservedObject var profileManager: ProfileManager
        @ObservedObject var ddcManager: DDCManager
        let engine: DimlyEngine
        @Binding var proposedProfileName: String
        let renameProfile: (DisplayProfile) -> Void
        let showIntroAgain: () -> Void
        let displayRow: (DisplayInfo) -> AnyView

        var body: some View {
            switch selection {
            case .general:
                generalDetail
            case .displays:
                displaysDetail
            case .shortcuts:
                shortcutsDetail
            case .profiles:
                profilesDetail
            case .about:
                aboutDetail
            }
        }

        private var generalDetail: some View {
            SettingsScrollView(title: String(localized: "General"), subtitle: nil) {
                SettingsCard(title: String(localized: "General"), subtitle: nil) {
                    SettingsToggleRow(
                        title: String(localized: "Autostart"),
                        subtitle: String(localized: "Start Dimly automatically when you log in."),
                        systemImage: "power.circle",
                        isOn: Binding(
                            get: { settingsStore.settings.launchAtLogin },
                            set: { newValue in settingsStore.update { $0.launchAtLogin = newValue } }
                        )
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: String(localized: "Show menu bar icon"),
                        subtitle: nil,
                        systemImage: "menubar.rectangle",
                        isOn: Binding(
                            get: { settingsStore.settings.showMenuBarIcon },
                            set: { newValue in settingsStore.update { $0.showMenuBarIcon = newValue } }
                        )
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: String(localized: "Hide Dock icon"),
                        subtitle: nil,
                        systemImage: "dock.rectangle",
                        isOn: Binding(
                            get: { settingsStore.settings.hideDockIcon },
                            set: { newValue in settingsStore.update { $0.hideDockIcon = newValue } }
                        )
                    )
                    SettingsDivider()
                    VStack(alignment: .leading, spacing: 6) {
                        Text(String(localized: "Hide the Dock icon and app switcher entry."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Dimly stays running for hotkeys even when the menu bar icon is hidden."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    SettingsDivider()
                    Button(String(localized: "Show introduction again")) {
                        showIntroAgain()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }

        private var displaysDetail: some View {
            SettingsScrollView(title: String(localized: "Displays"), subtitle: nil) {
                SettingsCard(title: String(localized: "Displays"), subtitle: nil) {
                    SettingsToggleRow(
                        title: String(localized: "Fade out on sleep/blackout"),
                        subtitle: nil,
                        systemImage: "moon.zzz",
                        isOn: Binding(
                            get: { settingsStore.settings.fadeOutAnimationEnabled },
                            set: { newValue in settingsStore.update { $0.fadeOutAnimationEnabled = newValue } }
                        )
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: String(localized: "Fade in on wake/restore"),
                        subtitle: nil,
                        systemImage: "sun.max",
                        isOn: Binding(
                            get: { settingsStore.settings.fadeInAnimationEnabled },
                            set: { newValue in settingsStore.update { $0.fadeInAnimationEnabled = newValue } }
                        )
                    )
                    SettingsDivider()
                    SettingsToggleRow(
                        title: String(localized: "Show display numbers on screens"),
                        subtitle: nil,
                        systemImage: "number",
                        isOn: Binding(
                            get: { settingsStore.settings.showDisplayNumbers },
                            set: { newValue in settingsStore.update { $0.showDisplayNumbers = newValue } }
                        )
                    )
                    SettingsDivider()
                    if displayManager.displays.isEmpty {
                        Text(String(localized: "No active displays detected."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(displayManager.displays) { display in
                            displayRow(display)
                            if display.id != displayManager.displays.last?.id {
                                SettingsDivider()
                            }
                        }
                    }
                }
            }
        }

        private var shortcutsDetail: some View {
            SettingsScrollView(title: String(localized: "Shortcuts"), subtitle: nil) {
                SettingsCard(title: String(localized: "Global shortcuts"), subtitle: nil) {
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
                        Label(String(localized: "Add Hotkey"), systemImage: "plus.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    SettingsDivider()

                    SettingsRow(
                        title: String(localized: "Panic hotkey (fixed):"),
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
                Text(String(localized: "No hotkeys set yet"))
                    .font(.callout.weight(.semibold))
                Text(String(localized: "Add a hotkey to quickly toggle blackout or sleep/wake."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        private var profilesDetail: some View {
            SettingsScrollView(title: String(localized: "Profiles"), subtitle: nil) {
                SettingsCard(title: String(localized: "Profiles"), subtitle: nil) {
                    HStack(alignment: .center, spacing: 10) {
                        Button(String(localized: "Save Current Setup")) {
                            profileManager.saveCurrentProfile(named: proposedProfileName)
                            proposedProfileName = ""
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        TextField(String(localized: "Profile name"), text: $proposedProfileName)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                    }

                    SettingsDivider()

                    if profileManager.profiles.isEmpty {
                        Text(String(localized: "No profiles yet. Save the current display setup to create one."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(profileManager.profiles) { profile in
                            profileRow(profile)
                            if profile.id != profileManager.profiles.last?.id {
                                SettingsDivider()
                            }
                        }
                    }

                    SettingsDivider()
                    automationSection
                }
            }
        }

        @ViewBuilder
        private func profileRow(_ profile: DisplayProfile) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .center, spacing: 10) {
                    Text(profile.name)
                        .font(.callout.weight(.semibold))
                    Text(profile.createdAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(String(localized: "Apply")) { profileManager.apply(profile: profile) }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    Button(String(localized: "Rename")) {
                        renameProfile(profile)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button(role: .destructive, action: { profileManager.delete(profile: profile) }) {
                        Text(String(localized: "Delete"))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                Text(String(format: String(localized: "ProfileDisplayCountFormat"), Int64(profile.displays.count)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        private var automationSection: some View {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(String(localized: "Auto-apply profile when an external display connects"), isOn: $profileManager.automationEnabled)
                Picker(String(localized: "Profile to apply"), selection: Binding(
                    get: { profileManager.automationProfileID ?? profileManager.profiles.first?.id },
                    set: { profileManager.automationProfileID = $0 }
                )) {
                    ForEach(profileManager.profiles) { profile in
                        Text(profile.name).tag(Optional(profile.id))
                    }
                }
                .disabled(profileManager.profiles.isEmpty || profileManager.automationEnabled == false)
                if let applied = profileManager.lastAppliedProfileName {
                    Text(String(format: String(localized: "LastAppliedFormat"), applied))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }

        private var aboutDetail: some View {
            SettingsScrollView(title: String(localized: "About"), subtitle: nil) {
                SettingsCard(title: String(localized: "Dimly"), subtitle: nil) {
                    let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
                    let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
                    HStack(alignment: .center, spacing: 14) {
                        if let icon = NSApp.applicationIconImage {
                            Image(nsImage: icon)
                                .resizable()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .shadow(radius: 6, y: 2)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(localized: "Dimly"))
                                .font(.title2.bold())
                            Text(String(format: String(localized: "VersionFormat"), version, build))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(String(localized: "© 2026 Jan Feuerbacher"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "Dimly is a native Swift macOS utility for quickly blacking out external displays and managing sleep/wake."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(localized: "Made in my free time - thanks for the support."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                SettingsCard(title: String(localized: "About"), subtitle: nil) {
                    HStack(spacing: 12) {
                        Link(destination: URL(string: "https://github.com/Punshnut/macos-dimly")!) {
                            Label(String(localized: "GitHub Repo"), systemImage: "link")
                        }
                        Link(destination: URL(string: "https://github.com/Punshnut/macos-dimly/issues/new")!) {
                            Label(String(localized: "Report an Issue"), systemImage: "exclamationmark.bubble")
                        }
                        Link(destination: URL(string: "https://ko-fi.com/janfeuerbacher")!) {
                            Label(String(localized: "Donate"), systemImage: "heart")
                        }
                    }
                }
            }
        }

        private func displayOptions(for binding: HotkeyBinding) -> [DisplayOption] {
            var options: [DisplayOption] = [
                DisplayOption(id: .allExternalDisplays, label: String(localized: "All External Displays"))
            ]
            let externals = displayManager.displays.filter { $0.isExternal }
            options.append(contentsOf: externals.map { display in
                DisplayOption(
                    id: .display(id: display.stableIdentity),
                    label: displayOptionLabel(for: display)
                )
            })
            if case .display(let id) = binding.target,
               options.contains(where: { $0.id == binding.target }) == false {
                let label = String(format: String(localized: "MissingDisplayFormat"), id)
                options.append(DisplayOption(id: binding.target, label: label))
            }
            return options
        }

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
                Picker(String(localized: "Display"), selection: $binding.target) {
                    ForEach(displayOptions) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .disabled(binding.action.usesTarget == false)
                .opacity(binding.action.usesTarget ? 1.0 : 0.5)
                Picker(String(localized: "Action"), selection: $binding.action) {
                    ForEach(HotkeyAction.allCases) { action in
                        Text(action.title).tag(action)
                    }
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                Text(binding.descriptor?.displayString ?? String(localized: "Not set"))
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

/// Simple recorder surface that captures a new hotkey descriptor.
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
                Text(isRecording ? String(localized: "Press keys") : String(localized: "Change"))
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
