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

    /// Applies the given filter to a display via gamma LUT manipulation.
    func applyFilter(_ filter: DisplayFilter, to display: DisplayInfo) {
        let displayID = display.displayID
        switch filter {

        case .standard, .grayscale:
            // .grayscale is kept in the enum only for legacy-settings decode compat.
            // True channel-mixing desaturation is not achievable via per-channel LUTs;
            // use Color Profile → "Black & White" for that instead.
            CGDisplayRestoreColorSyncSettings()
            activeFilter[display.stableIdentity] = .standard

        case .invert, .warmth, .cool:
            let (r, g, b) = Self.tables(for: filter)
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
                activeFilter[display.stableIdentity] = filter
            } else {
                logger.error("Gamma LUT failed for \(display.stableIdentity, privacy: .public): \(result.rawValue, privacy: .public)")
            }
        }
    }

    /// Re-applies all stored filters; call after sleep/wake or color profile change.
    func restoreAll(for displays: [DisplayInfo]) {
        for display in displays {
            let filter = activeFilter[display.stableIdentity] ?? .standard
            if filter != .standard {
                applyFilter(filter, to: display)
            }
        }
    }

    // MARK: - Gamma table generation

    private static func tables(for filter: DisplayFilter) -> ([Float], [Float], [Float]) {
        // Entries are in the display's gamma-encoded domain (0 → 1).
        // Per-channel LUTs can only remap — they cannot cross-mix channels.
        let n = tableSize
        let id = (0..<n).map { Float($0) / Float(n - 1) }

        switch filter {
        case .standard, .grayscale:
            return (id, id, id)

        case .invert:
            // Mirror: encoded 1.0 → 0.0 and vice versa.
            let inv = (0..<n).map { Float(n - 1 - $0) / Float(n - 1) }
            return (inv, inv, inv)

        case .warmth:
            // Shift white point warmer by pulling blue down ~18%.
            // Red/green stay at identity so no hue shift in the mid-tones.
            let cool = id.map { min(max($0 * 0.82, 0), 1) }
            return (id, id, cool)

        case .cool:
            // Shift white point cooler by pulling red down ~14%.
            let warm = id.map { min(max($0 * 0.86, 0), 1) }
            return (warm, id, id)
        }
    }
}
