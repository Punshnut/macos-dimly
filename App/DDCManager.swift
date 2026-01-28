// MARK: - DDC/CI Orchestration
// Encapsulates best-effort DDC power commands and probes external panel capability.
import Foundation
import Combine
import CoreGraphics
import IOKit
import IOKit.graphics
import IOKit.i2c
import OSLog

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

enum DDCPowerCommand: String, Codable {
    case standby = "Standby"
    case wake = "Wake"
}

struct DDCState: Equatable {
    var status: DDCSupportStatus
    var lastError: String?
    var lastCommand: DDCPowerCommand?
    var lastCommandAt: Date?
}

/// Handles best-effort DDC/CI commands and per-display capability probing.
@MainActor
final class DDCManager: ObservableObject {
    @Published private(set) var states: [String: DDCState] = [:] // stableIdentity -> state

    private let displayManager: DisplayManager
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Dimly", category: "DDC")

    init(displayManager: DisplayManager) {
        self.displayManager = displayManager
        probeAll()
        // Re-probe whenever displays change.
        displayManager.$displays.sink { [weak self] _ in
            self?.probeAll()
        }
        .store(in: &cancellables)
    }

    // MARK: - Public API

    func probeAll() {
        for display in displayManager.displays {
            probe(display)
        }
    }

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

    // MARK: - Private

    private var cancellables: Set<AnyCancellable> = []

    private func probe(_ display: DisplayInfo) {
        if display.isBuiltin {
            setState(DDCState(status: .notSupported, lastError: String(localized: "Internal panel"), lastCommand: nil, lastCommandAt: nil), for: display)
            return
        }

        // IOI2CInterfaceOpen can block on some panels; do it off the main actor and marshal the result back.
        Task.detached(priority: .utility) { [display, weak self] in
            let result = Self.probeDisplaySynchronously(display)
            await self?.setState(result, for: display)
        }
    }

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

    private func handleFailure(_ error: Error, display: DisplayInfo, action: String) {
        logger.error("DDC \(action, privacy: .public) failed for \(display.stableIdentity, privacy: .public): \(error.localizedDescription, privacy: .public)")
        updateState(for: display, status: .notSupported, lastError: error.localizedDescription, lastCommand: nil)
    }

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

    nonisolated private static func openConnection(for displayID: CGDirectDisplayID) -> Result<IOI2CConnectRef, Error> {
        guard let service = DisplayHardware.ioServicePort(for: displayID) else {
            return .failure(DDCError.serviceUnavailable)
        }
        defer { IOObjectRelease(service) }

        var connect: IOI2CConnectRef?
        let status = IOI2CInterfaceOpen(service, IOOptionBits(0), &connect)
        guard status == kIOReturnSuccess, let connect else {
            return .failure(DDCError.openFailed(status))
        }
        return .success(connect)
    }

    nonisolated private static func close(_ connection: IOI2CConnectRef) {
        IOI2CInterfaceClose(connection, IOOptionBits(0))
    }

    nonisolated private static func sendVCPCommand(connection: IOI2CConnectRef, code: UInt8, value: UInt16) -> Result<Void, Error> {
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

    nonisolated private static func checksum(for bytes: [UInt8]) -> UInt8 {
        // DDC checksum: sum of slave address (0x6E) + bytes + checksum == 0 (mod 256)
        let sum = 0x6E + bytes.reduce(0) { $0 + Int($1) }
        return UInt8((256 - (sum % 256)) % 256)
    }
}

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
