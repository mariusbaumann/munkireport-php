import Foundation
import SystemConfiguration

public enum SystemInfo {

    public static func getHardwareInfo() -> [String: Any] {
        let arch = getCPUArch()
        var cmd: [String]
        if arch.contains("arm") {
            cmd = ["/usr/bin/arch", "-arm64", "/usr/sbin/system_profiler", "SPHardwareDataType", "-xml"]
        } else {
            cmd = ["/usr/sbin/system_profiler", "SPHardwareDataType", "-xml"]
        }

        guard let output = runCommand(cmd) else { return [:] }
        guard let data = output.data(using: .utf8),
              let plist = PlistHelper.readPlist(fromData: data) as? [[String: Any]],
              let firstItem = plist.first,
              let items = firstItem["_items"] as? [[String: Any]],
              let hardware = items.first else {
            return [:]
        }
        return hardware
    }

    public static func getComputerName() -> String {
        return runCommand(["/usr/sbin/scutil", "--get", "ComputerName"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public static func getCPUInfo() -> String {
        return runCommand(["/usr/sbin/sysctl", "-n", "machdep.cpu.brand_string"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public static func getCPUArch() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let version = withUnsafePointer(to: &sysinfo.version) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }

        // Parse RELEASE_ARM64 or RELEASE_X86_64 from kernel version
        let pattern = "RELEASE_([iA-Z1-9]+)(_\\d+)?"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: version, range: NSRange(version.startIndex..., in: version)),
              let range = Range(match.range(at: 1), in: version) else {
            return "unknown"
        }
        return String(version[range]).lowercased()
    }

    public static func getHostname() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        return withUnsafePointer(to: &sysinfo.nodename) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(_SYS_NAMELEN)) {
                String(cString: $0)
            }
        }
    }

    public static func getOSVersion(onlyMajorMinor: Bool = false) -> String {
        // Set SYSTEM_VERSION_COMPAT to 0 to get real version
        setenv("SYSTEM_VERSION_COMPAT", "0", 1)
        guard let output = runCommand(["/usr/bin/sw_vers", "-productVersion"])?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return ""
        }
        if onlyMajorMinor {
            let components = output.split(separator: ".")
            return components.prefix(2).joined(separator: ".")
        }
        return output
    }

    public static func getBuildVersion() -> String {
        return runCommand(["/usr/bin/sw_vers", "-buildVersion"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    public static func getUptime() -> Int {
        guard let output = runCommand(["/usr/sbin/sysctl", "-n", "kern.boottime"]) else { return -1 }

        // Parse "{ sec = 1234567890, usec = 0 } ..."
        let pattern = "sec = (\\d+),"
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: output, range: NSRange(output.startIndex..., in: output)),
              let range = Range(match.range(at: 1), in: output),
              let bootSec = Int(output[range]) else {
            return -1
        }

        let up = Int(Date().timeIntervalSince1970) - bootSec
        return up > 0 ? up : -1
    }

    public static func getConsoleUser() -> String {
        let user = SCDynamicStoreCopyConsoleUser(nil, nil, nil)
        return (user as String?) ?? ""
    }

    public static func getLongUsername(_ username: String) -> String {
        guard !username.isEmpty,
              let pw = getpwnam(username) else { return "" }
        return String(cString: pw.pointee.pw_gecos)
    }

    public static func getUID(_ username: String) -> uid_t {
        guard !username.isEmpty,
              let pw = getpwnam(username) else { return 0 }
        return pw.pointee.pw_uid
    }

    // MARK: - Private

    private static func runCommand(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: args[0])
        if args.count > 1 {
            process.arguments = Array(args[1...])
        }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }
}
