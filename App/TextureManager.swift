// MARK: - Texture Manager
// Imports, stores, and compiles texture overlays (images, SVGs, and procedural
// "Texture Playground" shaders) shared per display. Mirrors LUTManager.swift's
// storage/import/persistence pattern.
import Foundation
import AppKit
import CoreGraphics
import Metal
import OSLog

// MARK: - Model

/// How a `TextureEntry`'s pixels were produced.
enum TextureKind: String, Codable, Equatable {
    case image
    case svg
    case procedural
}

/// A texture entry in the user's library.
struct TextureEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let kind: TextureKind
    /// Filename of the base diffuse image, stored under Application Support/Dimly/Textures/
    /// (rasterized bitmap for .svg, rendered bitmap for .procedural).
    var filename: String
    /// Optional explicit normal map filename, alongside `filename`.
    var normalMapFilename: String?
    /// When true and no explicit normal map is supplied, relief shading is derived
    /// from the diffuse image's luminance (Sobel pass) instead.
    var autoGenerateRelief: Bool
    /// Source `.metal` filename for procedural entries, stored under Textures/Procedural/.
    var proceduralSourceFilename: String?
    let isBundled: Bool

    static func == (lhs: TextureEntry, rhs: TextureEntry) -> Bool { lhs.id == rhs.id }
}

/// Errors thrown while importing or compiling textures.
enum TextureImportError: LocalizedError {
    case unsupportedFormat
    case ioError(String)
    case rasterizeFailed
    case compileFailed(String)
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:    return "Unsupported texture file format."
        case .ioError(let msg):     return msg
        case .rasterizeFailed:      return "Could not rasterize the image."
        case .compileFailed(let msg): return msg
        case .renderFailed:         return "Could not render the texture."
        }
    }
}

@MainActor
final class TextureManager: ObservableObject {
    @Published private(set) var library: [TextureEntry] = []

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "TextureManager")
    private var device: MTLDevice? = MTLCreateSystemDefaultDevice()

    // MARK: - Storage

    private static var texturesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Dimly/Textures", isDirectory: true)
    }

    private static var proceduralDirectory: URL {
        texturesDirectory.appendingPathComponent("Procedural", isDirectory: true)
    }

    private static var libraryFile: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Dimly/texture_library.json")
    }

    nonisolated static let supportedImageExtensions = ["png", "jpg", "jpeg", "heic", "tiff"]

    // MARK: - Init

    init() {
        loadLibrary()
        importBundledTexturesIfNeeded()
    }

    // MARK: - Bundled textures

    private static let bundledTexturesImportedKey = "DimlyBundledTexturesImported"

    private func importBundledTexturesIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.bundledTexturesImportedKey) else { return }
        UserDefaults.standard.set(true, forKey: Self.bundledTexturesImportedKey)
        guard let examplesDir = Bundle.main.url(forResource: "ExampleTextures", withExtension: nil) else { return }
        Task.detached(priority: .background) { [weak self] in
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: examplesDir, includingPropertiesForKeys: nil
            )) ?? []
            let diffuseFiles = urls
                .filter { Self.supportedImageExtensions.contains($0.pathExtension.lowercased()) }
                .filter { !$0.lastPathComponent.lowercased().contains("_normal") }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for diffuseURL in diffuseFiles {
                let base = diffuseURL.deletingPathExtension().lastPathComponent
                let normalURL = urls.first { $0.deletingPathExtension().lastPathComponent == "\(base)_normal" }
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    _ = try? self.importBundledTexture(diffuseURL: diffuseURL, normalURL: normalURL, name: base)
                }
            }

            // Community-contributed procedural textures (see CONTRIBUTING.md#contributing-a-texture).
            let proceduralDir = examplesDir.appendingPathComponent("Procedural", isDirectory: true)
            let metalFiles = ((try? FileManager.default.contentsOfDirectory(
                at: proceduralDir, includingPropertiesForKeys: nil
            )) ?? [])
                .filter { $0.pathExtension.lowercased() == "metal" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for metalURL in metalFiles {
                guard let source = try? String(contentsOf: metalURL, encoding: .utf8) else { continue }
                let name = metalURL.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "_", with: " ")
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    _ = try? self.compileProceduralTexture(source: source, name: name)
                }
            }
        }
    }

    private func importBundledTexture(diffuseURL: URL, normalURL: URL?, name: String) throws -> TextureEntry {
        try FileManager.default.createDirectory(at: Self.texturesDirectory, withIntermediateDirectories: true)
        let destDiffuse = Self.texturesDirectory.appendingPathComponent(diffuseURL.lastPathComponent)
        if !FileManager.default.fileExists(atPath: destDiffuse.path) {
            try FileManager.default.copyItem(at: diffuseURL, to: destDiffuse)
        }
        var normalFilename: String?
        if let normalURL {
            let destNormal = Self.texturesDirectory.appendingPathComponent(normalURL.lastPathComponent)
            if !FileManager.default.fileExists(atPath: destNormal.path) {
                try FileManager.default.copyItem(at: normalURL, to: destNormal)
            }
            normalFilename = normalURL.lastPathComponent
        }
        let entry = TextureEntry(
            id: UUID(), name: name, kind: .image,
            filename: diffuseURL.lastPathComponent,
            normalMapFilename: normalFilename,
            autoGenerateRelief: normalFilename == nil,
            proceduralSourceFilename: nil,
            isBundled: true
        )
        library.append(entry)
        persistLibrary()
        return entry
    }

    // MARK: - Import (image / SVG)

    /// Imports a png/jpg/jpeg/heic/tiff/svg file into the library.
    @discardableResult
    func importTexture(from url: URL) throws -> TextureEntry {
        let ext = url.pathExtension.lowercased()
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        try FileManager.default.createDirectory(at: Self.texturesDirectory, withIntermediateDirectories: true)

        let baseName = url.deletingPathExtension().lastPathComponent
        let kind: TextureKind
        let destFilename: String
        if ext == "svg" {
            guard let rasterized = Self.rasterizeSVG(at: url) else { throw TextureImportError.rasterizeFailed }
            destFilename = Self.uniqueFilename(baseName: baseName, ext: "png", in: Self.texturesDirectory)
            let destURL = Self.texturesDirectory.appendingPathComponent(destFilename)
            guard Self.writePNG(rasterized, to: destURL) else { throw TextureImportError.rasterizeFailed }
            kind = .svg
        } else if Self.supportedImageExtensions.contains(ext) {
            let data = try { () throws -> Data in
                do { return try Data(contentsOf: url) }
                catch { throw TextureImportError.ioError("Could not read file: \(error.localizedDescription)") }
            }()
            destFilename = Self.uniqueFilename(baseName: baseName, ext: ext, in: Self.texturesDirectory)
            let destURL = Self.texturesDirectory.appendingPathComponent(destFilename)
            try data.write(to: destURL)
            kind = .image
        } else {
            throw TextureImportError.unsupportedFormat
        }

        // Auto-pair with a sibling _normal/_height file dropped alongside the same import,
        // already present in the library under a matching base name.
        let normalCandidateBase = Self.strippingSuffixConvention(baseName)
        let normalMatch = library.first {
            Self.strippingSuffixConvention(($0.filename as NSString).deletingPathExtension) == normalCandidateBase
                && $0.filename != destFilename
                && ($0.filename.lowercased().contains("_normal") || $0.filename.lowercased().contains("_height"))
        }

        let entry = TextureEntry(
            id: UUID(), name: baseName, kind: kind,
            filename: destFilename,
            normalMapFilename: normalMatch?.filename,
            autoGenerateRelief: normalMatch == nil,
            proceduralSourceFilename: nil,
            isBundled: false
        )
        library.append(entry)
        persistLibrary()
        logger.notice("Imported texture \(entry.name, privacy: .public)")
        return entry
    }

    /// Assigns or replaces a display texture entry's normal/height map from an imported file.
    func assignNormalMap(from url: URL, to entry: TextureEntry) throws {
        guard let index = library.firstIndex(where: { $0.id == entry.id }) else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        try FileManager.default.createDirectory(at: Self.texturesDirectory, withIntermediateDirectories: true)
        let ext = url.pathExtension.lowercased()
        let baseName = "\(url.deletingPathExtension().lastPathComponent)_normal"
        let destFilename = Self.uniqueFilename(baseName: baseName, ext: ext, in: Self.texturesDirectory)
        let destURL = Self.texturesDirectory.appendingPathComponent(destFilename)
        try Data(contentsOf: url).write(to: destURL)
        library[index].normalMapFilename = destFilename
        library[index].autoGenerateRelief = false
        persistLibrary()
        TextureRenderer.invalidateCache(for: entry.id)
    }

    private static func strippingSuffixConvention(_ base: String) -> String {
        for suffix in ["_diffuse", "_normal", "_height"] {
            if base.lowercased().hasSuffix(suffix) {
                return String(base.dropLast(suffix.count))
            }
        }
        return base
    }

    private static func uniqueFilename(baseName: String, ext: String, in directory: URL) -> String {
        var filename = "\(baseName).\(ext)"
        var destURL = directory.appendingPathComponent(filename)
        var counter = 1
        while FileManager.default.fileExists(atPath: destURL.path) {
            filename = "\(baseName)_\(counter).\(ext)"
            destURL = directory.appendingPathComponent(filename)
            counter += 1
        }
        return filename
    }

    /// Rasterizes an SVG document to a bitmap at a resolution suitable for tiling on Retina displays.
    private static func rasterizeSVG(at url: URL, targetSize: CGFloat = 1024) -> CGImage? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let size = NSSize(width: targetSize, height: targetSize)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        )
        guard let rep else { return nil }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        guard let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.current = context
        image.draw(in: NSRect(origin: .zero, size: size))
        return rep.cgImage
    }

    private static func writePNG(_ image: CGImage, to url: URL) -> Bool {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
            return false
        }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }

    // MARK: - Procedural (Texture Playground)

    /// Compiles a Metal Shading Language texture source and renders it once into a cached
    /// bitmap, storing the source file alongside the render so it stays editable.
    /// See docs/textures.md ("Texture Playground") for the expected fragment-function shape.
    @discardableResult
    func compileProceduralTexture(source: String, name: String, autoGenerateRelief: Bool = true, existingID: UUID? = nil) throws -> TextureEntry {
        let image = try renderProceduralPreview(source: source)
        try FileManager.default.createDirectory(at: Self.proceduralDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Self.texturesDirectory, withIntermediateDirectories: true)

        let id = existingID ?? UUID()
        let sourceFilename = "\(id.uuidString).metal"
        let imageFilename = "\(id.uuidString).png"
        try source.write(to: Self.proceduralDirectory.appendingPathComponent(sourceFilename), atomically: true, encoding: .utf8)
        guard Self.writePNG(image, to: Self.texturesDirectory.appendingPathComponent(imageFilename)) else {
            throw TextureImportError.renderFailed
        }

        let entry = TextureEntry(
            id: id, name: name, kind: .procedural,
            filename: imageFilename,
            normalMapFilename: nil,
            autoGenerateRelief: autoGenerateRelief,
            proceduralSourceFilename: sourceFilename,
            isBundled: false
        )
        if let index = library.firstIndex(where: { $0.id == id }) {
            library[index] = entry
        } else {
            library.append(entry)
        }
        persistLibrary()
        return entry
    }

    /// Compiles and renders `source` without saving anything - used for the Playground's
    /// live preview. Throws with the Metal compiler's diagnostic text on failure.
    func renderProceduralPreview(source: String) throws -> CGImage {
        guard let device else { throw TextureImportError.compileFailed("Metal is not available on this Mac.") }
        let library: MTLLibrary
        do {
            library = try device.makeLibrary(source: source, options: nil)
        } catch {
            throw TextureImportError.compileFailed(error.localizedDescription)
        }
        guard let function = library.makeFunction(name: "textureMain") else {
            throw TextureImportError.compileFailed("No 'textureMain' kernel function found.")
        }
        guard let pipeline = try? device.makeComputePipelineState(function: function) else {
            throw TextureImportError.compileFailed("Could not build the compute pipeline.")
        }

        let size = 512
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false
        )
        textureDescriptor.usage = [.shaderWrite, .shaderRead]
        guard let outputTexture = device.makeTexture(descriptor: textureDescriptor),
              let commandQueue = device.makeCommandQueue(),
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeComputeCommandEncoder() else {
            throw TextureImportError.renderFailed
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(outputTexture, index: 0)
        let threadsPerGroup = MTLSize(width: 16, height: 16, depth: 1)
        let groups = MTLSize(
            width: (size + threadsPerGroup.width - 1) / threadsPerGroup.width,
            height: (size + threadsPerGroup.height - 1) / threadsPerGroup.height,
            depth: 1
        )
        encoder.dispatchThreadgroups(groups, threadsPerThreadgroup: threadsPerGroup)
        encoder.endEncoding()
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()

        guard let cgImage = Self.cgImage(from: outputTexture) else { throw TextureImportError.renderFailed }
        return cgImage
    }

    private static func cgImage(from texture: MTLTexture) -> CGImage? {
        let width = texture.width, height = texture.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        texture.getBytes(&bytes, bytesPerRow: width * 4,
                          from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        guard let providerRef = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: providerRef, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }

    /// Documented starter stub shown when opening a new Texture Playground.
    static let proceduralTemplate = """
    #include <metal_stdlib>
    using namespace metal;

    // Small helpers for procedural grain/noise.
    inline float hash(float2 p) {
        return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
    }
    inline float noise(float2 p) {
        float2 i = floor(p), f = fract(p);
        float a = hash(i), b = hash(i + float2(1, 0));
        float c = hash(i + float2(0, 1)), d = hash(i + float2(1, 1));
        float2 u = f * f * (3.0 - 2.0 * f);
        return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
    }

    // Runs once per texel of a 512x512 tileable texture. uv is periodic in [0, tileCount).
    kernel void textureMain(texture2d<float, access::write> out [[texture(0)]],
                             uint2 gid [[thread_position_in_grid]]) {
        if (gid.x >= out.get_width() || gid.y >= out.get_height()) { return; }
        float2 uv = float2(gid) / float2(out.get_width(), out.get_height());
        float grain = noise(uv * 32.0) * 0.5 + noise(uv * 64.0 + 17.0) * 0.5;
        float3 paper = float3(0.96, 0.95, 0.92) - grain * 0.08;
        out.write(float4(paper, 1.0), gid);
    }
    """

    // MARK: - Delete / Rename

    func deleteTexture(_ entry: TextureEntry) {
        let fileURL = Self.texturesDirectory.appendingPathComponent(entry.filename)
        try? FileManager.default.removeItem(at: fileURL)
        if let normalFilename = entry.normalMapFilename {
            try? FileManager.default.removeItem(at: Self.texturesDirectory.appendingPathComponent(normalFilename))
        }
        if let sourceFilename = entry.proceduralSourceFilename {
            try? FileManager.default.removeItem(at: Self.proceduralDirectory.appendingPathComponent(sourceFilename))
        }
        library.removeAll { $0.id == entry.id }
        persistLibrary()
    }

    func renameTexture(_ entry: TextureEntry, to name: String) {
        guard let index = library.firstIndex(where: { $0.id == entry.id }) else { return }
        library[index].name = name
        persistLibrary()
    }

    // MARK: - Reading pixel data (for TextureRenderer)

    func diffuseImage(for entry: TextureEntry) -> CGImage? {
        Self.loadImage(named: entry.filename, in: Self.texturesDirectory)
    }

    /// Convenience thumbnail for library grids - same bitmap as `diffuseImage(for:)`, wrapped
    /// for SwiftUI/AppKit display.
    func thumbnailImage(for entry: TextureEntry) -> NSImage? {
        guard let cgImage = diffuseImage(for: entry) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }

    func normalMapImage(for entry: TextureEntry) -> CGImage? {
        guard let filename = entry.normalMapFilename else { return nil }
        return Self.loadImage(named: filename, in: Self.texturesDirectory)
    }

    /// Plain-text source for a procedural entry, editable in the Texture Playground.
    func proceduralSource(for entry: TextureEntry) -> String? {
        guard let filename = entry.proceduralSourceFilename else { return nil }
        return try? String(contentsOf: Self.proceduralDirectory.appendingPathComponent(filename), encoding: .utf8)
    }

    private static func loadImage(named filename: String, in directory: URL) -> CGImage? {
        let url = directory.appendingPathComponent(filename)
        guard let dataProvider = CGDataProvider(url: url as CFURL) else { return nil }
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "png":
            return CGImage(pngDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        case "jpg", "jpeg":
            return CGImage(jpegDataProviderSource: dataProvider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        default:
            return NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
    }

    // MARK: - Persistence

    private func loadLibrary() {
        guard let data = try? Data(contentsOf: Self.libraryFile),
              let decoded = try? JSONDecoder().decode([TextureEntry].self, from: data) else { return }
        library = decoded
        logger.info("Loaded \(decoded.count, privacy: .public) texture(s) from library")
    }

    private func persistLibrary() {
        try? FileManager.default.createDirectory(
            at: Self.libraryFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if let data = try? JSONEncoder().encode(library) {
            try? data.write(to: Self.libraryFile)
        }
    }
}
