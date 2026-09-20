// MARK: - Texture Grid Popover
// Menu bar "Grid" mode: a thumbnail picker per display, for setups where a single cycle
// button isn't precise enough. Opened from MenuBarContentView's textureQuickAction.
import SwiftUI

private let textureGridPopoverColumns = [GridItem(.adaptive(minimum: 64, maximum: 80), spacing: 8)]

struct TextureGridPopoverView: View {
    let displays: [DisplayInfo]
    @ObservedObject var engine: DimlyEngine
    @ObservedObject var settingsStore: AppSettingsStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(displays) { display in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(settingsStore.settings.displayAliases[display.stableIdentity] ?? display.name ?? String(localized: "AppName"))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        LazyVGrid(columns: textureGridPopoverColumns, spacing: 8) {
                            noneTile(for: display)
                            ForEach(engine.textureManager.library) { entry in
                                tile(for: entry, display: display)
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
        .frame(width: 280, height: min(CGFloat(displays.count) * 140 + 20, 420))
    }

    private func noneTile(for display: DisplayInfo) -> some View {
        let isActive = settingsStore.settings.activeTextureByDisplayID[display.stableIdentity] == nil
        return Button {
            engine.setActiveTexture(nil, for: display)
        } label: {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.secondary.opacity(0.12))
                .frame(width: 56, height: 44)
                .overlay(Image(systemName: "slash.circle").font(.caption).foregroundStyle(.secondary))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(isActive ? Color.accentColor : .clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .help(String(localized: "TexturePickerNoneLabel"))
    }

    private func tile(for entry: TextureEntry, display: DisplayInfo) -> some View {
        let isActive = settingsStore.settings.activeTextureByDisplayID[display.stableIdentity] == entry.id
        return Button {
            engine.setActiveTexture(entry, for: display)
        } label: {
            Group {
                if let image = engine.textureManager.thumbnailImage(for: entry) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Rectangle().fill(Color.secondary.opacity(0.2))
                }
            }
            .frame(width: 56, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(isActive ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: isActive ? 2 : 0.5))
        }
        .buttonStyle(.plain)
        .help(entry.name)
    }
}
