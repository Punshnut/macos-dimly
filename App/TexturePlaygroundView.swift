// MARK: - Texture Playground
// A small, playful Metal Shading Language code box for procedural textures - see
// docs/textures.md and TextureManager.compileProceduralTexture/renderProceduralPreview.
// Deliberately just a plain-text editor: no autocomplete, no linting, no project files.
import SwiftUI
import AppKit

struct TexturePlaygroundView: View {
    @ObservedObject var textureManager: TextureManager
    let engine: DimlyEngine
    let editingEntry: TextureEntry?
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var source: String
    @State private var autoGenerateRelief: Bool
    @State private var previewImage: NSImage?
    @State private var previewCGImage: CGImage?
    @State private var previewOpacity: Double = 0.5
    @State private var errorText: String?
    @State private var compileTask: Task<Void, Never>?
    @State private var isSaving = false

    init(textureManager: TextureManager, engine: DimlyEngine, editingEntry: TextureEntry?) {
        self.textureManager = textureManager
        self.engine = engine
        self.editingEntry = editingEntry
        let existingSource = editingEntry.flatMap { textureManager.proceduralSource(for: $0) }
        _name = State(initialValue: editingEntry?.name ?? String(localized: "TexturePlaygroundDefaultName"))
        _source = State(initialValue: existingSource ?? TextureManager.proceduralTemplate)
        _autoGenerateRelief = State(initialValue: editingEntry?.autoGenerateRelief ?? true)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            SettingsDivider()
            HStack(spacing: 0) {
                editor
                    .frame(minWidth: 360, maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                previewPane
                    .frame(width: 220)
            }
            SettingsDivider()
            footer
        }
        .frame(width: 720, height: 520)
        .onAppear { scheduleRecompile() }
        .onChange(of: source) { _, _ in scheduleRecompile() }
        .onChange(of: previewOpacity) { _, newValue in
            guard let previewCGImage else { return }
            engine.previewTexture(image: previewCGImage, opacity: newValue, blendMode: .normal, tileScale: 1.0)
        }
        .onDisappear {
            engine.restoreAllTextureOverlays()
        }
    }

    private var header: some View {
        HStack {
            Text(String(localized: "TexturePlaygroundTitle"))
                .font(.headline)
            Spacer()
            TextField(String(localized: "TexturePlaygroundNameFieldLabel"), text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 220)
        }
        .padding(14)
    }

    private var editor: some View {
        TextEditor(text: $source)
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(8)
    }

    private var previewPane: some View {
        VStack(spacing: 8) {
            Text(String(localized: "TexturePlaygroundPreviewLabel"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            tiledPreview
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(String(localized: "TexturePlaygroundPreviewIntensityLabel"))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(Int(previewOpacity * 100))%")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(value: $previewOpacity, in: 0...1)
                    .controlSize(.small)
            }
            Toggle(String(localized: "TexturePlaygroundReliefToggleLabel"), isOn: $autoGenerateRelief)
                .toggleStyle(.switch)
                .controlSize(.small)
                .font(.caption)
            if let errorText {
                ScrollView {
                    Text(errorText)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
            }
            Spacer()
        }
        .padding(10)
    }

    /// Shows the current preview tiled 2x2 so seams are obvious - and never goes blank on a
    /// failed compile, it just keeps showing the last successful render.
    private var tiledPreview: some View {
        Group {
            if let previewImage {
                VStack(spacing: 0) {
                    ForEach(0..<2, id: \.self) { _ in
                        HStack(spacing: 0) {
                            ForEach(0..<2, id: \.self) { _ in
                                Image(nsImage: previewImage)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 90, height: 90)
                                    .clipped()
                            }
                        }
                    }
                }
                .frame(width: 180, height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15), lineWidth: 0.5))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.secondary.opacity(0.15))
                    .frame(width: 180, height: 180)
                    .overlay(ProgressView().controlSize(.small))
            }
        }
    }

    private var footer: some View {
        HStack {
            Button(String(localized: "TexturePlaygroundCopyCodeButton")) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(source, forType: .string)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Button(String(localized: "TexturePlaygroundExportButton")) {
                exportSource()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            Spacer()
            Button(String(localized: "ActionCancelButton")) { dismiss() }
                .buttonStyle(.bordered)
                .controlSize(.small)
            Button(String(localized: "ActionSaveButton")) { save() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(previewImage == nil || isSaving)
        }
        .padding(14)
    }

    // MARK: - Compile

    /// Recompiles on a short debounce after the last keystroke; a failing compile leaves the
    /// last good preview on screen and only updates the error strip, so the window never
    /// blanks out mid-edit.
    private func scheduleRecompile() {
        compileTask?.cancel()
        compileTask = Task {
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            do {
                let image = try textureManager.renderProceduralPreview(source: source)
                await MainActor.run {
                    previewImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
                    previewCGImage = image
                    errorText = nil
                    engine.previewTexture(image: image, opacity: previewOpacity, blendMode: .normal, tileScale: 1.0)
                }
            } catch {
                await MainActor.run {
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func exportSource() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(name).metal"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? source.write(to: url, atomically: true, encoding: .utf8)
    }

    private func save() {
        isSaving = true
        do {
            _ = try textureManager.compileProceduralTexture(
                source: source, name: name.isEmpty ? String(localized: "TexturePlaygroundDefaultName") : name,
                autoGenerateRelief: autoGenerateRelief, existingID: editingEntry?.id
            )
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
        isSaving = false
    }
}
