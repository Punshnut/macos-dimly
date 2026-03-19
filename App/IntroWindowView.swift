// MARK: - Intro Window
// First-launch welcome UI.
import SwiftUI
import AppKit

/// Introductory surface shown the first time the app launches.
struct IntroWindowView: View {
    /// Called when the user dismisses the intro window.
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack(alignment: .topTrailing) {
            introBackground

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.32 : 0.18))
                        Image(systemName: "display")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.primary)
                    }
                    .frame(width: 44, height: 44)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "Welcome to Dimly"))
                            .font(.title2.bold())
                        Text(String(localized: "Your displays, one click away."))
                            .foregroundStyle(.secondary)
                    }
                }

                introCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(localized: "Dimly lives in the menu bar."))
                            .font(.headline)
                        Text(String(localized: "Look at the top-right of your screen for the display icon."))
                            .foregroundStyle(.secondary)
                    }
                }

                introCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text(String(localized: "How control mode works"))
                                .font(.headline)
                            Spacer()
                            statusPill(
                                title: String(localized: "Checking DDC"),
                                color: .orange
                            )
                        }

                        HStack(spacing: 10) {
                            modeTile(
                                title: String(localized: "DDC"),
                                subtitle: String(localized: "Direct monitor control for brightness and sleep/wake."),
                                symbol: "cable.connector",
                                color: .green
                            )
                            modeTile(
                                title: String(localized: "Overlay mode"),
                                subtitle: String(localized: "Fallback dimming layer when DDC is unavailable or disabled."),
                                symbol: "square.stack.3d.down.right.fill",
                                color: .blue
                            )
                        }

                        HStack(spacing: 8) {
                            Image(systemName: "arrow.triangle.branch")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(String(localized: "Dimly tries DDC first, then safely falls back to overlay mode."))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button(String(localized: "Got it")) {
                        onDismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 20)

            VStack(alignment: .trailing, spacing: 6) {
                Text(String(localized: "Menu bar"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(16)
        }
    }

    private var introBackground: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [
                    Color(red: 0.11, green: 0.12, blue: 0.15),
                    Color(red: 0.08, green: 0.11, blue: 0.16)
                ]
                : [
                    Color(red: 0.95, green: 0.96, blue: 0.98),
                    Color(red: 0.90, green: 0.94, blue: 0.98)
                ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    /// Shared card container used to group related intro content.
    @ViewBuilder
    private func introCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.44), lineWidth: 1)
        )
    }

    /// Explanatory tile describing one display-control path.
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
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(color.opacity(0.36), lineWidth: 1)
        )
    }

    /// Status badge used in the control-mode section header.
    private func statusPill(title: String, color: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.20))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}

#Preview {
    IntroWindowView(onDismiss: {})
        .frame(width: 500, height: 380)
}
