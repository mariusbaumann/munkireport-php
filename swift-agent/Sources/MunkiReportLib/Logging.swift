import Foundation
import os.log

public final class Logging {
    private static let maxLogSize: UInt64 = 1_000_000 // ~1MB
    private static var logToSyslog = false
    private static let osLog = OSLog(subsystem: Constants.bundleIDString, category: "agent")

    private static let errorsFile = "\(Constants.logDir)/errors.log"
    private static let warningsFile = "\(Constants.logDir)/warnings.log"

    public static func configureSyslog() {
        logToSyslog = true
    }

    public static func logError(_ msg: String) {
        appendToLog(msg)
        appendToFile(errorsFile, message: msg)
        if logToSyslog {
            os_log(.error, log: osLog, "%{public}@", msg)
        }
    }

    public static func logWarning(_ msg: String) {
        appendToLog(msg)
        appendToFile(warningsFile, message: msg)
        if logToSyslog {
            os_log(.default, log: osLog, "%{public}@", msg)
        }
    }

    public static func logDetail(_ msg: String) {
        appendToLog(msg)
        if logToSyslog {
            os_log(.info, log: osLog, "%{public}@", msg)
        }
    }

    public static func rotateMainLog() {
        rotateFile(Constants.logFile)
    }

    public static func rotateErrors() {
        rotateFile(errorsFile)
    }

    public static func rotateWarnings() {
        rotateFile(warningsFile)
    }

    private static func appendToLog(_ msg: String) {
        appendToFile(Constants.logFile, message: msg)
    }

    private static func appendToFile(_ path: String, message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(timestamp) \(message)\n"

        let fm = FileManager.default
        if !fm.fileExists(atPath: path) {
            // Ensure directory exists
            let dir = (path as NSString).deletingLastPathComponent
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
            fm.createFile(atPath: path, contents: nil)
        }

        if let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            if let data = line.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        }
    }

    private static func rotateFile(_ path: String) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path),
              let attrs = try? fm.attributesOfItem(atPath: path),
              let size = attrs[.size] as? UInt64,
              size > maxLogSize else { return }

        let rotatedPath = path + ".1"
        try? fm.removeItem(atPath: rotatedPath)
        try? fm.moveItem(atPath: path, toPath: rotatedPath)
    }
}
