// MARK: - DDC/CI Orchestration
// DDC power and brightness coordination for external displays.
import Foundation
import Combine
import CoreGraphics
import AppKit
import IOKit
import IOKit.graphics
import IOKit.i2c
import OSLog

/// Whether a display appears to support DDC/CI control.
enum DDCSupportStatus: String {
    case supported = "Supported"
    case notSupported = "Not Supported"
    case unknown = "Unknown"
}

extension DDCSupportStatus {
    var localizedDescription: String {
        String(localized: String.LocalizationValue(rawValue))
    }
}

/// Last DDC power command issued to a display.
enum DDCPowerCommand: String, Codable {
    case standby = "Standby"
    case wake = "Wake"
}

/// Per-display DDC status and last command metadata.
struct DDCState: Equatable {
    var status: DDCSupportStatus
    var lastError: String?
    var lastCommand: DDCPowerCommand?
    var lastCommandAt: Date?
}

/// Unified handle for an open DDC transport session.
private enum DDCConnection {
    case i2c(IOI2CConnectRef)
#if arch(arm64)
    case avService(UnsafeRawPointer) // +1 retained IOAVService CF object
#endif
}

/// Manages DDC probing plus power/brightness commands.
@MainActor
final class DDCManager: ObservableObject {
    @Published private(set) var states: [String: DDCState] = [:] // stableIdentity -> state
    @Published private(set) var brightnessLevels: [String: Int] = [:] // stableIdentity -> percent
    @Published private(set) var cableCheckDisplayIDs: Set<String> = [] // stableIdentity set

    private let displayManager: DisplayManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "DDC")
    private let probeRetryCount = 4
    private let probeRetryDelayNanoseconds: UInt64 = 450_000_000
    // Keep the transient "checking cable/DDC" state visible briefly after wake or topology changes.
    private let cableCheckWindowNanoseconds: UInt64 = 3_000_000_000
    private var probeTasks: [String: Task<Void, Never>] = [:]
    private var cableCheckClearTasks: [String: Task<Void, Never>] = [:]
    private var lastObservedExternalDisplayIDByIdentity: [String: CGDirectDisplayID] = [:]
    private var workspaceWakeToken: NSObjectProtocol?
    private var workspaceScreensWakeToken: NSObjectProtocol?

    /// Starts probing current displays and listens for changes.
    init(displayManager: DisplayManager) {
        self.displayManager = displayManager
        self.lastObservedExternalDisplayIDByIdentity = Dictionary(
            uniqueKeysWithValues: displayManager.displays
                .filter(\.isExternal)
                .map { ($0.stableIdentity, $0.displayID) }
        )
        syncBuiltinStates(with: displayManager.displays)
        probeAll(markAsCableCheck: true)
        displayManager.$displays
            .removeDuplicates()
            .sink { [weak self] displays in
                self?.reconcileForDisplayChange(displays)
                self?.syncBuiltinStates(with: displays)
                self?.probeDisplaysAddedOrReconnected(in: displays, markAsCableCheck: true)
            }
            .store(in: &cancellables)

        workspaceWakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.probeAll(markAsCableCheck: true)
            }
        }
        workspaceScreensWakeToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.screensDidWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.probeAll(markAsCableCheck: true)
            }
        }
    }

    @MainActor
    deinit {
        if let workspaceWakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceWakeToken)
        }
        if let workspaceScreensWakeToken {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceScreensWakeToken)
        }
    }

    // MARK: - Public API

    /// Probes every current display for DDC support.
    func probeAll(markAsCableCheck: Bool = false) {
        let displays = displayManager.displays
        syncBuiltinStates(with: displays)
        for display in displays where display.isExternal {
            scheduleProbe(display, retriesRemaining: probeRetryCount, markAsCableCheck: markAsCableCheck)
        }
    }

    /// Re-probes one display, typically after a failed command while unresolved.
    func refreshProbe(for display: DisplayInfo) {
        scheduleProbe(display, retriesRemaining: probeRetryCount, markAsCableCheck: false)
    }

    /// Sends a DDC standby command. Returns `true` on success.
    func standby(_ display: DisplayInfo) -> Bool {
        let result = sendPowerCommand(display, value: 0x04) // VCP 0xD6 power off
        switch result {
        case .success:
            logger.notice("DDC standby issued to \(display.stableIdentity, privacy: .public)")
            updateState(for: display, status: .supported, lastError: nil, lastCommand: .standby)
            return true
        case .failure(let error):
            handleFailure(error, display: display, action: "standby")
            return false
        }
    }

    /// Sends a DDC wake command. Returns `true` on success.
    func wake(_ display: DisplayInfo) -> Bool {
        let result = sendPowerCommand(display, value: 0x01) // VCP 0xD6 power on
        switch result {
        case .success:
            logger.notice("DDC wake issued to \(display.stableIdentity, privacy: .public)")
            updateState(for: display, status: .supported, lastError: nil, lastCommand: .wake)
            return true
        case .failure(let error):
            handleFailure(error, display: display, action: "wake")
            return false
        }
    }

    /// Sets hardware brightness over DDC/CI asynchronously (0...100).
    func setBrightness(_ percent: Int, for display: DisplayInfo, completion: @escaping (Bool) -> Void) {
        let clamped = max(0, min(100, percent))
        if states[display.stableIdentity]?.status == .notSupported {
            completion(false)
            return
        }
        Task { [weak self] in
            guard let self else { return }
            let result = await Task.detached(priority: .userInitiated) { [display, clamped] in
                Self.sendBrightnessCommandSynchronously(displayID: display.displayID, value: UInt16(clamped))
            }.value
            switch result {
            case .success:
                self.logger.notice("DDC brightness \(clamped, privacy: .public)% set for \(display.stableIdentity, privacy: .public)")
                self.updateState(for: display, status: .supported, lastError: nil, lastCommand: nil)
                self.brightnessLevels[display.stableIdentity] = clamped
                completion(true)
            case .failure(let error):
                self.handleFailure(error, display: display, action: "brightness")
                completion(false)
            }
        }
    }

    // MARK: - Private

    private var cancellables: Set<AnyCancellable> = []

    /// Keeps internal probe/state maps aligned with the current display list.
    private func reconcileForDisplayChange(_ displays: [DisplayInfo]) {
        let liveIDs = Set(displays.map(\.stableIdentity))
        let staleStateIDs = states.keys.filter { !liveIDs.contains($0) }
        for id in staleStateIDs {
            states.removeValue(forKey: id)
            brightnessLevels.removeValue(forKey: id)
            probeTasks[id]?.cancel()
            probeTasks.removeValue(forKey: id)
            cableCheckDisplayIDs.remove(id)
            cableCheckClearTasks[id]?.cancel()
            cableCheckClearTasks.removeValue(forKey: id)
        }
    }

    /// Marks built-in displays as not DDC-capable without starting probe work.
    private func syncBuiltinStates(with displays: [DisplayInfo]) {
        for display in displays where display.isBuiltin {
            let state = DDCState(
                status: .notSupported,
                lastError: String(localized: "Internal panel"),
                lastCommand: nil,
                lastCommandAt: nil
            )
            setState(state, for: display)
        }
    }

    /// Starts probe cycles only for newly added or reconnected external displays.
    private func probeDisplaysAddedOrReconnected(in displays: [DisplayInfo], markAsCableCheck: Bool) {
        let currentExternalIDByIdentity = Dictionary(
            uniqueKeysWithValues: displays
                .filter(\.isExternal)
                .map { ($0.stableIdentity, $0.displayID) }
        )
        let displaysNeedingProbe = displays.filter { display in
            guard display.isExternal else { return false }
            return lastObservedExternalDisplayIDByIdentity[display.stableIdentity] != display.displayID
        }
        lastObservedExternalDisplayIDByIdentity = currentExternalIDByIdentity
        for display in displaysNeedingProbe {
            scheduleProbe(display, retriesRemaining: probeRetryCount, markAsCableCheck: markAsCableCheck)
        }
    }

    /// Probes a single display asynchronously to avoid blocking the main actor.
    private func scheduleProbe(_ display: DisplayInfo, retriesRemaining: Int, markAsCableCheck: Bool) {
        let id = display.stableIdentity
        probeTasks[id]?.cancel()
        if display.isBuiltin {
            setState(DDCState(status: .notSupported, lastError: String(localized: "Internal panel"), lastCommand: nil, lastCommandAt: nil), for: display)
            probeTasks[id] = nil
            return
        }
        if markAsCableCheck {
            startCableCheckWindow(for: id)
        }
        setState(DDCState(status: .unknown, lastError: nil, lastCommand: nil, lastCommandAt: nil), for: display)

        probeTasks[id] = Task { [weak self] in
            guard let self else { return }
            await self.runProbeAttempt(for: display, retriesRemaining: retriesRemaining)
        }
    }

    /// Marks a display as actively being checked due to topology/wake changes.
    private func startCableCheckWindow(for id: String) {
        let window = cableCheckWindowNanoseconds
        cableCheckDisplayIDs.insert(id)
        cableCheckClearTasks[id]?.cancel()
        cableCheckClearTasks[id] = Task { [weak self] in
            try? await Task.sleep(nanoseconds: window)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.cableCheckDisplayIDs.remove(id)
                self?.cableCheckClearTasks.removeValue(forKey: id)
            }
        }
    }

    /// Runs one probe attempt and retries briefly to avoid false "not supported" during startup/reconnect.
    private func runProbeAttempt(for display: DisplayInfo, retriesRemaining: Int) async {
        let result = await Task.detached(priority: .utility) {
            Self.probeDisplaySynchronously(display)
        }.value
        guard Task.isCancelled == false else { return }

        if result.status == .supported {
            setState(result, for: display)
            probeTasks[display.stableIdentity] = nil
            return
        }

        guard retriesRemaining > 0 else {
            setState(result, for: display)
            probeTasks[display.stableIdentity] = nil
            return
        }

        setState(DDCState(status: .unknown, lastError: nil, lastCommand: nil, lastCommandAt: nil), for: display)
        try? await Task.sleep(nanoseconds: probeRetryDelayNanoseconds)
        guard Task.isCancelled == false else { return }
        await runProbeAttempt(for: display, retriesRemaining: retriesRemaining - 1)
    }

    /// Synchronous probe used off-main-thread to detect DDC availability.
    nonisolated private static func probeDisplaySynchronously(_ display: DisplayInfo) -> DDCState {
        let openResult = Self.openConnection(for: display.displayID)
        switch openResult {
        case .success(let connection):
            Self.close(connection)
            return DDCState(status: .supported, lastError: nil, lastCommand: nil, lastCommandAt: nil)
        case .failure(let error):
            return DDCState(status: .notSupported, lastError: error.localizedDescription, lastCommand: nil, lastCommandAt: nil)
        }
    }

    /// Logs a DDC failure and updates the display state.
    private func handleFailure(_ error: Error, display: DisplayInfo, action: String) {
        logger.error("DDC \(action, privacy: .public) failed for \(display.stableIdentity, privacy: .public): \(error.localizedDescription, privacy: .public)")
        updateState(for: display, status: .notSupported, lastError: error.localizedDescription, lastCommand: nil)
    }

    /// Updates state without clobbering a previously recorded command.
    @MainActor
    private func setState(_ state: DDCState, for display: DisplayInfo) {
        if var existing = states[display.stableIdentity] {
            if state.lastCommand == nil {
                existing.status = state.status
                existing.lastError = state.lastError
                states[display.stableIdentity] = existing
                return
            }
        }
        states[display.stableIdentity] = state
    }

    /// Writes status and optional command metadata into the state map.
    private func updateState(for display: DisplayInfo, status: DDCSupportStatus, lastError: String?, lastCommand: DDCPowerCommand?) {
        var updated = states[display.stableIdentity] ?? DDCState(status: status, lastError: lastError, lastCommand: nil, lastCommandAt: nil)
        updated.status = status
        updated.lastError = lastError
        if let lastCommand {
            updated.lastCommand = lastCommand
            updated.lastCommandAt = Date()
        }
        states[display.stableIdentity] = updated
    }

    // MARK: - I2C helpers

    /// Sends a VCP power command (0xD6) to a display.
    private func sendPowerCommand(_ display: DisplayInfo, value: UInt16) -> Result<Void, Error> {
        guard let state = states[display.stableIdentity], state.status == .supported else {
            return .failure(DDCError.notSupported)
        }
        let openResult = Self.openConnection(for: display.displayID)
        switch openResult {
        case .failure(let error):
            return .failure(error)
        case .success(let connection):
            defer { Self.close(connection) }
            return Self.sendVCPCommand(connection: connection, code: 0xD6, value: value)
        }
    }

    /// Sends a VCP brightness command (0x10) to a display.
    nonisolated private static func sendBrightnessCommandSynchronously(displayID: CGDirectDisplayID, value: UInt16) -> Result<Void, Error> {
        let openResult = Self.openConnection(for: displayID)
        switch openResult {
        case .failure(let error):
            return .failure(error)
        case .success(let connection):
            defer { Self.close(connection) }
            return Self.sendVCPCommand(connection: connection, code: 0x10, value: value)
        }
    }

    /// Opens a DDC transport connection for a display, routing to the correct path per architecture.
    nonisolated private static func openConnection(for displayID: CGDirectDisplayID) -> Result<DDCConnection, Error> {
#if arch(arm64)
        return openConnectionARM(for: displayID)
#else
        return openConnectionIntel(for: displayID)
#endif
    }

    /// Intel (x86_64): opens an IOI2C connection via IOFramebuffer.
    nonisolated private static func openConnectionIntel(for displayID: CGDirectDisplayID) -> Result<DDCConnection, Error> {
        guard let service = DisplayHardware.ioServicePort(for: displayID) else {
            return .failure(DDCError.serviceUnavailable)
        }
        defer { IOObjectRelease(service) }
        var connect: IOI2CConnectRef?
        let status = IOI2CInterfaceOpen(service, IOOptionBits(0), &connect)
        guard status == kIOReturnSuccess, let connect else {
            return .failure(DDCError.openFailed(status))
        }
        return .success(.i2c(connect))
    }

#if arch(arm64)
    /// Apple Silicon (arm64): opens an IOAVService connection via DCPAVServiceProxy.
    nonisolated private static func openConnectionARM(for displayID: CGDirectDisplayID) -> Result<DDCConnection, Error> {
        guard let avService = DisplayHardware.ioAVServiceRef(for: displayID) else {
            return .failure(DDCError.serviceUnavailable)
        }
        return .success(.avService(avService))
    }
#endif

    /// Closes a DDC transport connection.
    nonisolated private static func close(_ connection: DDCConnection) {
        switch connection {
        case .i2c(let ref):
            IOI2CInterfaceClose(ref, IOOptionBits(0))
#if arch(arm64)
        case .avService(let ref):
            Unmanaged<AnyObject>.fromOpaque(ref).release()
#endif
        }
    }

    /// Sends a raw VCP command over the given transport connection.
    nonisolated private static func sendVCPCommand(connection: DDCConnection, code: UInt8, value: UInt16) -> Result<Void, Error> {
        switch connection {
        case .i2c(let ref):
            return sendVCPCommandIntel(connection: ref, code: code, value: value)
#if arch(arm64)
        case .avService(let ref):
            return sendVCPCommandARM(avService: ref, code: code, value: value)
#endif
        }
    }

    /// Intel: sends a VCP command payload over IOI2C.
    nonisolated private static func sendVCPCommandIntel(connection: IOI2CConnectRef, code: UInt8, value: UInt16) -> Result<Void, Error> {
        var request = IOI2CRequest()
        request.commFlags = 0
        request.sendAddress = 0x6E
        request.sendTransactionType = IOOptionBits(kIOI2CSimpleTransactionType)
        request.replyTransactionType = IOOptionBits(kIOI2CNoTransactionType)

        var payload: [UInt8] = [
            0x51, // Destination address
            0x84, // Command: Set VCP feature
            0x03, // Message length
            code, // VCP code
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
            0 // checksum placeholder
        ]
        payload[6] = Self.checksum(for: payload)

        let sent = payload.withUnsafeBytes { buffer -> Result<Void, Error> in
            guard let baseAddress = buffer.baseAddress else {
                return .failure(DDCError.requestFailed(kIOReturnNoMemory))
            }
            request.sendBytes = UInt32(buffer.count)
            request.sendBuffer = vm_address_t(UInt(bitPattern: baseAddress))
            let result = IOI2CSendRequest(connection, IOOptionBits(0), &request)
            if result != kIOReturnSuccess {
                return .failure(DDCError.requestFailed(result))
            }
            return .success(())
        }
        return sent
    }

#if arch(arm64)
    /// Apple Silicon: sends a VCP command via IOAVServiceWriteI2C.
    nonisolated private static func sendVCPCommandARM(avService: UnsafeRawPointer, code: UInt8, value: UInt16) -> Result<Void, Error> {
        guard let writeFn = DisplayHardware.ioavServiceWriteI2C else {
            return .failure(DDCError.serviceUnavailable)
        }
        // Build the full DDC/CI frame so checksum() covers all relevant bytes.
        var fullPayload: [UInt8] = [
            0x51,                           // Destination address (becomes IOAVService dataAddress)
            0x84,                           // Set VCP Feature command
            0x03,                           // Message length
            code,                           // VCP code
            UInt8((value >> 8) & 0xFF),
            UInt8(value & 0xFF),
            0                               // Checksum placeholder
        ]
        fullPayload[6] = Self.checksum(for: fullPayload)
        // IOAVServiceWriteI2C takes chipAddress=0x37 and dataAddress=0x51 as separate
        // parameters; the data buffer is the payload minus the leading 0x51.
        var data = Array(fullPayload.dropFirst())
        let result = data.withUnsafeMutableBytes { buf -> IOReturn in
            guard let base = buf.baseAddress else { return kIOReturnNoMemory }
            return writeFn(avService, 0x37, 0x51,
                           UnsafeMutableRawPointer(mutating: base),
                           UInt32(buf.count))
        }
        return result == kIOReturnSuccess ? .success(()) : .failure(DDCError.requestFailed(result))
    }
#endif

    /// Calculates the DDC checksum required by VCP commands.
    nonisolated private static func checksum(for bytes: [UInt8]) -> UInt8 {
        // DDC checksum: sum of slave address (0x6E) + bytes + checksum == 0 (mod 256)
        let sum = 0x6E + bytes.reduce(0) { $0 + Int($1) }
        return UInt8((256 - (sum % 256)) % 256)
    }
}

/// Errors surfaced while attempting DDC communication.
enum DDCError: LocalizedError {
    case notSupported
    case serviceUnavailable
    case openFailed(kern_return_t)
    case requestFailed(kern_return_t)

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return String(localized: "DDC not supported")
        case .serviceUnavailable:
            return String(localized: "Display service unavailable")
        case .openFailed(let status):
            return String(format: String(localized: "DDCOpenFailedFormat"), String(status, radix: 16))
        case .requestFailed(let status):
            return String(format: String(localized: "DDCRequestFailedFormat"), String(status, radix: 16))
        }
    }
}
