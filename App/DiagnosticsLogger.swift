// MARK: - Diagnostics Logger
// File logger used alongside unified logging.
import Foundation

/// Small thread-safe logger for local diagnostics.
final class DiagnosticsLogger: @unchecked Sendable {
    static let shared = DiagnosticsLogger()

    private let queue = DispatchQueue(label: "com.punshnut.dimly.diaglog")
    private let heartbeatQueue = DispatchQueue(label: "com.punshnut.dimly.diaglog.heartbeat")
    private let handle: FileHandle?
    private let logURL: URL
    private var uiHeartbeat: DispatchSourceTimer?
    private var bgHeartbeat: DispatchSourceTimer?

    private init() {
        let logsDir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("Dimly", isDirectory: true)
        try? FileManager.default.createDirectory(at: logsDir, withIntermediateDirectories: true)
        logURL = logsDir.appendingPathComponent("dimly-app.log")

        // Clear on each launch so captures stay short and relevant.
        try? "".write(to: logURL, atomically: true, encoding: .utf8)

        handle = try? FileHandle(forWritingTo: logURL)
        if handle == nil {
            print("[Dimly] Failed to open log file at \(logURL.path)")
        }

        writeHeader()
    }

    /// Starts periodic heartbeat log entries on main and background queues.
    func startHeartbeat(interval: TimeInterval = 5) {
        if uiHeartbeat == nil {
            let timer = DispatchSource.makeTimerSource(queue: .main)
            timer.schedule(deadline: .now() + interval, repeating: interval)
            timer.setEventHandler { [weak self] in
                self?.log("heartbeat-main", category: "heartbeat")
            }
            timer.resume()
            uiHeartbeat = timer
        }

        if bgHeartbeat == nil {
            let timer = DispatchSource.makeTimerSource(queue: heartbeatQueue)
            timer.schedule(deadline: .now() + interval, repeating: interval)
            timer.setEventHandler { [weak self] in
                self?.log("heartbeat-bg", category: "heartbeat")
            }
            timer.resume()
            bgHeartbeat = timer
        }
    }

    /// Writes a timestamped line to the log file.
    func log(_ message: String, category: String = "general") {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] [\(category)] \(message)\n"
        guard let data = line.data(using: .utf8) else { return }
        queue.async { [handle] in
            handle?.seekToEndOfFile()
            handle?.write(data)
            try? handle?.synchronize()
        }
    }

    /// Writes an app/version header at the start of a log file.
    private func writeHeader() {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let header = "=== Dimly log start v\(version) (\(build)) ===\n"
        if let data = header.data(using: .utf8) {
            queue.async { [handle] in
                handle?.write(data)
                try? handle?.synchronize()
            }
        }
    }

    /// File URL for the current diagnostics log.
    var logFileURL: URL {
        logURL
    }
}
