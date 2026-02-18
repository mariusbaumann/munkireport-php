import Foundation

public enum ScriptRunnerError: Error, CustomStringConvertible {
    case scriptNotFound(String)
    case notExecutable(String)
    case insecurePermissions(String)
    case timedOut(String)

    public var description: String {
        switch self {
        case .scriptNotFound(let path): return "Script not found: \(path)"
        case .notExecutable(let path): return "\(path) not executable"
        case .insecurePermissions(let msg): return "Insecure permissions: \(msg)"
        case .timedOut(let path): return "\(path) timed out"
        }
    }
}

public struct ScriptResult {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String
}

public enum ScriptRunner {

    public static func runScript(
        path: String,
        args: [String] = [],
        timeout: Int = 30,
        allowInsecure: Bool = false
    ) throws -> ScriptResult {
        let fm = FileManager.default

        guard fm.fileExists(atPath: path) else {
            throw ScriptRunnerError.scriptNotFound(path)
        }

        if !allowInsecure {
            try verifyFilePermissions(path)
        }

        guard fm.isExecutableFile(atPath: path) else {
            throw ScriptRunnerError.notExecutable(path)
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        let semaphore = DispatchSemaphore(value: 0)
        var didTimeout = false

        DispatchQueue.global().async {
            process.waitUntilExit()
            semaphore.signal()
        }

        let result = semaphore.wait(timeout: .now() + .seconds(timeout))
        if result == .timedOut {
            didTimeout = true
            process.terminate()
            // Give it a moment to die
            Thread.sleep(forTimeInterval: 0.5)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }

        if didTimeout {
            throw ScriptRunnerError.timedOut(path)
        }

        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

        return ScriptResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }

    public static func runDir(
        scriptDir: String,
        runtype: String,
        abort: Bool = false
    ) {
        let fm = FileManager.default

        guard fm.fileExists(atPath: scriptDir) else { return }

        let timeout = (Preferences.pref("scriptTimeOut") as? Int) ?? 30
        if timeout != 30 {
            Display.displayDetail("# Set custom script timeout to \(timeout) seconds")
        }

        let parentDir = (scriptDir as NSString).lastPathComponent
        Display.displayDetail("# Executing scripts in \(parentDir)")

        guard let files = try? fm.contentsOfDirectory(atPath: scriptDir) else { return }
        let sortedFiles = files.sorted()

        for script in sortedFiles {
            // Skip hidden files
            if script.hasPrefix(".") { continue }

            let scriptPath = (scriptDir as NSString).appendingPathComponent(script)

            // Skip directories
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: scriptPath, isDirectory: &isDir), isDir.boolValue {
                continue
            }

            do {
                Display.displayDetail("Running \(script)")
                let result = try runScript(
                    path: scriptPath,
                    args: [runtype],
                    timeout: timeout
                )

                if !result.stdout.isEmpty {
                    Display.displayDetail(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if !result.stderr.isEmpty {
                    Display.displayDetail("\(script) Error: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
                }
                if result.exitCode != 0 {
                    if abort {
                        Display.displayDetail("Aborted by \(script)")
                        exit(1)
                    } else {
                        Display.displayWarning("\(script) return code: \(result.exitCode)")
                    }
                }
            } catch ScriptRunnerError.scriptNotFound {
                // Script disappeared, skip
            } catch {
                Display.displayWarning("\(script): \(error)")
            }
        }
    }

    // MARK: - Private

    private static func verifyFilePermissions(_ path: String) throws {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: path) else {
            throw ScriptRunnerError.insecurePermissions("Cannot read attributes of \(path)")
        }

        let ownerID = attrs[.ownerAccountID] as? UInt ?? UInt.max
        let groupID = attrs[.groupOwnerAccountID] as? UInt ?? UInt.max
        let perms = (attrs[.posixPermissions] as? UInt16) ?? 0

        // Must be owned by root (0) or _munkireport
        if ownerID != 0 {
            throw ScriptRunnerError.insecurePermissions("\(path) not owned by root (owner: \(ownerID))")
        }

        // Group must be wheel (0) or admin (80)
        if groupID != 0 && groupID != 80 {
            throw ScriptRunnerError.insecurePermissions("\(path) has unexpected group owner (\(groupID))")
        }

        // Must not be world-writable
        if perms & 0o002 != 0 {
            throw ScriptRunnerError.insecurePermissions("\(path) is world-writable")
        }

        // Must not be group-writable (unless group is wheel or admin)
        if perms & 0o020 != 0 && groupID != 0 && groupID != 80 {
            throw ScriptRunnerError.insecurePermissions("\(path) is group-writable by non-admin group")
        }
    }
}
