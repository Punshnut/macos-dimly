// MARK: - Texture Renderer
// Renders a TextureEntry into a single, tileable, relief-shaded bitmap - computed once per
// parameter change (never per frame), then handed to a display's overlay window as a
// CALayer pattern color. See BlackoutManager.swift for the window/layer side of this.
import Foundation
import AppKit
import CoreGraphics

private final class TextureRenderKey: NSObject {
    let textureID: UUID
    let tileScale: Double
    let backingScale: CGFloat

    init(textureID: UUID, tileScale: Double, backingScale: CGFloat) {
        self.textureID = textureID
        self.tileScale = tileScale
        self.backingScale = backingScale
    }

    override func isEqual(_ object: Any?) -> Bool {
        guard let other = object as? TextureRenderKey else { return false }
        return textureID == other.textureID && tileScale == other.tileScale && backingScale == other.backingScale
    }

    override var hash: Int {
        var hasher = Hasher()
        hasher.combine(textureID)
        hasher.combine(tileScale)
        hasher.combine(backingScale)
        return hasher.finalize()
    }
}

@MainActor
enum TextureRenderer {
    /// Fixed, app-wide light direction used for relief shading - not user-configurable,
    /// to keep the settings UI focused on opacity/blend mode/scale rather than a full
    /// lighting rig.
    private static let lightDirection = (x: Float(-0.55), y: Float(0.55), z: Float(0.63))

    private static let tileCache = NSCache<TextureRenderKey, NSImage>()

    /// The expensive relief-shading pass, cached by texture ID alone - it depends only on
    /// the texture's diffuse/normal pixels, never on tile scale or screen backing scale, so
    /// those parameters mustn't invalidate it (that was the bug behind laggy tile-scale
    /// dragging: every tick used to re-run this whole pass from scratch).
    private static let shadedImageCache = NSCache<NSString, CGImage>()

    /// Returns a tileable `NSImage` (relief-shaded if a normal/height source is available)
    /// for the given texture, at the given tile scale and display backing scale. The shading
    /// pass is cached separately (see `shadedImage(for:manager:)`) so tile-scale/backing-scale
    /// changes only ever do a cheap resize/wrap of an already-shaded bitmap, never a re-shade.
    static func tileImage(for entry: TextureEntry, manager: TextureManager, tileScale: Double, backingScale: CGFloat) -> NSImage? {
        let key = TextureRenderKey(textureID: entry.id, tileScale: tileScale, backingScale: backingScale)
        if let cached = tileCache.object(forKey: key) { return cached }
        guard let shaded = shadedImage(for: entry, manager: manager) else { return nil }

        let targetWidth = max(1, Int(CGFloat(shaded.width) * CGFloat(tileScale)))
        let targetHeight = max(1, Int(CGFloat(shaded.height) * CGFloat(tileScale)))
        let size = NSSize(width: CGFloat(targetWidth) / backingScale, height: CGFloat(targetHeight) / backingScale)
        let tile = NSImage(size: size)
        tile.addRepresentation(NSBitmapImageRep(cgImage: shaded))
        tileCache.setObject(tile, forKey: key)
        return tile
    }

    /// The relief-shaded bitmap for a texture, computed once and cached by texture ID.
    private static func shadedImage(for entry: TextureEntry, manager: TextureManager) -> CGImage? {
        let cacheKey = entry.id.uuidString as NSString
        if let cached = shadedImageCache.object(forKey: cacheKey) { return cached }
        guard let diffuse = manager.diffuseImage(for: entry) else { return nil }

        let normalSource = manager.normalMapImage(for: entry)
        let shaded = shade(diffuse: diffuse, explicitNormalMap: normalSource, autoGenerateRelief: entry.autoGenerateRelief && normalSource == nil)
        shadedImageCache.setObject(shaded, forKey: cacheKey)
        return shaded
    }

    /// Clears every cached render (both the shaded bitmap and any tiled variants) for a
    /// texture - call this whenever a texture's underlying pixels change (e.g. reassigning
    /// its normal map), so stale shading doesn't keep showing.
    static func invalidateCache(for textureID: UUID) {
        shadedImageCache.removeObject(forKey: textureID.uuidString as NSString)
        // NSCache has no key enumeration, so the tile cache (keyed by texture+scale+backing)
        // can't be selectively evicted by texture ID alone - clear it entirely. This is cheap:
        // entries are trivial resize/wrap operations to rebuild, not re-shades.
        tileCache.removeAllObjects()
    }

    // MARK: - Relief shading

    /// Produces a Lambertian-shaded version of `diffuse` using either an explicit normal map
    /// or a normal field derived from `diffuse`'s luminance via a Sobel pass.
    private static func shade(diffuse: CGImage, explicitNormalMap: CGImage?, autoGenerateRelief: Bool) -> CGImage {
        guard explicitNormalMap != nil || autoGenerateRelief else { return diffuse }

        let width = diffuse.width, height = diffuse.height
        guard let diffusePixels = pixelBuffer(from: diffuse, width: width, height: height) else { return diffuse }

        let normalPixels: [Float]
        if let explicitNormalMap, let normalBuffer = pixelBuffer(from: explicitNormalMap, width: width, height: height) {
            normalPixels = decodeNormalMap(normalBuffer, width: width, height: height)
        } else {
            normalPixels = sobelNormals(fromLuminanceOf: diffusePixels, width: width, height: height)
        }

        var output = diffusePixels
        for y in 0..<height {
            for x in 0..<width {
                let ni = (y * width + x) * 3
                let nx = normalPixels[ni], ny = normalPixels[ni + 1], nz = normalPixels[ni + 2]
                let lambert = max(0, nx * lightDirection.x + ny * lightDirection.y + nz * lightDirection.z)
                let shade = 0.55 + 0.45 * lambert // keep midtones, avoid crushing to black
                let pi = (y * width + x) * 4
                output[pi] = UInt8(clamping: Int(Float(diffusePixels[pi]) * shade))
                output[pi + 1] = UInt8(clamping: Int(Float(diffusePixels[pi + 1]) * shade))
                output[pi + 2] = UInt8(clamping: Int(Float(diffusePixels[pi + 2]) * shade))
            }
        }

        return image(from: output, width: width, height: height) ?? diffuse
    }

    private static func pixelBuffer(from image: CGImage, width: Int, height: Int) -> [UInt8]? {
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &buffer, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }

    private static func image(from buffer: [UInt8], width: Int, height: Int) -> CGImage? {
        guard let provider = CGDataProvider(data: Data(buffer) as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// Decodes a standard tangent-space normal map (RGB -> XYZ in [-1, 1]) into a flat xyz array.
    private static func decodeNormalMap(_ buffer: [UInt8], width: Int, height: Int) -> [Float] {
        var out = [Float](repeating: 0, count: width * height * 3)
        for i in 0..<(width * height) {
            let pi = i * 4
            out[i * 3]     = Float(buffer[pi]) / 127.5 - 1
            out[i * 3 + 1] = Float(buffer[pi + 1]) / 127.5 - 1
            out[i * 3 + 2] = Float(buffer[pi + 2]) / 127.5 - 1
        }
        return out
    }

    /// Derives a normal field from luminance using a Sobel gradient - used when a texture
    /// has no explicit normal/height map ("auto-generate relief from luminance").
    private static func sobelNormals(fromLuminanceOf pixels: [UInt8], width: Int, height: Int) -> [Float] {
        func luminance(_ x: Int, _ y: Int) -> Float {
            let cx = min(max(x, 0), width - 1), cy = min(max(y, 0), height - 1)
            let pi = (cy * width + cx) * 4
            return (Float(pixels[pi]) * 0.299 + Float(pixels[pi + 1]) * 0.587 + Float(pixels[pi + 2]) * 0.114) / 255
        }

        var out = [Float](repeating: 0, count: width * height * 3)
        let strength: Float = 2.2
        for y in 0..<height {
            for x in 0..<width {
                let gx = (luminance(x + 1, y - 1) + 2 * luminance(x + 1, y) + luminance(x + 1, y + 1))
                       - (luminance(x - 1, y - 1) + 2 * luminance(x - 1, y) + luminance(x - 1, y + 1))
                let gy = (luminance(x - 1, y + 1) + 2 * luminance(x, y + 1) + luminance(x + 1, y + 1))
                       - (luminance(x - 1, y - 1) + 2 * luminance(x, y - 1) + luminance(x + 1, y - 1))
                var nx = -gx * strength, ny = -gy * strength, nz: Float = 1
                let len = sqrt(nx * nx + ny * ny + nz * nz)
                nx /= len; ny /= len; nz /= len
                let i = (y * width + x) * 3
                out[i] = nx; out[i + 1] = ny; out[i + 2] = nz
            }
        }
        return out
    }
}
