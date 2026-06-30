// MARK: - LUT Manager
// Imports, stores, and applies .cube / .3dl / .lut / .csv color lookup tables per display.
import Foundation
import CoreGraphics
import OSLog

// MARK: - Model

/// Describes the dimensionality of a loaded LUT.
enum LUTDimension: Codable, Equatable {
    case lut1D(size: Int)
    case lut3D(size: Int)

    var label: String {
        switch self {
        case .lut1D(let n): return "1D · \(n)"
        case .lut3D(let n): return "3D · \(n)³"
        }
    }

    var is3D: Bool {
        if case .lut3D = self { return true }
        return false
    }
}

/// A LUT entry in the user's library.
struct LUTEntry: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    /// Filename stored under Application Support/Dimly/LUTs/ (includes extension).
    let filename: String
    let dimension: LUTDimension

    static func == (lhs: LUTEntry, rhs: LUTEntry) -> Bool { lhs.id == rhs.id }
}

// MARK: - Parser

/// Errors thrown by the LUT parser.
enum LUTParseError: LocalizedError {
    case unsupportedFormat
    case invalidSize
    case noData
    case ioError(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:   return "Unrecognized LUT format."
        case .invalidSize:         return "LUT size is out of the supported range (2–65536)."
        case .noData:              return "No color data found in the file."
        case .ioError(let msg):    return msg
        }
    }
}

/// Normalized parse output — always 256-entry R/G/B arrays ready for CGSetDisplayTransferByTable.
struct LUTParseResult {
    let title: String?
    let dimension: LUTDimension
    let r: [Float]   // 256 entries, [0..1]
    let g: [Float]
    let b: [Float]
}

struct LUTParser {

    // MARK: Entry point

    /// Dispatches to the appropriate sub-parser based on file extension.
    static func parse(data: Data, fileExtension: String) throws -> LUTParseResult {
        let ext = fileExtension.lowercased()
        let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) ?? ""
        switch ext {
        case "cube":
            return try parseCube(text)
        case "3dl":
            return try parse3dl(text)
        case "lut":
            // Resolve and some tools emit .lut files using cube syntax.
            if text.contains("LUT_3D_SIZE") || text.contains("LUT_1D_SIZE") {
                return try parseCube(text)
            }
            return try parseLut(text)
        case "csv":
            return try parseCsv(text)
        default:
            throw LUTParseError.unsupportedFormat
        }
    }

    // MARK: .cube

    private static func parseCube(_ text: String) throws -> LUTParseResult {
        var title: String?
        var is3D = false
        var lutSize: Int?
        var domainMin: (Float, Float, Float) = (0, 0, 0)
        var domainMax: (Float, Float, Float) = (1, 1, 1)
        var dataLines: [[Float]] = []
        var inDataBlock = false

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            if !inDataBlock {
                if line.uppercased().hasPrefix("TITLE") {
                    let parts = line.split(separator: " ", maxSplits: 1)
                    title = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: CharacterSet(charactersIn: "\"")) : nil
                } else if line.uppercased().hasPrefix("LUT_3D_SIZE") {
                    is3D = true
                    lutSize = Int(line.split(separator: " ").last ?? "")
                } else if line.uppercased().hasPrefix("LUT_1D_SIZE") {
                    is3D = false
                    lutSize = Int(line.split(separator: " ").last ?? "")
                } else if line.uppercased().hasPrefix("DOMAIN_MIN") {
                    let v = parseFloatTriple(line)
                    if let v { domainMin = v }
                } else if line.uppercased().hasPrefix("DOMAIN_MAX") {
                    let v = parseFloatTriple(line)
                    if let v { domainMax = v }
                } else if let floats = tryParseFloatRow(line), floats.count == 3 {
                    // First data row: header is done.
                    inDataBlock = true
                    dataLines.append(floats)
                }
            } else {
                if let floats = tryParseFloatRow(line), floats.count == 3 {
                    dataLines.append(floats)
                }
            }
        }

        guard let size = lutSize, size >= 2, size <= 65536 else { throw LUTParseError.invalidSize }
        guard !dataLines.isEmpty else { throw LUTParseError.noData }

        // Normalize domain.
        let rRange = domainMax.0 - domainMin.0
        let gRange = domainMax.1 - domainMin.1
        let bRange = domainMax.2 - domainMin.2
        var normalized: [[Float]] = dataLines.map { row in
            let nr = rRange > 0 ? (row[0] - domainMin.0) / rRange : row[0]
            let ng = gRange > 0 ? (row[1] - domainMin.1) / gRange : row[1]
            let nb = bRange > 0 ? (row[2] - domainMin.2) / bRange : row[2]
            return [clamp01(nr), clamp01(ng), clamp01(nb)]
        }

        if is3D {
            let expected = size * size * size
            if normalized.count > expected { normalized = Array(normalized.prefix(expected)) }
            let (rOut, gOut, bOut) = extractNeutralAxis(normalized, size: size)
            let dim = LUTDimension.lut3D(size: size)
            return LUTParseResult(title: title, dimension: dim,
                                  r: interpolateTo256(rOut), g: interpolateTo256(gOut), b: interpolateTo256(bOut))
        } else {
            let count = min(normalized.count, size)
            let rVals = (0..<count).map { normalized[$0][0] }
            let gVals = (0..<count).map { normalized[$0][1] }
            let bVals = (0..<count).map { normalized[$0][2] }
            let dim = LUTDimension.lut1D(size: size)
            return LUTParseResult(title: title, dimension: dim,
                                  r: interpolateTo256(rVals), g: interpolateTo256(gVals), b: interpolateTo256(bVals))
        }
    }

    // MARK: .3dl

    private static func parse3dl(_ text: String) throws -> LUTParseResult {
        var lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        guard !lines.isEmpty else { throw LUTParseError.noData }

        // Detect Autodesk/Flame variant: first line starts with "Mesh" (case-insensitive).
        if lines[0].uppercased().hasPrefix("MESH") {
            let parts = lines[0].split(separator: " ")
            // Mesh <input_depth> <output_depth> <lut_size>  or  Mesh <n> (legacy)
            var outputDepth = 12
            var lutSize = 33
            if parts.count >= 4, let od = Int(parts[2]), let ls = Int(parts[3]) {
                outputDepth = od
                lutSize = ls
            } else if parts.count >= 2, let ls = Int(parts[1]) {
                lutSize = ls
            }
            let maxVal = Float((1 << outputDepth) - 1)
            lines.removeFirst()

            var dataLines: [[Float]] = []
            for line in lines {
                if let ints = tryParseIntRow(line), ints.count >= 3 {
                    dataLines.append([Float(ints[0]) / maxVal, Float(ints[1]) / maxVal, Float(ints[2]) / maxVal])
                }
            }
            guard !dataLines.isEmpty else { throw LUTParseError.noData }
            guard lutSize >= 2, lutSize <= 256 else { throw LUTParseError.invalidSize }

            let expected = lutSize * lutSize * lutSize
            if dataLines.count > expected { dataLines = Array(dataLines.prefix(expected)) }
            let (rOut, gOut, bOut) = extractNeutralAxis(dataLines, size: lutSize)
            return LUTParseResult(title: nil, dimension: .lut3D(size: lutSize),
                                  r: interpolateTo256(rOut), g: interpolateTo256(gOut), b: interpolateTo256(bOut))
        }

        // Simple variant: first line is integer n (size), rest are integer triplets.
        if let n = Int(lines[0]), n >= 2 {
            let size = n
            lines.removeFirst()
            var rVals: [Float] = [], gVals: [Float] = [], bVals: [Float] = []
            for line in lines {
                guard let ints = tryParseIntRow(line), ints.count >= 3 else { continue }
                let maxVal: Float = ints.max().map { $0 <= 255 ? 255.0 : ($0 <= 1023 ? 1023.0 : 4095.0) } ?? 4095.0
                rVals.append(Float(ints[0]) / maxVal)
                gVals.append(Float(ints[1]) / maxVal)
                bVals.append(Float(ints[2]) / maxVal)
                if rVals.count >= size { break }
            }
            guard !rVals.isEmpty else { throw LUTParseError.noData }
            return LUTParseResult(title: nil, dimension: .lut1D(size: size),
                                  r: interpolateTo256(rVals), g: interpolateTo256(gVals), b: interpolateTo256(bVals))
        }

        throw LUTParseError.unsupportedFormat
    }

    // MARK: .lut

    private static func parseLut(_ text: String) throws -> LUTParseResult {
        var rVals: [Float] = [], gVals: [Float] = [], bVals: [Float] = []
        var maxIntSeen: Int = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            // Float row: three values all in [0..1].
            if let floats = tryParseFloatRow(line), floats.count == 3,
               floats.allSatisfy({ $0 >= 0 && $0 <= 1.01 }) {
                rVals.append(clamp01(floats[0]))
                gVals.append(clamp01(floats[1]))
                bVals.append(clamp01(floats[2]))
                continue
            }
            // Integer row.
            if let ints = tryParseIntRow(line), ints.count >= 3 {
                if let m = ints.max() { maxIntSeen = max(maxIntSeen, m) }
                rVals.append(Float(ints[0]))
                gVals.append(Float(ints[1]))
                bVals.append(Float(ints[2]))
            }
        }

        guard !rVals.isEmpty else { throw LUTParseError.noData }
        guard rVals.count >= 2, rVals.count <= 65536 else { throw LUTParseError.invalidSize }

        // Normalize integer values if needed.
        if maxIntSeen > 1 {
            let divisor: Float = maxIntSeen <= 255 ? 255 : (maxIntSeen <= 1023 ? 1023 : 4095)
            rVals = rVals.map { clamp01($0 / divisor) }
            gVals = gVals.map { clamp01($0 / divisor) }
            bVals = bVals.map { clamp01($0 / divisor) }
        }

        return LUTParseResult(title: nil, dimension: .lut1D(size: rVals.count),
                              r: interpolateTo256(rVals), g: interpolateTo256(gVals), b: interpolateTo256(bVals))
    }

    // MARK: .csv

    private static func parseCsv(_ text: String) throws -> LUTParseResult {
        var rVals: [Float] = [], gVals: [Float] = [], bVals: [Float] = []
        var maxIntSeen: Int = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }

            // Skip header rows that start with a letter.
            let first = line.unicodeScalars.first
            if let f = first, CharacterSet.letters.contains(f) { continue }

            // Detect delimiter from first data line.
            let delimiter: Character = line.contains(",") ? "," : "\t"
            let parts = line.split(separator: delimiter).map { $0.trimmingCharacters(in: .whitespaces) }

            // Accept 3 columns (R,G,B) or 4 columns (Input,R,G,B).
            let offset = parts.count == 4 ? 1 : 0
            guard parts.count >= 3 + offset else { continue }

            let r = parts[offset], g = parts[offset + 1], b = parts[offset + 2]

            if let rf = Float(r), let gf = Float(g), let bf = Float(b) {
                if rf <= 1.01 && gf <= 1.01 && bf <= 1.01 {
                    rVals.append(clamp01(rf)); gVals.append(clamp01(gf)); bVals.append(clamp01(bf))
                } else {
                    let iv = [Int(rf), Int(gf), Int(bf)]
                    if let m = iv.max() { maxIntSeen = max(maxIntSeen, m) }
                    rVals.append(Float(rf)); gVals.append(Float(gf)); bVals.append(Float(bf))
                }
            }
        }

        guard !rVals.isEmpty else { throw LUTParseError.noData }
        guard rVals.count >= 2, rVals.count <= 65536 else { throw LUTParseError.invalidSize }

        if maxIntSeen > 1 {
            let divisor: Float = maxIntSeen <= 255 ? 255 : (maxIntSeen <= 1023 ? 1023 : 4095)
            rVals = rVals.map { clamp01($0 / divisor) }
            gVals = gVals.map { clamp01($0 / divisor) }
            bVals = bVals.map { clamp01($0 / divisor) }
        }

        return LUTParseResult(title: nil, dimension: .lut1D(size: rVals.count),
                              r: interpolateTo256(rVals), g: interpolateTo256(gVals), b: interpolateTo256(bVals))
    }

    // MARK: Helpers

    /// For a 3D LUT stored in Blue-fastest (B varies fastest) order,
    /// samples the neutral-axis diagonal to extract 1D per-channel curves.
    private static func extractNeutralAxis(_ data: [[Float]], size: Int) -> ([Float], [Float], [Float]) {
        var r: [Float] = [], g: [Float] = [], b: [Float] = []
        for i in 0..<size {
            let idx = i * (size * size) + i * size + i  // R-major: R*n² + G*n + B
            if idx < data.count {
                r.append(data[idx][0])
                g.append(data[idx][1])
                b.append(data[idx][2])
            } else {
                let t = Float(i) / Float(size - 1)
                r.append(t); g.append(t); b.append(t)
            }
        }
        return (r, g, b)
    }

    /// Linearly interpolates an n-element array to exactly 256 elements.
    static func interpolateTo256(_ values: [Float]) -> [Float] {
        let n = values.count
        guard n >= 2 else {
            let v = values.first ?? 0
            return [Float](repeating: v, count: 256)
        }
        if n == 256 { return values }
        return (0..<256).map { i in
            let t = Float(i) / 255.0 * Float(n - 1)
            let lo = Int(t)
            let hi = min(lo + 1, n - 1)
            let frac = t - Float(lo)
            return values[lo] + frac * (values[hi] - values[lo])
        }
    }

    private static func tryParseFloatRow(_ line: String) -> [Float]? {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," })
        let floats = parts.compactMap { Float($0) }
        return floats.count == parts.count ? floats : nil
    }

    private static func tryParseIntRow(_ line: String) -> [Int]? {
        let parts = line.split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," })
        let ints = parts.compactMap { Int($0) }
        return ints.count == parts.count ? ints : nil
    }

    private static func parseFloatTriple(_ line: String) -> (Float, Float, Float)? {
        let parts = line.split(separator: " ").compactMap { Float($0) }
        guard parts.count >= 3 else { return nil }
        return (parts[parts.count - 3], parts[parts.count - 2], parts[parts.count - 1])
    }

    private static func clamp01(_ v: Float) -> Float { max(0, min(1, v)) }
}

// MARK: - LUTManager

/// Manages the user's LUT library, parses files, caches gamma tables, and persists entries.
@MainActor
final class LUTManager: ObservableObject {
    @Published private(set) var library: [LUTEntry] = []

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "LUTManager")
    private var tableCache: [UUID: ([Float], [Float], [Float])] = [:]

    // MARK: - Storage

    private static var lutsDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Dimly/LUTs", isDirectory: true)
    }

    private static var libraryFile: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("Dimly/lut_library.json")
    }

    // MARK: - Init

    init() {
        loadLibrary()
        importBundledLUTsIfNeeded()
    }

    // MARK: - Bundled Example LUTs

    private static let bundledLUTsImportedKey = "DimlyBundledLUTsImported"

    private func importBundledLUTsIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: Self.bundledLUTsImportedKey) else { return }
        guard let examplesDir = Bundle.main.url(forResource: "ExampleLUTs", withExtension: nil) else {
            UserDefaults.standard.set(true, forKey: Self.bundledLUTsImportedKey)
            return
        }
        Task.detached(priority: .background) { [weak self] in
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: examplesDir, includingPropertiesForKeys: nil
            )) ?? []
            let supported = ["cube", "3dl", "lut", "csv"]
            for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard supported.contains(url.pathExtension.lowercased()) else { continue }
                try? await MainActor.run { [weak self] in
                    try self?.importLUT(from: url)
                }
            }
            await MainActor.run {
                UserDefaults.standard.set(true, forKey: Self.bundledLUTsImportedKey)
            }
        }
    }

    // MARK: - Import

    /// Imports a .cube/.3dl/.lut/.csv file into the library. Returns the new entry.
    @discardableResult
    func importLUT(from url: URL) throws -> LUTEntry {
        let ext = url.pathExtension.lowercased()
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        let data = try { () throws -> Data in
            do { return try Data(contentsOf: url) }
            catch { throw LUTParseError.ioError("Could not read file: \(error.localizedDescription)") }
        }()

        let result = try LUTParser.parse(data: data, fileExtension: ext)

        try FileManager.default.createDirectory(at: Self.lutsDirectory,
                                                withIntermediateDirectories: true)

        // Generate a unique filename so duplicates don't overwrite each other.
        let baseName = url.deletingPathExtension().lastPathComponent
        var destFilename = "\(baseName).\(ext)"
        var destURL = Self.lutsDirectory.appendingPathComponent(destFilename)
        var counter = 1
        while FileManager.default.fileExists(atPath: destURL.path) {
            destFilename = "\(baseName)_\(counter).\(ext)"
            destURL = Self.lutsDirectory.appendingPathComponent(destFilename)
            counter += 1
        }

        try data.write(to: destURL)

        let suggestedName = result.title ?? baseName
        let entry = LUTEntry(id: UUID(), name: suggestedName,
                             filename: destFilename, dimension: result.dimension)
        tableCache[entry.id] = (result.r, result.g, result.b)
        library.append(entry)
        persistLibrary()
        logger.notice("Imported LUT \(entry.name, privacy: .public) [\(entry.dimension.label, privacy: .public)]")
        return entry
    }

    // MARK: - Delete

    /// Removes a LUT entry and its file. Callers must clear activeLUTByDisplayID separately.
    func deleteLUT(_ entry: LUTEntry) {
        let fileURL = Self.lutsDirectory.appendingPathComponent(entry.filename)
        try? FileManager.default.removeItem(at: fileURL)
        tableCache.removeValue(forKey: entry.id)
        library.removeAll { $0.id == entry.id }
        persistLibrary()
        logger.notice("Deleted LUT \(entry.name, privacy: .public)")
    }

    // MARK: - Rename

    func renameLUT(_ entry: LUTEntry, to name: String) {
        guard let index = library.firstIndex(where: { $0.id == entry.id }) else { return }
        library[index].name = name
        persistLibrary()
    }

    // MARK: - Gamma Tables

    /// Returns 256-point R/G/B gamma tables for the given entry (cached after first parse).
    func gammaTables(for entry: LUTEntry) -> ([Float], [Float], [Float])? {
        if let cached = tableCache[entry.id] { return cached }
        let fileURL = Self.lutsDirectory.appendingPathComponent(entry.filename)
        guard let data = try? Data(contentsOf: fileURL) else {
            logger.error("Could not read LUT file for \(entry.name, privacy: .public)")
            return nil
        }
        let ext = (entry.filename as NSString).pathExtension
        guard let result = try? LUTParser.parse(data: data, fileExtension: ext) else {
            logger.error("Could not parse LUT \(entry.name, privacy: .public)")
            return nil
        }
        let tables = (result.r, result.g, result.b)
        tableCache[entry.id] = tables
        return tables
    }

    // MARK: - Backup Support

    /// Returns the raw file bytes for a LUT entry (used when embedding in a settings backup).
    func exportEntryData(_ entry: LUTEntry) -> Data? {
        let fileURL = Self.lutsDirectory.appendingPathComponent(entry.filename)
        return try? Data(contentsOf: fileURL)
    }

    /// Restores a LUT from embedded backup data, skipping if the same UUID already exists.
    @discardableResult
    func importEntryFromData(_ data: Data, entry: LUTEntry) throws -> LUTEntry {
        if library.contains(where: { $0.id == entry.id }) { return entry }

        try FileManager.default.createDirectory(at: Self.lutsDirectory,
                                                withIntermediateDirectories: true)
        let destURL = Self.lutsDirectory.appendingPathComponent(entry.filename)
        if !FileManager.default.fileExists(atPath: destURL.path) {
            try data.write(to: destURL)
        }
        library.append(entry)
        persistLibrary()
        return entry
    }

    // MARK: - Persistence

    private func loadLibrary() {
        guard let data = try? Data(contentsOf: Self.libraryFile),
              let decoded = try? JSONDecoder().decode([LUTEntry].self, from: data) else { return }
        library = decoded
        logger.info("Loaded \(decoded.count, privacy: .public) LUT(s) from library")
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
