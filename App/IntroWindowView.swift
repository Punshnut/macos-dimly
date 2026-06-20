// MARK: - Intro Window
// First-launch welcome UI.
import SwiftUI
import AppKit

/// Introductory surface shown the first time the app launches.
struct IntroWindowView: View {
    /// Called when the user dismisses the intro window.
    let onDismiss: () -> Void
    /// Live display inventory — observed so the built-in card appears as soon as displays load.
    @ObservedObject var displayManager: DisplayManager
    /// Whether to include the built-in display in Dimly. Bound to controller state.
    @Binding var includeInternalMonitor: Bool

    @Environment(\.colorScheme) private var colorScheme
    @State private var ddcPulse = false

    private var builtInDisplay: DisplayInfo? {
        displayManager.displays.first(where: { $0.isBuiltin })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            headerRow
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
        .padding(.horizontal, 28)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .background(Color.clear)
        .animation(.spring(duration: 0.45), value: builtInDisplay != nil)
    }

    // MARK: - Header

    private var headerRow: some View {
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

                Image(systemName: "display")
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
            .frame(width: 56, height: 56)
            .shadow(color: Color.accentColor.opacity(0.30), radius: 14, y: 4)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(localized: "IntroWelcomeTitle"))
                    .font(.title.bold())
                Text(String(localized: "IntroWelcomeSubtitle"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
                        .onAppear { ddcPulse = true }
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
