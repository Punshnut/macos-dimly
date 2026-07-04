// MARK: - Intro Window
// First-launch welcome UI.
import SwiftUI
import AppKit

/// Which page of the intro window is currently visible.
enum IntroPage {
    /// Full first-run onboarding tour.
    case welcome
    /// Lightweight, purely informational summary of recently added features.
    case whatsNew
}

/// Introductory surface shown the first time the app launches. Also hosts a "What's New" page
/// that returning users can be opened directly to after an update, reachable via the same tab
/// strip so nothing about it feels like a separate, disconnected surface.
struct IntroWindowView: View {
    /// Called when the user dismisses the intro window.
    let onDismiss: () -> Void
    /// Live display inventory — observed so the built-in card appears as soon as displays load.
    @ObservedObject var displayManager: DisplayManager
    /// Whether to include the built-in display in Dimly. Bound to controller state.
    @Binding var includeInternalMonitor: Bool
    /// Features listed on the What's New page.
    let whatsNewFeatures: [WhatsNewFeature]
    /// Called after `currentPage` changes so the host window can re-measure and resize.
    var onPageChange: (() -> Void)?

    @State private var currentPage: IntroPage
    @Environment(\.colorScheme) private var colorScheme
    @State private var ddcPulse = false

    init(
        onDismiss: @escaping () -> Void,
        displayManager: DisplayManager,
        includeInternalMonitor: Binding<Bool>,
        initialPage: IntroPage = .welcome,
        whatsNewFeatures: [WhatsNewFeature] = [],
        onPageChange: (() -> Void)? = nil
    ) {
        self.onDismiss = onDismiss
        self.displayManager = displayManager
        self._includeInternalMonitor = includeInternalMonitor
        self.whatsNewFeatures = whatsNewFeatures
        self.onPageChange = onPageChange
        self._currentPage = State(initialValue: initialPage)
    }

    private var builtInDisplay: DisplayInfo? {
        displayManager.displays.first(where: { $0.isBuiltin })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageBody
        }
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .background(Color.clear)
        .animation(.spring(duration: 0.45), value: builtInDisplay != nil)
        .onChange(of: currentPage) { _, _ in onPageChange?() }
    }

    // MARK: - Page Tab Strip

    /// A small, minimal pill slider — no icons or text, just a floating thumb. A single real
    /// `Button` toggling between the two pages, in the style of macOS's Liquid Glass switches.
    /// Placed inline in the header (not at the very top of the window) since bare SwiftUI
    /// gestures/buttons sitting in a titled window's top drag strip can lose clicks to the
    /// window's own move-by-background handling — only genuine `NSControl`-backed views like
    /// this `Button` reliably claim them there.
    private var pageTabStrip: some View {
        let totalWidth: CGFloat = 44
        let height: CGFloat = 18
        let inset: CGFloat = 2
        let segmentWidth = totalWidth / 2
        let tooltip = currentPage == .welcome
            ? String(localized: "WhatsNewHeaderTitle")
            : String(localized: "IntroWelcomeTitle")

        return Button {
            withAnimation(.spring(duration: 0.4)) {
                currentPage = (currentPage == .welcome) ? .whatsNew : .welcome
            }
        } label: {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                Capsule()
                    .fill(.background)
                    .shadow(color: .black.opacity(colorScheme == .dark ? 0.4 : 0.15), radius: 1.5, y: 0.5)
                    .frame(width: segmentWidth - inset * 2, height: height - inset * 2)
                    .offset(x: (currentPage == .whatsNew ? segmentWidth : 0) + inset)
            }
            .frame(width: totalWidth, height: height)
        }
        .buttonStyle(.plain)
        .help(tooltip)
    }

    @ViewBuilder
    private var pageBody: some View {
        switch currentPage {
        case .welcome:
            welcomePage
                .transition(.asymmetric(
                    insertion: .move(edge: .leading).combined(with: .opacity),
                    removal: .move(edge: .trailing).combined(with: .opacity)
                ))
        case .whatsNew:
            whatsNewPage
                .transition(.asymmetric(
                    insertion: .move(edge: .trailing).combined(with: .opacity),
                    removal: .move(edge: .leading).combined(with: .opacity)
                ))
        }
    }

    private var welcomePage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeaderRow(
                symbol: "display",
                title: String(localized: "IntroWelcomeTitle"),
                subtitle: String(localized: "IntroWelcomeSubtitle")
            )
            menuBarCard
            controlModeCard
            if builtInDisplay != nil {
                internalMonitorCard
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            Divider()
                .padding(.top, 4)
            actionRow
        }
    }

    private var whatsNewPage: some View {
        VStack(alignment: .leading, spacing: 16) {
            pageHeaderRow(
                symbol: "sparkles",
                title: String(localized: "WhatsNewHeaderTitle"),
                subtitle: String(localized: "WhatsNewHeaderSubtitle")
            )
            ForEach(whatsNewFeatures) { feature in
                whatsNewFeatureCard(feature)
            }
            Divider()
                .padding(.top, 4)
            whatsNewActionRow
        }
    }

    // MARK: - Header

    /// Shared icon-badge + title/subtitle header used by both pages, with an inline page slider
    /// when there's a What's New page to switch to.
    private func pageHeaderRow(symbol: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(LinearGradient(
                        colors: [
                            Color.accentColor.opacity(colorScheme == .dark ? 0.30 : 0.18),
                            Color.accentColor.opacity(colorScheme == .dark ? 0.10 : 0.06)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1.5)
                    )

                Image(systemName: symbol)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 56, height: 56)
            .shadow(color: Color.accentColor.opacity(0.30), radius: 14, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if !whatsNewFeatures.isEmpty {
                Spacer(minLength: 12)
                pageTabStrip
            }
        }
    }

    // MARK: - Cards

    private var menuBarCard: some View {
        introCard {
            HStack(spacing: 10) {
                Image(systemName: "menubar.rectangle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "IntroMenuBarTitle"))
                        .font(.headline)
                    Text(String(localized: "IntroMenuBarHint"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var controlModeCard: some View {
        introCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(String(localized: "IntroControlModeTitle"))
                        .font(.headline)
                    Spacer()
                    statusPill(title: String(localized: "DDCCheckingLabel"), color: .orange)
                        .opacity(ddcPulse ? 0.55 : 1.0)
                        .animation(
                            .easeInOut(duration: 1.1).repeatForever(autoreverses: true),
                            value: ddcPulse
                        )
                        .onAppear {
                            // Starts slightly after appearing so the pulse doesn't kick off mid-
                            // way through the window's own entrance/resize animation and visibly
                            // "bounce" the badge.
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                ddcPulse = true
                            }
                        }
                }

                HStack(spacing: 10) {
                    modeTile(
                        title: String(localized: "DDC"),
                        subtitle: String(localized: "IntroControlDDCSubtitle"),
                        symbol: "cable.connector",
                        color: .green
                    )
                    modeTile(
                        title: String(localized: "DisplayModeOverlayLabel"),
                        subtitle: String(localized: "IntroControlOverlaySubtitle"),
                        symbol: "square.stack.3d.down.right.fill",
                        color: .blue
                    )
                }

                HStack(spacing: 8) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "IntroControlFallbackNote"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var internalMonitorCard: some View {
        introCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "laptopcomputer")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "IntroInternalMonitorTitle"))
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $includeInternalMonitor)
                            .toggleStyle(.switch)
                            .tint(.accentColor)
                            .labelsHidden()
                    }
                    Text(String(localized: "IntroInternalMonitorHint"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if let name = builtInDisplay?.name {
                        Text(name)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(.quaternary))
                    }
                }
            }
        }
    }

    // MARK: - What's New

    private func whatsNewFeatureCard(_ feature: WhatsNewFeature) -> some View {
        introCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: feature.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(feature.color)
                    .frame(width: 22)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: String.LocalizationValue(feature.titleKey)))
                        .font(.headline)
                    Text(String(localized: String.LocalizationValue(feature.descriptionKey)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button {
                        SettingsNavigationCoordinator.shared.pendingTarget = feature.settingsTarget
                        NotificationCenter.default.post(name: .dimlyOpenSettingsWindow, object: nil)
                    } label: {
                        HStack(spacing: 4) {
                            Text(String(localized: String.LocalizationValue(feature.locationKey)))
                            Image(systemName: "chevron.right")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(feature.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(feature.color.opacity(colorScheme == .dark ? 0.22 : 0.14)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var whatsNewActionRow: some View {
        Button {
            onDismiss()
        } label: {
            Label(String(localized: "WhatsNewDismissButton"), systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    // MARK: - Action Row

    private var actionRow: some View {
        Button {
            onDismiss()
        } label: {
            Label(String(localized: "IntroGotItButton"), systemImage: "arrow.right.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .keyboardShortcut(.defaultAction)
    }

    // MARK: - Shared Subviews

    @ViewBuilder
    private func introCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.regularMaterial)
        )
        // Top-edge specular highlight for depth
        .overlay(alignment: .top) {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color.white.opacity(colorScheme == .dark ? 0.12 : 0.60), .clear],
                    startPoint: .top,
                    endPoint: .center
                ))
                .frame(height: 32)
                .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    Color.white.opacity(colorScheme == .dark ? 0.10 : 0.55),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
    }

    private func modeTile(title: String, subtitle: String, symbol: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
            }
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(colorScheme == .dark ? 0.18 : 0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(color.opacity(0.32), lineWidth: 1)
        )
    }

    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.18))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

#Preview {
    IntroWindowView(
        onDismiss: {},
        displayManager: DisplayManager(),
        includeInternalMonitor: .constant(true)
    )
    .frame(width: 520)
    .background(.regularMaterial)
}
