import SwiftUI
import AppKit

// MARK: - Display Section Content
// Stateless per-display tile builders, shared between the Displays tab's per-monitor
// card (SettingsRootView.displayRowView) and the Settings search results view, so a
// display's brightness/contrast/etc. tile is defined exactly once regardless of where
// it's rendered.
@MainActor
enum DisplaySectionContent {
    @ViewBuilder
    static func brightness(
        for display: DisplayInfo,
        engine: DimlyEngine,
        brightnessTint: Color,
        brightnessModeLabel: String
    ) -> some View {
        let currentBrightness = Double(engine.brightnessPercent(for: display))
        DimlySliderContainer(tint: brightnessTint) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Spacer()
                    Text(
                        String.localizedStringWithFormat(
                            String(localized: "BrightnessPercentFormat"),
                            Int64(currentBrightness.rounded())
                        )
                    )
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    Text(brightnessModeLabel)
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(brightnessTint.opacity(0.18))
                        .foregroundStyle(brightnessTint)
                        .clipShape(Capsule())
                }
                HStack(spacing: 8) {
                    Button {
                        let current = engine.brightnessPercent(for: display)
                        let updated = max(0, current - 1)
                        if updated != current { engine.setBrightness(updated, for: display, source: .slider) }
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
                            get: { Double(engine.brightnessPercent(for: display)) },
                            set: { engine.setBrightness(Int($0.rounded()), for: display, source: .slider) }
                        ),
                        in: 0...100
                    )
                    .tint(brightnessTint)
                    Button {
                        let current = engine.brightnessPercent(for: display)
                        let updated = min(100, current + 1)
                        if updated != current { engine.setBrightness(updated, for: display, source: .slider) }
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
        }
    }

    @ViewBuilder
    static func contrast(for display: DisplayInfo, ddcManager: DDCManager, engine: DimlyEngine) -> some View {
        let currentContrast = ddcManager.contrastLevels[display.stableIdentity] ?? 50
        DimlySliderContainer(tint: .green) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Spacer()
                    Text(String.localizedStringWithFormat(String(localized: "ContrastPercentFormat"), Int64(currentContrast)))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Button {
                        let next = max(0, currentContrast - 1)
                        engine.setContrast(next, for: display)
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(FluentPressButtonStyle(pressedScale: 0.84, pressedOpacity: 0.82))
                    .foregroundStyle(.secondary)
                    .help(String(localized: "ActionDecreaseContrastHint"))
                    Slider(
                        value: Binding(
                            get: { Double(currentContrast) },
                            set: { engine.setContrast(Int($0.rounded()), for: display) }
                        ),
                        in: 0...100
                    )
                    .tint(.green)
                    Button {
                        let next = min(100, currentContrast + 1)
                        engine.setContrast(next, for: display)
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(FluentPressButtonStyle(pressedScale: 0.84, pressedOpacity: 0.82))
                    .foregroundStyle(.secondary)
                    .help(String(localized: "ActionIncreaseContrastHint"))
                }
            }
        }
    }

    @ViewBuilder
    static func power(for display: DisplayInfo, engine: DimlyEngine, controlTint: Color) -> some View {
        HStack(spacing: 8) {
            Button(String(localized: "ActionStandbyButton")) { engine.standby(display: display) }
                .tint(controlTint)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(String(localized: "ActionWakeButton")) { engine.wake(display: display) }
                .tint(controlTint)
                .buttonStyle(.bordered)
                .controlSize(.small)
            Spacer()
        }
    }

    @ViewBuilder
    static func nightShiftRow(for display: DisplayInfo, nightShiftManager: NightShiftManager, displayManager: DisplayManager, showLabel: Bool = true) -> some View {
        if nightShiftManager.isAvailable && (display.isBuiltin || displayManager.displays.filter(\.isBuiltin).isEmpty) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    if showLabel {
                        Text(String(localized: "NightShiftLabel"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { nightShiftManager.isEnabled },
                        set: { nightShiftManager.setEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.large)
                }
                if nightShiftManager.isEnabled {
                    DimlySliderContainer(tint: .orange) {
                        HStack(spacing: 8) {
                            Text(String(localized: "NightShiftLessWarmLabel"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Slider(
                                value: Binding(
                                    get: { Double(nightShiftManager.strength) },
                                    set: { nightShiftManager.setStrength(Float($0)) }
                                ),
                                in: 0...1
                            )
                            .tint(.orange)
                            Text(String(localized: "NightShiftMoreWarmLabel"))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    static func trueToneRow(for display: DisplayInfo, trueToneManager: TrueToneManager, showLabel: Bool = true) -> some View {
        if trueToneManager.isTrueToneAvailable(for: display) {
            HStack {
                if showLabel {
                    Text(String(localized: "TrueToneLabel"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { trueToneManager.isTrueToneEnabled(for: display) },
                    set: { trueToneManager.setTrueTone($0, for: display) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.large)
            }
        }
    }

    @ViewBuilder
    static func displayFilterRow(for display: DisplayInfo, displayAppearanceManager: DisplayAppearanceManager, engine: DimlyEngine, showLabel: Bool = true) -> some View {
        let currentFilter = displayAppearanceManager.activeFilter[display.stableIdentity] ?? .standard
        HStack {
            if showLabel {
                Text(String(localized: "DisplayFilterLabel"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { currentFilter },
                set: { engine.setDisplayFilter($0, for: display) }
            )) {
                ForEach(DisplayFilter.displayable) { filter in
                    Text(filter.localizedName).tag(filter)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .labelsHidden()
        }
    }

    @ViewBuilder
    static func lutPicker(for display: DisplayInfo, settingsStore: AppSettingsStore, engine: DimlyEngine, showLabel: Bool = true) -> some View {
        let activeLUTID = settingsStore.settings.activeLUTByDisplayID[display.stableIdentity]
        HStack {
            if showLabel {
                Text(String(localized: "LUTRowLabel"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { activeLUTID },
                set: { newID in
                    let entry = newID.flatMap { id in engine.lutManager.library.first { $0.id == id } }
                    engine.setActiveLUT(entry, for: display)
                }
            )) {
                Text(String(localized: "LUTPickerNoneLabel")).tag(Optional<UUID>.none)
                if !engine.lutManager.library.isEmpty {
                    Divider()
                    ForEach(engine.lutManager.library) { entry in
                        Text(entry.name).tag(Optional(entry.id))
                    }
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .labelsHidden()
        }
    }

    /// Color profile row — full picker for externals; System Settings hint for internals.
    @ViewBuilder
    static func colorProfile(for display: DisplayInfo, colorProfileManager: ColorProfileManager, engine: DimlyEngine, showLabel: Bool = true) -> some View {
        if display.isBuiltin {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(String(localized: "ColorProfileBuiltinHintLabel"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(String(localized: "OpenSystemSettingsButton")) {
                    NSWorkspace.shared.open(
                        URL(string: "x-apple.systempreferences:com.apple.displays-settings")!
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        } else {
            let profiles = colorProfileManager.availableProfiles[display.stableIdentity] ?? []
            let currentID = colorProfileManager.currentProfile[display.stableIdentity]?.id
                ?? ColorProfile.systemDefaultID
            if !profiles.isEmpty {
                HStack {
                    if showLabel {
                        Text(String(localized: "ColorProfileSectionLabel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { currentID },
                        set: { id in
                            if let profile = profiles.first(where: { $0.id == id }) {
                                engine.setColorProfile(profile, for: display)
                            }
                        }
                    )) {
                        // Sections mirror the profile groups for organised presentation.
                        let byGroup = Dictionary(grouping: profiles, by: \.group)
                        // System Default first, always.
                        if let defaults = byGroup[.standard]?.filter(\.isSystemDefault) {
                            ForEach(defaults) { Text($0.name).tag($0.id) }
                        }
                        // Curated standard profiles.
                        let standards = (byGroup[.standard] ?? []).filter { !$0.isSystemDefault }
                        if !standards.isEmpty {
                            Section(String(localized: "ColorProfileGroupStandardLabel")) {
                                ForEach(standards) { Text($0.name).tag($0.id) }
                            }
                        }
                        // Modern / extended colour spaces.
                        let modern = byGroup[.modern] ?? []
                        if !modern.isEmpty {
                            Section(String(localized: "ColorProfileGroupModernLabel")) {
                                ForEach(modern) { Text($0.name).tag($0.id) }
                            }
                        }
                        // Creative effect profiles (/Library).
                        let creative = byGroup[.creative] ?? []
                        if !creative.isEmpty {
                            Section(String(localized: "ColorProfileGroupCreativeLabel")) {
                                ForEach(creative) { Text($0.name).tag($0.id) }
                            }
                        }
                        // Hardware calibration profiles (/Library/Displays).
                        let calibration = byGroup[.calibration] ?? []
                        if !calibration.isEmpty {
                            Section(String(localized: "ColorProfileGroupCalibrationLabel")) {
                                ForEach(calibration) { Text($0.name).tag($0.id) }
                            }
                        }
                        // User-installed profiles (~/Library).
                        let user = byGroup[.user] ?? []
                        if !user.isEmpty {
                            Section(String(localized: "ColorProfileGroupUserLabel")) {
                                ForEach(user) { Text($0.name).tag($0.id) }
                            }
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .labelsHidden()
                }
            }
        }
    }

    @ViewBuilder
    static func resolution(for display: DisplayInfo, displayModeManager: DisplayModeManager, engine: DimlyEngine, showLabel: Bool = true) -> some View {
        let grouped = displayModeManager.groupedModes(for: display)
        let currentMode = displayModeManager.currentMode[display.stableIdentity]
        if grouped.isEmpty {
            Text(String(localized: "DDCUnknownLabel"))
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                let currentResLabel = currentMode.map { $0.resolutionLabel + ($0.isHiDPI ? " HiDPI" : "") } ?? ""
                let currentResGroup = grouped.first(where: { $0.resolution == currentResLabel }) ?? grouped.first!
                HStack {
                    if showLabel {
                        Text(String(localized: "ResolutionPickerLabel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("", selection: Binding(
                        get: { currentResLabel },
                        set: { newRes in
                            if let group = grouped.first(where: { $0.resolution == newRes }),
                               let preferred = group.modes.first(where: { $0.refreshRate == currentMode?.refreshRate }) ?? group.modes.first {
                                engine.setDisplayMode(preferred, for: display)
                            }
                        }
                    )) {
                        ForEach(grouped, id: \.resolution) { group in
                            Text(group.resolution).tag(group.resolution)
                        }
                    }
                    .pickerStyle(.menu)
                    .controlSize(.small)
                    .labelsHidden()
                }
                if currentResGroup.modes.count > 1 {
                    HStack {
                        Text(String(localized: "RefreshRatePickerLabel"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Picker("", selection: Binding(
                            get: { currentMode?.refreshRate ?? currentResGroup.modes.first?.refreshRate ?? 60 },
                            set: { hz in
                                if let mode = currentResGroup.modes.first(where: { $0.refreshRate == hz }) {
                                    engine.setDisplayMode(mode, for: display)
                                }
                            }
                        )) {
                            ForEach(currentResGroup.modes, id: \.refreshRate) { mode in
                                Text(String(format: "%.0fHz", mode.refreshRate)).tag(mode.refreshRate)
                            }
                        }
                        .pickerStyle(.menu)
                        .controlSize(.small)
                        .labelsHidden()
                    }
                }
            }
        }
    }

    @ViewBuilder
    static func inputSource(for display: DisplayInfo, ddcManager: DDCManager, engine: DimlyEngine, showLabel: Bool = true) -> some View {
        let currentSource = ddcManager.inputSources[display.stableIdentity]
        HStack {
            if showLabel {
                Text(String(localized: "SectionInputSourceTitle"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Picker("", selection: Binding(
                get: { currentSource?.rawValue ?? -1 },
                set: { rawValue in
                    if let source = DDCInputSource(rawValue: rawValue) {
                        engine.setInputSource(source, for: display)
                    }
                }
            )) {
                if currentSource == nil {
                    Text(String(localized: "InputSourceUnknownLabel")).tag(-1)
                }
                ForEach(DDCInputSource.allCases) { source in
                    Text(source.localizedName).tag(source.rawValue)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .labelsHidden()
        }
    }

    @ViewBuilder
    static func overlayOnlyToggle(for display: DisplayInfo, settingsStore: AppSettingsStore) -> some View {
        if display.isExternal {
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
                                if !settings.overlayOnlyDisplayIDs.contains(display.stableIdentity) {
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
    }

    @ViewBuilder
    static func showInDimlyToggle(for display: DisplayInfo, settingsStore: AppSettingsStore) -> some View {
        let isShownInDimly: Bool = {
            if display.isBuiltin {
                return settingsStore.settings.menuBarIncludedInternalDisplayIDs.contains(display.stableIdentity)
            }
            return settingsStore.settings.menuBarExcludedDisplayIDs.contains(display.stableIdentity) == false
        }()
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
                                if !settings.menuBarIncludedInternalDisplayIDs.contains(display.stableIdentity) {
                                    settings.menuBarIncludedInternalDisplayIDs.append(display.stableIdentity)
                                }
                            } else {
                                settings.menuBarIncludedInternalDisplayIDs.removeAll { $0 == display.stableIdentity }
                            }
                        } else {
                            if enabled {
                                settings.menuBarExcludedDisplayIDs.removeAll { $0 == display.stableIdentity }
                            } else if !settings.menuBarExcludedDisplayIDs.contains(display.stableIdentity) {
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

    @ViewBuilder
    static func dimlyBehavior(for display: DisplayInfo, settingsStore: AppSettingsStore) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            overlayOnlyToggle(for: display, settingsStore: settingsStore)
            showInDimlyToggle(for: display, settingsStore: settingsStore)
        }
    }

    @ViewBuilder
    static func image(
        for display: DisplayInfo,
        nightShiftManager: NightShiftManager,
        displayManager: DisplayManager,
        trueToneManager: TrueToneManager,
        displayAppearanceManager: DisplayAppearanceManager,
        engine: DimlyEngine,
        settingsStore: AppSettingsStore,
        colorProfileManager: ColorProfileManager
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            nightShiftRow(for: display, nightShiftManager: nightShiftManager, displayManager: displayManager)
            trueToneRow(for: display, trueToneManager: trueToneManager)
            displayFilterRow(for: display, displayAppearanceManager: displayAppearanceManager, engine: engine)
            lutPicker(for: display, settingsStore: settingsStore, engine: engine)
            colorProfile(for: display, colorProfileManager: colorProfileManager, engine: engine)
        }
    }
}
