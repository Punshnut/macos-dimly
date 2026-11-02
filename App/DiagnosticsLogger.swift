// MARK: - Diagnostics Logger
// File logger used alongside unified logging.
import Foundation

/// Thread-safe file logger used for local diagnostics.
final class DiagnosticsLogger: @unchecked Sendable {
    static let shared = DiagnosticsLogger()

    private let queue = DispatchQueue(label: "com.punshnut.dimly.diaglog")
    private var handle: FileHandle?
    private let logURL: URL
    private let logsDir: URL
    private let formatter = ISO8601DateFormatter()
    private let isEnabled: Bool
    private let maxFileSizeBytes: UInt64 = 2 * 1024 * 1024
    private let maxRotatedFiles = 3
    private var currentFileSizeBytes: UInt64 = 0

    /// Creates the singleton logger, resolves the log file path, and opens the active log if diagnostics are enabled.
    private init() {
        let resolvedLogsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Dimly", isDirectory: true)
        logsDir = resolvedLogsDir
        logURL = resolvedLogsDir.appendingPathComponent("dimly-app.log")

        let env = ProcessInfo.processInfo.environment
        let envEnabled = env["DIMLY_DIAGNOSTICS"] == "1"
        let defaultsEnabled = UserDefaults.standard.bool(forKey: "DiagnosticsLoggingEnabled")
#if DEBUG
        let debugEnabled = true
#else
        let debugEnabled = false
#endif
        isEnabled = debugEnabled || envEnabled || defaultsEnabled

        try? FileManager.default.createDirectory(at: resolvedLogsDir, withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        guard isEnabled else {
            handle = nil
            return
        }
        handle = try? FileHandle(forWritingTo: logURL)
        if handle == nil {
            print("[Dimly] Failed to open log file at \(logURL.path)")
            return
        }
        handle?.seekToEndOfFile()
        currentFileSizeBytes = handle?.offsetInFile ?? 0
        rotateIfNeeded(forAppending: 0)
        writeHeader()
    }

    /// Writes a timestamped line to the log file.
    func log(_ message: String, category: String = "general") {
        guard isEnabled else { return }
        let timestamp = formatter.string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async { [weak self] in
            guard let self else { return }
            self.rotateIfNeeded(forAppending: UInt64(data.count))
            self.handle?.seekToEndOfFile()
            self.handle?.write(data)
            self.currentFileSizeBytes += UInt64(data.count)
        }
    }

    /// Writes an app/version header at the start of a log file.
    private func writeHeader() {
        guard isEnabled else { return }
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let header = "=== Dimly log start v\(version) (\(build)) diagnostics=\(isEnabled) ===\n"
        if let data = header.data(using: .utf8) {
            queue.async { [weak self] in
                guard let self else { return }
                self.rotateIfNeeded(forAppending: UInt64(data.count))
                self.handle?.seekToEndOfFile()
                self.handle?.write(data)
                self.currentFileSizeBytes += UInt64(data.count)
            }
        }
    }

    /// Rotates log files once size bounds are reached.
    private func rotateIfNeeded(forAppending bytesToAppend: UInt64) {
        guard isEnabled else { return }
        guard currentFileSizeBytes + bytesToAppend > maxFileSizeBytes else { return }
        handle?.closeFile()
        handle = nil

        for index in stride(from: maxRotatedFiles, through: 1, by: -1) {
            let source = rotatedLogURL(index: index - 1)
            let destination = rotatedLogURL(index: index)
            if FileManager.default.fileExists(atPath: destination.path) {
                try? FileManager.default.removeItem(at: destination)
            }
            if FileManager.default.fileExists(atPath: source.path) {
                try? FileManager.default.moveItem(at: source, to: destination)
            }
        }

        FileManager.default.createFile(atPath: logURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: logURL)
        handle?.seekToEndOfFile()
        currentFileSizeBytes = handle?.offsetInFile ?? 0
    }

    /// Returns URL for active/rotated log files.
    private func rotatedLogURL(index: Int) -> URL {
        if index == 0 { return logURL }
        return logsDir.appendingPathComponent("dimly-app.log.\(index)")
    }

    /// File URL for the current diagnostics log.
    var logFileURL: URL {
        logURL
    }
}
