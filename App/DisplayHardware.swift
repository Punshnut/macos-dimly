// MARK: - Display Hardware
// Thin wrapper around CoreGraphics/IOKit for enumerating and describing displays.
import Foundation
import CoreGraphics
import CoreGraphics.CGDirectDisplay
import CoreGraphics.CGDisplayConfiguration
import Darwin
import IOKit
import IOKit.graphics

/// Describes a single display's best-effort identifying and descriptive info.
struct DisplayInfo: Identifiable, Equatable {
    let displayID: CGDirectDisplayID
    let uuid: String?
    let serialNumber: Int?
    let name: String?
    let isBuiltin: Bool
    let isExternal: Bool
    let resolution: String
    let refreshRateHz: Double?

    /// Stable identifier used across sessions (UUID, serial, or fallback to display ID).
    var stableIdentity: String {
        if let uuid { return uuid }
        if let serialNumber { return "serial-\(serialNumber)" }
        return "display-\(displayID)"
    }

    /// `Identifiable` conformance uses the stable identity.
    var id: String { stableIdentity }
}

/// Protocol allowing the display manager to be tested by injecting a fake hardware backend.
protocol DisplayHardwareProviding: AnyObject, Sendable {
    /// Returns active CoreGraphics display IDs.
    func activeDisplayIDs() -> [CGDirectDisplayID]
    /// Builds a `DisplayInfo` for a given display ID.
    func displayInfo(for id: CGDirectDisplayID) -> DisplayInfo
    /// Registers a callback for display changes and returns an opaque token.
    func registerCallback(_ callback: @escaping (CGDirectDisplayID, CGDisplayChangeSummaryFlags) -> Void) -> AnyObject
    /// Unregisters a callback token produced by `registerCallback`.
    func unregisterCallback(_ token: AnyObject)
}

/// CoreGraphics/IOKit-backed hardware reader.
final class DisplayHardware: DisplayHardwareProviding, @unchecked Sendable {
    private final class CallbackBox {
        let handler: (CGDirectDisplayID, CGDisplayChangeSummaryFlags) -> Void
        init(_ handler: @escaping (CGDirectDisplayID, CGDisplayChangeSummaryFlags) -> Void) { self.handler = handler }
    }

    /// Returns the list of active display IDs from CoreGraphics.
    func activeDisplayIDs() -> [CGDirectDisplayID] {
        let maxDisplays: UInt32 = 16
        var activeDisplays = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var displayCount: UInt32 = 0
        let status = CGGetActiveDisplayList(maxDisplays, &activeDisplays, &displayCount)
        guard status == .success else { return [] }
        return Array(activeDisplays.prefix(Int(displayCount)))
    }

    /// Fetches identifying metadata for the given display.
    func displayInfo(for id: CGDirectDisplayID) -> DisplayInfo {
        let uuid = Self.displayUUID(for: id)
        let serial = CGDisplaySerialNumber(id)
        let builtIn = CGDisplayIsBuiltin(id) == 1
        let resolution = Self.resolutionString(for: id)
        let refresh = Self.refreshRate(for: id)
        let name = Self.displayName(for: id)

        return DisplayInfo(
            displayID: id,
            uuid: uuid?.uuidString,
            serialNumber: serial == 0 ? nil : Int(serial),
            name: name,
            isBuiltin: builtIn,
            isExternal: !builtIn,
            resolution: resolution,
            refreshRateHz: refresh
        )
    }

    /// Registers the CGDisplay reconfiguration callback.
    func registerCallback(_ callback: @escaping (CGDirectDisplayID, CGDisplayChangeSummaryFlags) -> Void) -> AnyObject {
        let box = CallbackBox(callback)
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(box).toOpaque())
        CGDisplayRegisterReconfigurationCallback(Self.reconfigurationCallback, pointer)
        return box
    }

    /// Removes a previously registered callback.
    func unregisterCallback(_ token: AnyObject) {
        let pointer = UnsafeMutableRawPointer(Unmanaged.passUnretained(token).toOpaque())
        CGDisplayRemoveReconfigurationCallback(Self.reconfigurationCallback, pointer)
    }

    // MARK: - Helpers

    /// Best-effort lookup for a display UUID using private CoreGraphics symbol.
    private static func displayUUID(for id: CGDirectDisplayID) -> UUID? {
        typealias Fn = @convention(c) (CGDirectDisplayID) -> Unmanaged<CFUUID>?
        guard
            let lib = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY),
            let symbol = dlsym(lib, "CGDisplayCreateUUIDFromDisplayID")
        else { return nil }
        let fn = unsafeBitCast(symbol, to: Fn.self)
        guard let cfUuid = fn(id)?.takeRetainedValue() else { return nil }
        let string = CFUUIDCreateString(kCFAllocatorDefault, cfUuid) as String
        return UUID(uuidString: string)
    }

    private static let reconfigurationCallback: CGDisplayReconfigurationCallBack = { displayID, flags, userInfo in
        guard let userInfo else { return }
        let box = Unmanaged<CallbackBox>.fromOpaque(userInfo).takeUnretainedValue()
        box.handler(displayID, flags)
    }

    /// Returns a localized resolution string (with a scaled suffix if needed).
    private static func resolutionString(for id: CGDirectDisplayID) -> String {
        guard let mode = CGDisplayCopyDisplayMode(id) else { return String(localized: "Unknown") }
        let width = Int(mode.width)
        let height = Int(mode.height)
        let scaling = mode.pixelWidth != mode.width || mode.pixelHeight != mode.height
        let scaleSuffix = scaling ? String(localized: "ScaledSuffix") : ""
        return "\(width)×\(height)\(scaleSuffix)"
    }

    /// Returns the refresh rate in Hz if it is meaningful (> 1 Hz).
    private static func refreshRate(for id: CGDirectDisplayID) -> Double? {
        guard let mode = CGDisplayCopyDisplayMode(id) else { return nil }
        let hz = mode.refreshRate
        return hz > 1 ? hz : nil
    }

    /// Attempts to read a user-friendly display name via IOKit/EDID.
    private static func displayName(for id: CGDirectDisplayID) -> String? {
        // Best-effort using IOKit to read the preferred product name from EDID.
        guard let servicePort = ioServicePort(for: id) else { return nil }
        defer { IOObjectRelease(servicePort) }

        let options = IOOptionBits(kIODisplayOnlyPreferredName)
        guard let info = IODisplayCreateInfoDictionary(servicePort, options).takeRetainedValue() as? [String: Any] else {
            return nil
        }
        if let names = info[kDisplayProductName as String] as? [String: Any],
           let first = names.values.compactMap({ $0 as? String }).first {
            return first
        }
        if let product = info[kDisplayProductID as String] as? Int {
            return String(format: String(localized: "DisplayNameUnknownFormat"), product)
        }
        return nil
    }

    // MARK: - IOService helpers

    /// Finds the matching IODisplay service port for a display ID.
    static func ioServicePort(for displayID: CGDirectDisplayID) -> io_service_t? {
        guard let matching = IOServiceMatching("IODisplayConnect") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        let targetVendor = CGDisplayVendorNumber(displayID)
        let targetProduct = CGDisplayModelNumber(displayID)
        let targetSerial = CGDisplaySerialNumber(displayID)

        while case let service = IOIteratorNext(iterator), service != 0 {
            let vendor = ioRegistryUInt32(service, key: kDisplayVendorID as CFString)
            let product = ioRegistryUInt32(service, key: kDisplayProductID as CFString)
            let serial = ioRegistryUInt32(service, key: kDisplaySerialNumber as CFString)

            let vendorMatches = vendor == targetVendor
            let productMatches = product == targetProduct
            let serialMatches = targetSerial == 0 || serial == targetSerial

            if vendorMatches && productMatches && serialMatches {
                return service
            }
            IOObjectRelease(service)
        }
        return nil
    }

    /// Reads a UInt32 registry property (or 0 if missing).
    private static func ioRegistryUInt32(_ service: io_service_t, key: CFString) -> UInt32 {
        guard let value = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?.takeRetainedValue() else {
            return 0
        }
        if let number = value as? NSNumber {
            return number.uint32Value
        }
        return 0
    }
}
