// MARK: - Display Appearance Manager
// Per-display gamma table filters using CGSetDisplayTransferByTable.
import Foundation
import CoreGraphics
import Combine
import OSLog

/// Applies per-display appearance filters using CoreGraphics gamma tables.
/// Filters are not persistent across sleep/wake — call restoreAll() on wake.
@MainActor
final class DisplayAppearanceManager: ObservableObject {
    @Published private(set) var activeFilter: [String: DisplayFilter] = [:]

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "DisplayFilter")
    private static let tableSize: Int = 256

    // MARK: - Public API

    /// Applies the given filter to a display, optionally composing with LUT tables.
    /// When `lutTables` is provided, the filter is applied first and then mapped through the LUT
    /// in a single `CGSetDisplayTransferByTable` call.
    func applyFilter(_ filter: DisplayFilter, lutTables: ([Float], [Float], [Float])? = nil, to display: DisplayInfo) {
        let displayID = display.displayID
        switch filter {

        case .standard, .grayscale:
            // .grayscale is kept in the enum only for legacy-settings decode compat.
            // True channel-mixing desaturation is not achievable via per-channel LUTs;
            // use Color Profile → "Black & White" for that instead.
            if let lut = lutTables {
                // Standard filter = identity, so just apply LUT directly.
                applyTables(lut.0, lut.1, lut.2, to: displayID, stableID: display.stableIdentity, filter: .standard)
            } else {
                CGDisplayRestoreColorSyncSettings()
                activeFilter[display.stableIdentity] = .standard
            }

        case .invert, .warmth, .cool:
            let (fr, fg, fb) = Self.tables(for: filter)
            let (r, g, b): ([Float], [Float], [Float])
            if let lut = lutTables {
                r = Self.composeTables(fr, through: lut.0)
                g = Self.composeTables(fg, through: lut.1)
                b = Self.composeTables(fb, through: lut.2)
            } else {
                (r, g, b) = (fr, fg, fb)
            }
            applyTables(r, g, b, to: displayID, stableID: display.stableIdentity, filter: filter)
        }
    }

    /// Re-applies all stored filters; call after sleep/wake or color profile change.
    /// `lutProvider` optionally supplies LUT tables per display so filter+LUT stay composed.
    func restoreAll(for displays: [DisplayInfo], lutProvider: ((DisplayInfo) -> ([Float], [Float], [Float])?)? = nil) {
        for display in displays {
            let filter = activeFilter[display.stableIdentity] ?? .standard
            let lut = lutProvider?(display)
            if filter != .standard || lut != nil {
                applyFilter(filter, lutTables: lut, to: display)
            }
        }
    }

    // MARK: - Private helpers

    private func applyTables(_ r: [Float], _ g: [Float], _ b: [Float],
                              to displayID: CGDirectDisplayID,
                              stableID: String,
                              filter: DisplayFilter) {
        let result = r.withUnsafeBufferPointer { rBuf in
            g.withUnsafeBufferPointer { gBuf in
                b.withUnsafeBufferPointer { bBuf in
                    CGSetDisplayTransferByTable(
                        displayID,
                        UInt32(Self.tableSize),
                        rBuf.baseAddress,
                        gBuf.baseAddress,
                        bBuf.baseAddress
                    )
                }
            }
        }
        if result == .success {
            activeFilter[stableID] = filter
        } else {
            logger.error("Gamma LUT failed for \(stableID, privacy: .public): \(result.rawValue, privacy: .public)")
        }
    }

    /// Threads `filterTable` through `lutTable`: each output[i] = lut(filterTable[i]).
    private static func composeTables(_ filterTable: [Float], through lutTable: [Float]) -> [Float] {
        let n = tableSize
        let lutMax = Float(lutTable.count - 1)
        return (0..<n).map { i in
            let pos = filterTable[i] * lutMax
            let lo = Int(pos)
            let hi = min(lo + 1, lutTable.count - 1)
            let frac = pos - Float(lo)
            return lutTable[lo] * (1 - frac) + lutTable[hi] * frac
        }
    }

    // MARK: - Gamma table generation

    static func tables(for filter: DisplayFilter) -> ([Float], [Float], [Float]) {
        let n = tableSize
        let id = (0..<n).map { Float($0) / Float(n - 1) }

        switch filter {
        case .standard, .grayscale:
            return (id, id, id)

        case .invert:
            let inv = (0..<n).map { Float(n - 1 - $0) / Float(n - 1) }
            return (inv, inv, inv)

        case .warmth:
            let cool = id.map { min(max($0 * 0.82, 0), 1) }
            return (id, id, cool)

        case .cool:
            let warm = id.map { min(max($0 * 0.86, 0), 1) }
            return (warm, id, id)
        }
    }
}
