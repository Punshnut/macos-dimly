// MARK: - Texture Library Tab
// Settings → Textures: thumbnail grid of imported/bundled/procedural textures, the menu bar
// mode toggle, and the "Texture Playground" code editor. Mirrors the LUT Library tab's
// structure/patterns (see _LUTsDetailView in SettingsRootView.swift).
import SwiftUI
import AppKit
import UniformTypeIdentifiers

private let textureThumbnailColumns = [GridItem(.adaptive(minimum: 76, maximum: 92), spacing: 10)]

struct _TexturesDetailView: View {
    @ObservedObject var textureManager: TextureManager
    @ObservedObject var settingsStore: AppSettingsStore
    let engine: DimlyEngine

    @State private var showImporter = false
    @State private var importError: String? = nil
    @State private var showImportError = false
    @State private var showPlayground = false
    @State private var editingEntry: TextureEntry?
    @State private var draggedFavoriteID: UUID?

    var body: some View {
        SettingsScrollView(
            title: String(localized: "TextureLibraryTitle"),
            subtitle: String(localized: "TextureLibrarySubtitle"),
            contentMaxWidth: 780
        ) {
            SettingsCard(title: String(localized: "TextureLibraryTitle"), subtitle: nil) {
                HStack {
                    Spacer()
                    Button(String(localized: "TexturePlaygroundOpenButton")) {
                        editingEntry = nil
                        showPlayground = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    Button(String(localized: "TextureImportButton")) {
                        showImporter = true
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if textureManager.library.isEmpty {
                    Text(String(localized: "TextureEmptyStateLabel"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 12)
                } else {
                    SettingsDivider()
                    LazyVGrid(columns: textureThumbnailColumns, spacing: 12) {
                        ForEach(textureManager.library) { entry in
                            TextureThumbnailTile(
                                entry: entry,
                                image: textureManager.thumbnailImage(for: entry),
                                onRename: { showRenameAlert(for: entry) },
                                onDelete: { confirmDeleteTexture(entry) },
                                onEdit: entry.kind == .procedural ? {
                                    editingEntry = entry
                                    showPlayground = true
                                } : nil
                            )
                        }
                    }
                }
            }

            SettingsCard(title: String(localized: "TextureMenuBarModeTitle"), subtitle: String(localized: "TextureMenuBarModeSubtitle")) {
                Picker("", selection: Binding(
                    get: { settingsStore.settings.textureMenuBarMode },
                    set: { newValue in settingsStore.update { $0.textureMenuBarMode = newValue } }
                )) {
                    ForEach(TextureMenuBarMode.allCases) { mode in
                        Text(mode.localizedName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                if settingsStore.settings.textureMenuBarMode == .cycle {
                    SettingsDivider()
                    Text(String(localized: "TextureCycleFavoritesLabel"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    favoritesReorderList
                }
            }
        }
        .fileImporter(
            isPresented: $showImporter,
            allowedContentTypes: TextureManager.supportedImageExtensions.compactMap { UTType(filenameExtension: $0) } + [UTType(filenameExtension: "svg") ?? .data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                guard let url = urls.first else { return }
                do {
                    _ = try textureManager.importTexture(from: url)
                } catch {
                    importError = error.localizedDescription
                    showImportError = true
                }
            case .failure:
                break
            }
        }
        .alert(
            String(localized: "TextureImportErrorTitle"),
            isPresented: $showImportError,
            presenting: importError
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { msg in
            Text(msg)
        }
        .sheet(isPresented: $showPlayground) {
            TexturePlaygroundView(textureManager: textureManager, engine: engine, editingEntry: editingEntry)
        }
    }

    private var favoritesReorderList: some View {
        let favorites = settingsStore.settings.textureCycleOrder.compactMap { id in
            textureManager.library.first { $0.id == id }
        }
        return VStack(spacing: 0) {
            if favorites.isEmpty {
                Text(String(localized: "TextureCycleFavoritesEmptyLabel"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            } else {
                ForEach(favorites) { entry in
                    HStack(spacing: 8) {
                        Image(systemName: "line.3.horizontal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(entry.name)
                            .font(.caption)
                        Spacer()
                        Button {
                            removeFromFavorites(entry)
                        } label: {
                            Image(systemName: "minus.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                    .onDrag {
                        draggedFavoriteID = entry.id
                        return NSItemProvider(object: entry.id.uuidString as NSString)
                    }
                    .onDrop(of: [.text], delegate: FavoriteDropDelegate(
                        target: entry, draggedID: $draggedFavoriteID,
                        favorites: favorites, settingsStore: settingsStore
                    ))
                }
            }
            Menu(String(localized: "TextureCycleFavoritesAddButton")) {
                ForEach(textureManager.library.filter { entry in
                    !settingsStore.settings.textureCycleOrder.contains(entry.id)
                }) { entry in
                    Button(entry.name) { addToFavorites(entry) }
                }
            }
            .menuStyle(.borderlessButton)
            .font(.caption)
            .padding(.top, 4)
        }
    }

    private func addToFavorites(_ entry: TextureEntry) {
        settingsStore.update { settings in
            guard !settings.textureCycleOrder.contains(entry.id) else { return }
            settings.textureCycleOrder.append(entry.id)
        }
    }

    private func removeFromFavorites(_ entry: TextureEntry) {
        settingsStore.update { settings in
            settings.textureCycleOrder.removeAll { $0 == entry.id }
        }
    }

    private func confirmDeleteTexture(_ entry: TextureEntry) {
        let alert = NSAlert()
        alert.messageText = String(format: String(localized: "TextureDeleteConfirmTitle"), entry.name)
        alert.informativeText = String(localized: "TextureDeleteConfirmSubtitle")
        alert.alertStyle = .warning
        alert.addButton(withTitle: String(localized: "ActionDeleteButton"))
        alert.addButton(withTitle: String(localized: "ActionCancelButton"))
        if alert.runModal() == .alertFirstButtonReturn {
            textureManager.deleteTexture(entry)
            settingsStore.update { settings in
                settings.textureCycleOrder.removeAll { $0 == entry.id }
                for (displayID, activeID) in settings.activeTextureByDisplayID where activeID == entry.id {
                    settings.activeTextureByDisplayID.removeValue(forKey: displayID)
                }
            }
        }
    }

    private func showRenameAlert(for entry: TextureEntry) {
        let alert = NSAlert()
        alert.messageText = String(localized: "TextureRenameAlertTitle")
        alert.informativeText = String(localized: "TextureRenameAlertSubtitle")
        alert.addButton(withTitle: String(localized: "ActionSaveButton"))
        alert.addButton(withTitle: String(localized: "ActionCancelButton"))
        let textField = NSTextField(string: entry.name)
        textField.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = textField
        let response = AlertPresentation.runModalOnCursorScreen(alert)
        if response == .alertFirstButtonReturn {
            let newName = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !newName.isEmpty {
                textureManager.renameTexture(entry, to: newName)
            }
        }
    }
}

private struct FavoriteDropDelegate: DropDelegate {
    let target: TextureEntry
    @Binding var draggedID: UUID?
    let favorites: [TextureEntry]
    let settingsStore: AppSettingsStore

    func performDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        guard let draggedID, draggedID != target.id,
              let toIndex = favorites.firstIndex(where: { $0.id == target.id }) else { return }
        settingsStore.update { settings in
            var order = settings.textureCycleOrder
            guard let fromIndex = order.firstIndex(of: draggedID) else { return }
            let item = order.remove(at: fromIndex)
            order.insert(item, at: min(toIndex, order.count))
            settings.textureCycleOrder = order
        }
    }
}

private struct TextureThumbnailTile: View {
    let entry: TextureEntry
    let image: NSImage?
    let onRename: () -> Void
    let onDelete: () -> Void
    let onEdit: (() -> Void)?

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.12))
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 72, height: 54)
                        .clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
                if entry.kind == .procedural {
                    VStack {
                        HStack {
                            Spacer()
                            Image(systemName: "chevron.left.forwardslash.chevron.right")
                                .font(.caption2)
                                .padding(4)
                                .background(.ultraThinMaterial, in: Circle())
                        }
                        Spacer()
                    }
                    .padding(4)
                }
            }
            .frame(width: 72, height: 54)
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.12), lineWidth: 0.5))
            Text(entry.name)
                .font(.caption2)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 6) {
                if let onEdit {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                } else {
                    Button(action: onRename) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                }
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 92)
    }
}
