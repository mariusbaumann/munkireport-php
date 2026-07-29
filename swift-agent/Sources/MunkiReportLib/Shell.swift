import Foundation

/// Runs external commands and returns their output.
public enum Shell {

    public struct Result {
        public let stdout: Data
        public let stderr: Data
        public let status: Int32

        /// stdout as text, replacing anything that is not valid UTF-8
        public var text: String {
            return String(decoding: stdout, as: UTF8.self)
        }

        public var succeeded: Bool {
            return status == 0
        }
    }

    public static func run(_ launchPath: String, _ arguments: [String]) -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: launchPath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        do {
            try process.run()
        } catch {
            Display.displayWarning("Error running \(launchPath): \(error)")
            return Result(stdout: Data(), stderr: Data(), status: -1)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return Result(stdout: stdoutData, stderr: stderrData, status: process.terminationStatus)
    }

    /// Runs a command with a -plist style argument and parses its output
    public static func plist(_ launchPath: String, _ arguments: [String]) -> Any? {
        let result = run(launchPath, arguments)
        guard result.succeeded else {
            let stderr = String(decoding: result.stderr, as: UTF8.self)
            Display.displayWarning(
                "Error running \(launchPath) \(arguments.joined(separator: " ")), stderr: \(stderr)"
            )
            return nil
        }
        return PlistHelper.readPlist(fromData: result.stdout)
    }

    public static func plistDict(_ launchPath: String, _ arguments: [String]) -> [String: Any] {
        return plist(launchPath, arguments) as? [String: Any] ?? [:]
    }
}
