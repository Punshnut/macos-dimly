// MARK: - Display Hardware
// CoreGraphics/IOKit helpers for display inventory and metadata.
import Foundation
import CoreGraphics
import CoreGraphics.CGDirectDisplay
import CoreGraphics.CGDisplayConfiguration
import Darwin
import IOKit
import IOKit.graphics

/// Display identity and descriptive metadata.
struct DisplayInfo: Identifiable, Equatable {
    let displayID: CGDirectDisplayID
    let uuid: String?
    let serialNumber: Int?
    let vendorNumber: Int
    let modelNumber: Int
    let name: String?
    let isBuiltin: Bool
    let isExternal: Bool
    let resolution: String
    let refreshRateHz: Double?

    /// Stable cross-session identifier (UUID, serial, or display ID fallback).
    var stableIdentity: String {
        if let uuid { return uuid }
        if let serialNumber { return "serial-\(serialNumber)" }
        return "display-\(displayID)"
    }

    /// `Identifiable` conformance uses the stable identity.
    var id: String { stableIdentity }
}

/// Hardware abstraction used by `DisplayManager`.
protocol DisplayHardwareProviding: AnyObject, Sendable {
    /// Returns active CoreGraphics display IDs.
    func activeDisplayIDs() -> [CGDirectDisplayID]
    /// Returns `DisplayInfo` for a given display ID.
    func displayInfo(for id: CGDirectDisplayID) -> DisplayInfo
    /// Registers a callback for display changes and returns an opaque token.
    func registerCallback(_ callback: @escaping (CGDirectDisplayID, CGDisplayChangeSummaryFlags) -> Void) -> AnyObject
    /// Unregisters a callback token produced by `registerCallback`.
    func unregisterCallback(_ token: AnyObject)
}

/// Default CoreGraphics/IOKit implementation.
final class DisplayHardware: DisplayHardwareProviding, @unchecked Sendable {
    private final class CallbackBox {
        let handler: (CGDirectDisplayID, CGDisplayChangeSummaryFlags) -> Void

        /// Stores the Swift closure so CoreGraphics can round-trip it through an opaque pointer.
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
        let vendor = CGDisplayVendorNumber(id)
        let model = CGDisplayModelNumber(id)
        let builtIn = CGDisplayIsBuiltin(id) == 1
        let resolution = Self.resolutionString(for: id)
        let refresh = Self.refreshRate(for: id)
        let name = Self.displayName(for: id)

        return DisplayInfo(
            displayID: id,
            uuid: uuid?.uuidString,
            serialNumber: serial == 0 ? nil : Int(serial),
            vendorNumber: Int(vendor),
            modelNumber: Int(model),
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

    /// Reads the current brightness (0...100) for a built-in display, if available.
    static func builtinDisplayBrightnessPercent(for displayID: CGDirectDisplayID) -> Int? {
        guard CGDisplayIsBuiltin(displayID) == 1 else { return nil }
        if let servicePort = ioServicePort(for: displayID) {
            defer { IOObjectRelease(servicePort) }
            var brightness: Float = 0
            let result = IODisplayGetFloatParameter(servicePort, 0, kIODisplayBrightnessKey as CFString, &brightness)
            if result == KERN_SUCCESS {
                let clamped = max(0, min(1, Double(brightness)))
                return Int((clamped * 100).rounded())
            }
        }

        // Apple Silicon/internal panels can fail the IODisplay path; fallback to DisplayServices.
        guard let brightness = displayServicesGetBrightness(displayID) else { return nil }
        let clamped = max(0, min(1, Double(brightness)))
        return Int((clamped * 100).rounded())
    }

    /// Sets brightness (0...100) for a built-in display.
    @discardableResult
    static func setBuiltinDisplayBrightnessPercent(_ percent: Int, for displayID: CGDirectDisplayID) -> Bool {
        guard CGDisplayIsBuiltin(displayID) == 1 else { return false }
        let clamped = Float(max(0, min(100, percent))) / 100

        if let servicePort = ioServicePort(for: displayID) {
            defer { IOObjectRelease(servicePort) }
            let result = IODisplaySetFloatParameter(servicePort, 0, kIODisplayBrightnessKey as CFString, clamped)
            if result == KERN_SUCCESS {
                return true
            }
        }

        return displayServicesSetBrightness(displayID, clamped)
    }

    /// Attempts to resolve a stable display UUID via the private CoreGraphics lookup API.
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

    /// Bridges the CoreGraphics C callback back into the boxed Swift closure.
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

    /// Reads a user-friendly display name via IOKit/EDID.
    private static func displayName(for id: CGDirectDisplayID) -> String? {
        // Prefer the localized product name exposed by IOKit when the EDID metadata is available.
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

    // MARK: - IOAVService private API (Apple Silicon DDC)

#if arch(arm64)
    typealias IOAVServiceCreateWithServiceFn =
        @convention(c) (CFAllocator?, io_service_t) -> UnsafeRawPointer?
    typealias IOAVServiceWriteI2CFn =
        @convention(c) (UnsafeRawPointer, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let ioavServiceCreateWithService: IOAVServiceCreateWithServiceFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let sym = dlsym(handle, "IOAVServiceCreateWithService") else { return nil }
        return unsafeBitCast(sym, to: IOAVServiceCreateWithServiceFn.self)
    }()

    static let ioavServiceWriteI2C: IOAVServiceWriteI2CFn? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY),
              let sym = dlsym(handle, "IOAVServiceWriteI2C") else { return nil }
        return unsafeBitCast(sym, to: IOAVServiceWriteI2CFn.self)
    }()

    /// Returns a +1 retained IOAVService ref for the given display, or nil.
    /// Caller must CFRelease when done.
    static func ioAVServiceRef(for displayID: CGDirectDisplayID) -> UnsafeRawPointer? {
        guard let createFn = ioavServiceCreateWithService else { return nil }
        let targetVendor  = CGDisplayVendorNumber(displayID)
        let targetProduct = CGDisplayModelNumber(displayID)
        let targetSerial  = CGDisplaySerialNumber(displayID)

        guard let matching = IOServiceMatching("DCPAVServiceProxy") else { return nil }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }

        while case let proxyService = IOIteratorNext(iterator), proxyService != 0 {
            defer { IOObjectRelease(proxyService) }
            if findMatchingDisplayConnect(under: proxyService,
                                          vendor: targetVendor,
                                          product: targetProduct,
                                          serial: targetSerial) != nil {
                return createFn(kCFAllocatorDefault, proxyService)
            }
        }
        return nil
    }

    /// Walks IO registry parents of `service` looking for an IODisplayConnect whose
    /// EDID vendor/product/serial matches the target. Returns the matching io_service_t
    /// (retained, caller must release), or nil. Search is bounded to 8 levels.
    private static func findMatchingDisplayConnect(
        under service: io_service_t,
        vendor: UInt32, product: UInt32, serial: UInt32
    ) -> io_service_t? {
        var current = service
        IOObjectRetain(current)
        for _ in 0..<8 {
            var parent: io_service_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard kr == KERN_SUCCESS, parent != 0 else { return nil }
            current = parent

            let nodeVendor  = ioRegistryUInt32(current, key: kDisplayVendorID as CFString)
            let nodeProduct = ioRegistryUInt32(current, key: kDisplayProductID as CFString)
            let nodeSerial  = ioRegistryUInt32(current, key: kDisplaySerialNumber as CFString)
            if nodeVendor == vendor && nodeProduct == product
                && (serial == 0 || nodeSerial == serial) {
                return current
            }
        }
        IOObjectRelease(current)
        return nil
    }
#endif

    // MARK: - DisplayServices fallback (private framework)

    private typealias DisplayServicesGetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DisplayServicesSetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let displayServicesGetBrightnessSymbol: DisplayServicesGetBrightnessFn? = {
        guard
            let address = displayServicesHandleAddress,
            let handle = UnsafeMutableRawPointer(bitPattern: address),
            let symbol = dlsym(handle, "DisplayServicesGetBrightness")
        else {
            return nil
        }
        return unsafeBitCast(symbol, to: DisplayServicesGetBrightnessFn.self)
    }()

    private static let displayServicesSetBrightnessSymbol: DisplayServicesSetBrightnessFn? = {
        guard
            let address = displayServicesHandleAddress,
            let handle = UnsafeMutableRawPointer(bitPattern: address),
            let symbol = dlsym(handle, "DisplayServicesSetBrightness")
        else {
            return nil
        }
        return unsafeBitCast(symbol, to: DisplayServicesSetBrightnessFn.self)
    }()

    private static let displayServicesHandleAddress: UInt? = {
        let candidates = [
            "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices",
            "/System/Library/PrivateFrameworks/DisplayServices.framework/Versions/A/DisplayServices"
        ]
        for path in candidates {
            if let handle = dlopen(path, RTLD_LAZY) {
                return UInt(bitPattern: handle)
            }
        }
        return nil
    }()

    /// Reads built-in brightness using private DisplayServices when IODisplay APIs fail.
    private static func displayServicesGetBrightness(_ displayID: CGDirectDisplayID) -> Float? {
        guard let getBrightness = displayServicesGetBrightnessSymbol else { return nil }
        var level: Float = 0
        let status = getBrightness(displayID, &level)
        return status == 0 ? level : nil
    }

    /// Writes built-in brightness through private DisplayServices fallback.
    private static func displayServicesSetBrightness(_ displayID: CGDirectDisplayID, _ level: Float) -> Bool {
        guard let setBrightness = displayServicesSetBrightnessSymbol else { return false }
        let status = setBrightness(displayID, level)
        return status == 0
    }
}
