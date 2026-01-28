// MARK: - Settings Window
// Tabbed SwiftUI surface for global preferences, shortcuts, profiles, and about info.
import SwiftUI
import AppKit

/// Settings window root with simple tab navigation.
struct SettingsRootView: View {
    @ObservedObject var settingsStore: AppSettingsStore
    @ObservedObject var displayManager: DisplayManager
    @ObservedObject var profileManager: ProfileManager
    @ObservedObject var ddcManager: DDCManager
    let engine: DimlyEngine
    @State private var introWindowController: IntroWindowController?

    var body: some View {
        TabView {
            generalTab
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
            shortcutsTab
                .tabItem { Label(String(localized: "Shortcuts"), systemImage: "keyboard") }
            profilesTab
                .tabItem { Label(String(localized: "Profiles"), systemImage: "rectangle.3.group") }
            aboutTab
                .tabItem { Label(String(localized: "About"), systemImage: "info.circle") }
        }
        .padding(20)
        .frame(minWidth: 320, idealWidth: 400, minHeight: 520)
    }

    // MARK: - Tabs

    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Toggle(String(localized: "Launch at login"), isOn: Binding(
                    get: { settingsStore.settings.launchAtLogin },
                    set: { newValue in settingsStore.update { $0.launchAtLogin = newValue } }
                ))
                Toggle(String(localized: "Show menu bar icon"), isOn: Binding(
                    get: { settingsStore.settings.showMenuBarIcon },
                    set: { newValue in settingsStore.update { $0.showMenuBarIcon = newValue } }
                ))
                Toggle(String(localized: "Hide Dock icon"), isOn: Binding(
                    get: { settingsStore.settings.hideDockIcon },
                    set: { newValue in settingsStore.update { $0.hideDockIcon = newValue } }
                ))
                Text(String(localized: "Hide the Dock icon and app switcher entry."))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                Text(String(localized: "Dimly stays running for hotkeys even when the menu bar icon is hidden."))
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Text(String(localized: "Displays"))
                    .font(.headline)
                    .padding(.top, 8)
                Toggle(String(localized: "Fade out on sleep/blackout"), isOn: Binding(
                    get: { settingsStore.settings.fadeOutAnimationEnabled },
                    set: { newValue in settingsStore.update { $0.fadeOutAnimationEnabled = newValue } }
                ))
                Toggle(String(localized: "Fade in on wake/restore"), isOn: Binding(
                    get: { settingsStore.settings.fadeInAnimationEnabled },
                    set: { newValue in settingsStore.update { $0.fadeInAnimationEnabled = newValue } }
                ))
                Toggle(String(localized: "Show display numbers on screens"), isOn: Binding(
                    get: { settingsStore.settings.showDisplayNumbers },
                    set: { newValue in settingsStore.update { $0.showDisplayNumbers = newValue } }
                ))
                if displayManager.displays.isEmpty {
                    Text(String(localized: "No active displays detected."))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(displayManager.displays) { display in
                        displayRow(for: display)
                    }
                }
                Divider()
                    .padding(.top, 8)
                Button(String(localized: "Show introduction again")) {
                    showIntroAgain()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.visible)
    }

    @ViewBuilder
    private func displayRow(for display: DisplayInfo) -> some View {
        let name = displayName(for: display)
        let status = displayStatus(for: display)
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                    .font(.headline)
                Spacer()
                Button(String(localized: "Rename")) {
                    renameDisplay(display, currentName: name)
                }
            }
            let typeLabel = display.isBuiltin ? String(localized: "Internal") : String(localized: "External")
            Text(String(format: String(localized: "DisplayTypeResolutionFormat"), typeLabel, display.resolution))
                .foregroundStyle(.secondary)
            if let hz = display.refreshRateHz {
                Text(String(format: String(localized: "RefreshRateFormat"), hz))
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
            let state = ddcManager.states[display.stableIdentity] ?? DDCState(status: .unknown, lastError: nil, lastCommand: nil, lastCommandAt: nil)
            let ddcSupported = state.status == .supported
            let overlayOnly = settingsStore.settings.overlayOnlyDisplayIDs.contains(display.stableIdentity)
            let fallbackActive = (!ddcSupported || overlayOnly) && engine.blackoutManager.activeDisplayIDs.contains(display.stableIdentity)
            let controlTint: Color = (ddcSupported && !overlayOnly) ? .green : (fallbackActive ? .blue : .secondary)
            let canControl = display.isExternal
            HStack(spacing: 8) {
                Label(String(format: String(localized: "DDCStatusFormat"), state.status.localizedDescription), systemImage: state.status == .supported ? "antenna.radiowaves.left.and.right" : "nosign")
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
                Button(String(localized: "Wake")) { engine.wake(display: display) }
                    .tint(controlTint)
                    .disabled(!canControl)
            }
            if display.isExternal {
                Toggle(String(localized: "Overlay Only (Never Sleep)"), isOn: Binding(
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
                .toggleStyle(.switch)
            }
        }
        .padding(.vertical, 6)
    }

    private var shortcutsTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(String(localized: "Global shortcuts"))
                    .font(.headline)

                if settingsStore.settings.hotkeyBindings.isEmpty {
                    emptyHotkeysCard
                } else {
                    ForEach(settingsStore.settings.hotkeyBindings, id: \.id) { binding in
                        HotkeyBindingRow(
                            binding: hotkeyBinding(for: binding.id),
                            displayOptions: displayOptions(for: binding),
                            onDelete: { removeHotkeyBinding(binding.id) }
                        )
                    }
                }

                Button {
                    addHotkeyBinding()
                } label: {
                    Label(String(localized: "Add Hotkey"), systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)

                HStack {
                    Label(String(localized: "Panic hotkey (fixed):"), systemImage: "bolt.fill")
                    Text(HotkeyDescriptor.panicDefault.displayString)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.top, 16)
            .padding(.bottom, 20)
        }
        .scrollIndicators(.visible)
    }

    private var emptyHotkeysCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "No hotkeys set yet"))
                .font(.subheadline.weight(.semibold))
            Text(String(localized: "Add a hotkey to quickly toggle blackout or sleep/wake."))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func addHotkeyBinding() {
        settingsStore.update { settings in
            settings.hotkeyBindings.append(
                HotkeyBinding(
                    action: .toggleBlackout,
                    target: .allExternalDisplays,
                    descriptor: nil
                )
            )
        }
    }

    private func removeHotkeyBinding(_ id: UUID) {
        settingsStore.update { settings in
            settings.hotkeyBindings.removeAll { $0.id == id }
        }
    }

    private func hotkeyBinding(for id: UUID) -> Binding<HotkeyBinding> {
        Binding(
            get: {
                settingsStore.settings.hotkeyBindings.first { $0.id == id }
                    ?? HotkeyBinding(id: id, action: .toggleBlackout, target: .allExternalDisplays, descriptor: nil)
            },
            set: { updated in
                settingsStore.update { settings in
                    guard let index = settings.hotkeyBindings.firstIndex(where: { $0.id == id }) else { return }
                    settings.hotkeyBindings[index] = updated
                }
            }
        )
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

    private var profilesTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(String(localized: "Profiles"))
                    .font(.headline)
                Spacer()
                Button(String(localized: "Save Current Setup")) {
                    profileManager.saveCurrentProfile(named: proposedProfileName)
                    proposedProfileName = ""
                }
                TextField(String(localized: "Profile name"), text: $proposedProfileName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            if profileManager.profiles.isEmpty {
                Text(String(localized: "No profiles yet. Save the current display setup to create one."))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(profileManager.profiles) { profile in
                    profileRow(profile)
                }
            }

            Divider()
            automationSection
            Spacer()
        }
        .padding(.horizontal, 14)
    }

    @State private var proposedProfileName: String = ""

    @ViewBuilder
    private func profileRow(_ profile: DisplayProfile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(profile.name)
                    .font(.subheadline.bold())
                Text(profile.createdAt, style: .date)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(String(localized: "Apply")) { profileManager.apply(profile: profile) }
                Button(String(localized: "Rename")) {
                    renameProfile(profile)
                }
                Button(role: .destructive, action: { profileManager.delete(profile: profile) }) {
                    Text(String(localized: "Delete"))
                }
            }
            Text(String(format: String(localized: "ProfileDisplayCountFormat"), Int64(profile.displays.count)))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    @State private var renameText: String = ""

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

    private func renameProfile(_ profile: DisplayProfile) {
        renameText = profile.name
        let alert = NSAlert()
        alert.messageText = String(localized: "Rename Profile")
        alert.informativeText = String(localized: "Enter a new name for this profile.")
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        let input = NSTextField(string: renameText)
        input.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = input
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            profileManager.rename(profile: profile, to: input.stringValue)
        }
    }

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

    private func displayOptionLabel(for display: DisplayInfo) -> String {
        let name = displayName(for: display)
        let externalIndex = externalIndexMap[display.stableIdentity] ?? 1
        let internalIndex = internalIndexMap[display.stableIdentity] ?? 1
        let marker = DisplayLabelResolver.overlayMarker(
            for: display,
            externalIndex: externalIndex,
            internalIndex: internalIndex,
            internalCount: internalDisplayCount
        )
        return String(format: String(localized: "DisplayTypeResolutionFormat"), name, marker)
    }

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

    private func indexMap(for displays: [DisplayInfo]) -> [String: Int] {
        let ordered = displays.sorted { $0.displayID < $1.displayID }
        var mapping: [String: Int] = [:]
        for (index, display) in ordered.enumerated() {
            mapping[display.stableIdentity] = index + 1
        }
        return mapping
    }

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

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 16) {
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
                        .foregroundStyle(.secondary)
                    Text(String(localized: "© 2026 Jan Feuerbacher"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text(String(localized: "Dimly is a native Swift macOS utility for quickly blacking out external displays and managing sleep/wake."))
                    .foregroundStyle(.secondary)
                Text(String(localized: "Made in my free time - thanks for the support."))
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Link(destination: URL(string: "https://github.com/Punshnut/dimly")!) {
                    Label(String(localized: "GitHub Repo"), systemImage: "link")
                }
                Link(destination: URL(string: "https://github.com/Punshnut/dimly/issues/new")!) {
                    Label(String(localized: "Report an Issue"), systemImage: "exclamationmark.bubble")
                }
                Link(destination: URL(string: "https://ko-fi.com/janfeuerbacher")!) {
                    Label(String(localized: "Donate"), systemImage: "heart")
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }
}

// MARK: - Hotkey Bindings UI

private struct DisplayOption: Identifiable, Hashable {
    let id: HotkeyTarget
    let label: String
}

private struct HotkeyBindingRow: View {
    @Binding var binding: HotkeyBinding
    let displayOptions: [DisplayOption]
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Picker(String(localized: "Display"), selection: $binding.target) {
                    ForEach(displayOptions) { option in
                        Text(option.label).tag(option.id)
                    }
                }
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
        }
        .padding(12)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Hotkey Recorder

private struct HotkeyRecorder: View {
    @Binding var descriptor: HotkeyDescriptor?
    @State private var isRecording = false
    @State private var captureMonitor = HotkeyCaptureMonitor()

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
        .onChange(of: isRecording) { newValue in
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

private final class HotkeyCaptureMonitor {
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var didCapture = false

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
