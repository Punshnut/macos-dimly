import SwiftUI
import AppKit

// MARK: - Settings Layout System

struct SettingsBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        LinearGradient(
            colors: gradientColors,
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    private var gradientColors: [Color] {
        if colorScheme == .dark {
            return [
                Color(red: 0.10, green: 0.11, blue: 0.13),
                Color(red: 0.12, green: 0.12, blue: 0.16),
                Color(red: 0.08, green: 0.10, blue: 0.14)
            ]
        }
        return [
            Color(red: 0.94, green: 0.95, blue: 0.97),
            Color(red: 0.90, green: 0.92, blue: 0.96),
            Color(red: 0.86, green: 0.89, blue: 0.94)
        ]
    }
}

struct SettingsScrollView<Content: View>: View {
    let title: String
    let subtitle: String?
    var contentMaxWidth: CGFloat? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            SettingsBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsHeader(title: title, subtitle: subtitle)
                    content()
                }
                .frame(maxWidth: contentMaxWidth, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .padding(.top, 4)
            }
            .safeAreaInset(edge: .top) {
                Color.clear.frame(height: 6)
            }
        }
    }
}

struct SettingsHeader: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.title.weight(.semibold))
            if let subtitle, subtitle.isEmpty == false {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.bottom, 2)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                if let subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            content()
        }
        .padding(14)
        .background(cardBackground)
        .overlay(cardBorder)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: cardShadow.color, radius: cardShadow.radius, x: 0, y: cardShadow.y)
    }

    private var cardBackground: some View {
        Group {
            if colorScheme == .dark {
                Rectangle().fill(.ultraThinMaterial)
            } else {
                Rectangle().fill(Color.white.opacity(0.78))
            }
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(cardBorderColor, lineWidth: 1)
    }

    private var cardBorderColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.white.opacity(0.5)
    }

    private var cardShadow: (color: Color, radius: CGFloat, y: CGFloat) {
        colorScheme == .dark
            ? (Color.black.opacity(0.18), 16, 10)
            : (Color.black.opacity(0.08), 16, 10)
    }
}

struct SettingsIcon: View {
    let systemName: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Circle()
                .fill(iconGradient)
                .frame(width: 34, height: 34)
            Image(systemName: systemName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white)
        }
    }

    private var iconGradient: LinearGradient {
        if colorScheme == .dark {
            return LinearGradient(
                colors: [
                    Color(red: 0.25, green: 0.32, blue: 0.52),
                    Color(red: 0.46, green: 0.30, blue: 0.62)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        return LinearGradient(
            colors: [
                Color(red: 0.18, green: 0.52, blue: 0.86),
                Color(red: 0.23, green: 0.78, blue: 0.68)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct SettingsDivider: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(dividerColor)
            .frame(height: 1)
            .padding(.leading, 44)
    }

    private var dividerColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color.black.opacity(0.08)
    }
}

struct SettingsRow<Accessory: View>: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            SettingsIcon(systemName: systemImage)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                if let subtitle, subtitle.isEmpty == false {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            accessory()
        }
        .padding(.vertical, 1)
    }
}

struct SettingsToggleRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title: title, subtitle: subtitle, systemImage: systemImage) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.large)
        }
    }
}

struct SettingsWindowToolbarHider: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem(id: "settings.toolbar.placeholder", placement: .automatic) {
                    Color.clear.frame(width: 0, height: 0)
                }
            }
            .background(SettingsToolbarCleaner())
    }
}

extension View {
    func hideSettingsToolbar() -> some View {
        modifier(SettingsWindowToolbarHider())
    }
}

// Removes leftover sidebar/separator toolbar items and keeps the toolbar alive.
private struct SettingsToolbarCleaner: NSViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        Task { @MainActor in
            context.coordinator.attachToolbar(to: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        Task { @MainActor in
            context.coordinator.attachToolbar(to: nsView.window)
        }
    }

    final class Coordinator: NSObject, NSToolbarDelegate {
        private let placeholderID = NSToolbarItem.Identifier("settings.toolbar.placeholder")

        @MainActor func attachToolbar(to window: NSWindow?) {
            guard let window else { return }
            if window.toolbar == nil {
                window.toolbar = NSToolbar(identifier: "SettingsToolbar")
            }
            window.toolbar?.delegate = self
            pruneToolbarItems(in: window.toolbar)
        }

        @MainActor private func pruneToolbarItems(in toolbar: NSToolbar?) {
            guard let toolbar else { return }
            let removalIndices = toolbar.items.enumerated().compactMap { index, item in
                let raw = item.itemIdentifier.rawValue.lowercased()
                if raw.contains("sidebar") || raw.contains("separator") {
                    return index
                }
                return nil
            }
            for index in removalIndices.reversed() {
                toolbar.removeItem(at: index)
            }
            if toolbar.items.contains(where: { $0.itemIdentifier == placeholderID }) == false {
                toolbar.insertItem(withItemIdentifier: placeholderID, at: 0)
            }
        }

        func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [placeholderID]
        }

        func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
            [placeholderID]
        }

        func toolbar(
            _ toolbar: NSToolbar,
            itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
            willBeInsertedIntoToolbar flag: Bool
        ) -> NSToolbarItem? {
            guard itemIdentifier == placeholderID else { return nil }
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            let view = NSView(frame: .zero)
            item.view = view
            return item
        }
    }
}
