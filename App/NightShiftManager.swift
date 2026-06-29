// MARK: - Night Shift Manager
// Controls macOS Night Shift via the private CBBlueLightClient API.
import Foundation
import Combine
import Darwin
import OSLog

/// System-global Night Shift control. Night Shift is not per-display.
@MainActor
final class NightShiftManager: ObservableObject {
    @Published private(set) var isAvailable: Bool = false
    @Published private(set) var isEnabled: Bool = false
    @Published private(set) var strength: Float = 0.5

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "NightShift")

    // dlopen handle
    private static let frameworkHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY)
    }()

    // Function typealias stubs
    private typealias ClientNewFn        = @convention(c) () -> UnsafeMutableRawPointer?
    private typealias ClientBoolFn       = @convention(c) () -> Bool
    private typealias ClientSetEnabledFn = @convention(c) (UnsafeMutableRawPointer, Bool) -> Bool
    private typealias ClientGetEnabledFn = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<ObjCBool>) -> Bool
    private typealias ClientSetStrFn     = @convention(c) (UnsafeMutableRawPointer, Float, Bool) -> Bool
    private typealias ClientGetStrFn     = @convention(c) (UnsafeMutableRawPointer, UnsafeMutablePointer<Float>) -> Bool

    private static let clientNew:        ClientNewFn?        = symbol("CBBlueLightClientNew")
    private static let clientIsSupported: ClientBoolFn?      = symbol("CBBlueLightClientIsSupported")
    private static let clientSetEnabled: ClientSetEnabledFn? = symbol("CBBlueLightClientSetEnabled")
    private static let clientGetEnabled: ClientGetEnabledFn? = symbol("CBBlueLightClientGetEnabled")
    private static let clientSetStr:     ClientSetStrFn?     = symbol("CBBlueLightClientSetStrength")
    private static let clientGetStr:     ClientGetStrFn?     = symbol("CBBlueLightClientGetStrength")

    private static func symbol<T>(_ name: String) -> T? {
        guard let handle = frameworkHandle, let sym = dlsym(handle, name) else { return nil }
        return unsafeBitCast(sym, to: T.self)
    }

    private let client: UnsafeMutableRawPointer?
    private var notificationToken: NSObjectProtocol?

    init() {
        let supported = Self.clientIsSupported?() ?? false
        isAvailable = supported
        if supported {
            client = Self.clientNew?()
        } else {
            client = nil
        }
        refresh()
        observeSystemChanges()
    }

    /// Enables or disables Night Shift.
    func setEnabled(_ on: Bool) {
        guard let client, let setFn = Self.clientSetEnabled else { return }
        _ = setFn(client, on)
        isEnabled = on
    }

    /// Sets Night Shift warmth strength (0.0 = least warm, 1.0 = most warm).
    func setStrength(_ value: Float) {
        guard let client, let setFn = Self.clientSetStr else { return }
        let clamped = max(0, min(1, value))
        _ = setFn(client, clamped, true)
        strength = clamped
    }

    /// Syncs published state from the system.
    func refresh() {
        guard let client else { return }
        if let getFn = Self.clientGetEnabled {
            var enabled: ObjCBool = false
            if getFn(client, &enabled) { isEnabled = enabled.boolValue }
        }
        if let getStr = Self.clientGetStr {
            var level: Float = 0.5
            if getStr(client, &level) { strength = level }
        }
    }

    private func observeSystemChanges() {
        let center = DistributedNotificationCenter.default()
        notificationToken = center.addObserver(
            forName: NSNotification.Name("com.apple.CoreBrightness.client.stateDidChange"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
    }
}
