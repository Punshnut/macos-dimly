// MARK: - True Tone Manager
// Controls per-display True Tone via private DisplayServices symbols.
import Foundation
import CoreGraphics
import Darwin
import OSLog

/// Per-display True Tone availability and control.
@MainActor
final class TrueToneManager: ObservableObject {
    @Published private(set) var availableByDisplayID: [String: Bool] = [:]
    @Published private(set) var enabledByDisplayID: [String: Bool] = [:]

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "TrueTone")

    private typealias TrueToneAvailFn  = @convention(c) (CGDirectDisplayID) -> Bool
    private typealias TrueToneGetFn    = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Bool>) -> Int32
    private typealias TrueToneSetFn    = @convention(c) (CGDirectDisplayID, Bool) -> Int32

    private static let trueToneAvailable: TrueToneAvailFn? = dsSymbol("DisplayServicesGetTrueToneAvailable")
    private static let trueToneGet:       TrueToneGetFn?   = dsSymbol("DisplayServicesGetTrueToneEnabled")
    private static let trueToneSet:       TrueToneSetFn?   = dsSymbol("DisplayServicesSetTrueToneEnabled")

    private static func dsSymbol<T>(_ name: String) -> T? {
        guard let address = DisplayHardware.displayServicesHandleAddress,
              let handle = UnsafeMutableRawPointer(bitPattern: address),
              let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    /// Probes True Tone availability and current state for each display.
    func refresh(for displays: [DisplayInfo]) {
        for display in displays {
            let avail = Self.trueToneAvailable?(display.displayID) ?? false
            availableByDisplayID[display.stableIdentity] = avail
            if avail, let getFn = Self.trueToneGet {
                var enabled = false
                if getFn(display.displayID, &enabled) == 0 {
                    enabledByDisplayID[display.stableIdentity] = enabled
                }
            }
        }
    }

    /// Returns whether True Tone is hardware-available for the given display.
    func isTrueToneAvailable(for display: DisplayInfo) -> Bool {
        availableByDisplayID[display.stableIdentity] ?? false
    }

    /// Returns whether True Tone is currently enabled for the given display.
    func isTrueToneEnabled(for display: DisplayInfo) -> Bool {
        enabledByDisplayID[display.stableIdentity] ?? false
    }

    /// Enables or disables True Tone for a display.
    func setTrueTone(_ enabled: Bool, for display: DisplayInfo) {
        guard let setFn = Self.trueToneSet else { return }
        let result = setFn(display.displayID, enabled)
        if result == 0 {
            enabledByDisplayID[display.stableIdentity] = enabled
        } else {
            logger.error("True Tone set failed for \(display.stableIdentity, privacy: .public): \(result, privacy: .public)")
        }
    }
}
