import Foundation
import MunkiReportLib

// MARK: - Helper Functions

func getVersion() -> String {
    return Preferences.pref("Version") as? String ?? "unknown"
}

func getReceiptInfo() -> [String: String] {
    var out = ["PackageVersion": "", "InstallDate": "", "PackageFileName": ""]
    guard let receipt = PlistHelper.readPlist(atPath: Constants.receiptPlistPath) as? [String: Any] else {
        return out
    }
    if let v = receipt["PackageVersion"] { out["PackageVersion"] = "\(v)" }
    if let v = receipt["InstallDate"] { out["InstallDate"] = "\(v)" }
    if let v = receipt["PackageFileName"] { out["PackageFileName"] = "\(v)" }
    return out
}

// MARK: - Command Line Parsing

struct Options {
    var version = false
    var showConfig = false
    var scriptsOnly = false
    var uploadOnly = false
    var forceAll = false
    var forceModules: String?
    var removePython2 = false
    var uninstallMunkireport = false
}

func parseArguments() -> Options {
    var opts = Options()
    var args = CommandLine.arguments.dropFirst()

    while let arg = args.first {
        args = args.dropFirst()
        switch arg {
        case "--version", "-V":
            opts.version = true
        case "--show-config":
            opts.showConfig = true
        case "--scriptsonly", "-S":
            opts.scriptsOnly = true
        case "--uploadonly", "-U":
            opts.uploadOnly = true
        case "--forceall", "-A":
            opts.forceAll = true
        case "--force", "-F":
            if let next = args.first {
                opts.forceModules = String(next)
                args = args.dropFirst()
            }
        case "--remove-python2":
            opts.removePython2 = true
        case "--uninstall-munkireport":
            opts.uninstallMunkireport = true
        case "-h", "--help":
            printUsage()
            exit(0)
        default:
            break
        }
    }
    return opts
}

func printUsage() {
    print("""
    Usage: munkireport-runner [OPTIONS]

      --version, -V            Print the version and exit
      --show-config            Print the current configuration and exit
      --scriptsonly, -S        Run postflight scripts only
      --uploadonly, -U         Skip scripts and only upload cache files
      --forceall, -A           Force all cache files to upload
      --force, -F <modules>   Force specified module(s) to upload
      --remove-python2         Remove legacy Python 2 installation
      --uninstall-munkireport  Fully uninstall MunkiReport
      -h, --help               Display this help message
    """)
}

// MARK: - Main

func main() {
    let options = parseArguments()
    let fm = FileManager.default

    // --version
    if options.version {
        print("MunkiReport-PHP (https://github.com/munkireport/munkireport-php)")
        print("Version: \(getVersion())")
        if fm.fileExists(atPath: Constants.receiptPlistPath) {
            print("PKG version: \(getReceiptInfo()["PackageVersion"] ?? "")")
        }
        exit(0)
    }

    // Root check
    if getuid() != 0 {
        Display.displayError("You must run this as root!")
        exit(0)
    }

    // --show-config
    if options.showConfig {
        let receiptInfo = getReceiptInfo()
        Preferences.printConfig()
        print("")
        print("     MunkiReport Version: \(getVersion())")
        if fm.fileExists(atPath: Constants.receiptPlistPath) {
            print(" MunkiReport PKG Version: \(receiptInfo["PackageVersion"] ?? "")")
            print("    MunkiReport PKG Name: \(receiptInfo["PackageFileName"] ?? "")")
            print("MunkiReport Install Date: \(receiptInfo["InstallDate"] ?? "")")
        }
        print("")
        print("         Agent runtime: Swift (native)")
        print("")
        let reportItems = Preferences.pref("ReportItems")
        print("         Modules enabled:")
        if let items = reportItems as? [String: Any] {
            for (key, value) in items.sorted(by: { $0.key < $1.key }) {
                print("           \(key): \(value)")
            }
        }
        exit(0)
    }

    // --remove-python2
    if options.removePython2 {
        let python2Binary = "/usr/local/munkireport/munkireport-python2"
        let python2Framework = "/Library/MunkiReport/Python.framework/Versions/2.7/"

        if fm.fileExists(atPath: python2Binary) || fm.fileExists(atPath: python2Framework) {
            Display.displayDetail("Removing MunkiReport's Python 2 installation...")
            print("Removing MunkiReport's Python 2 installation...")
            try? fm.removeItem(atPath: python2Binary)
            try? fm.removeItem(atPath: python2Framework)
            Display.displayDetail("Complete")
            print("Complete")
        } else {
            Display.displayDetail("MunkiReport's Python 2 not detected")
            print("MunkiReport's Python 2 not detected")
        }
        exit(0)
    }

    // --uninstall-munkireport
    if options.uninstallMunkireport {
        Display.displayDetail("Uninstalling MunkiReport...")
        print("Uninstalling MunkiReport...")

        let filesToRemove = [
            "/Library/LaunchDaemons/com.github.munkireport.runner.plist",
            "/usr/local/munki/postflight",
            "/usr/local/munki/report_broken_client",
            "/var/db/receipts/com.github.munkireport.plist",
            "/var/db/receipts/com.github.munkireport.bom",
            "/Library/Preferences/MunkiReport.plist",
        ]
        let dirsToRemove = [
            "/Library/MunkiReport/",
            "/usr/local/munkireport/",
        ]

        for file in filesToRemove {
            if fm.fileExists(atPath: file) {
                try? fm.removeItem(atPath: file)
            }
        }
        for dir in dirsToRemove {
            if fm.fileExists(atPath: dir) {
                try? fm.removeItem(atPath: dir)
            }
        }

        Display.displayDetail("Completed uninstallation of MunkiReport")
        print("Completed uninstallation of MunkiReport")
        exit(0)
    }

    // Configure syslog if needed
    if Preferences.pref("LogToSyslog") as? Bool == true {
        Logging.configureSyslog()
    }

    // Force upload settings
    let forceUpload: String?
    if options.forceAll {
        forceUpload = "FORCE_UPLOAD_ALL"
    } else if let modules = options.forceModules {
        forceUpload = modules
    } else {
        forceUpload = nil
    }

    let runtype = "auto"
    Display.verbose = 3

    // Reset error/warning logs
    Logging.rotateErrors()
    Logging.rotateWarnings()

    // Main runner
    Display.displayDetail("## Starting MunkiReport run")

    // Check for legacy Python 2
    if fm.fileExists(atPath: "/usr/local/munkireport/munkireport-python2") ||
       fm.fileExists(atPath: "/Library/MunkiReport/Python.framework/Versions/2.7/bin/python") {
        Display.displayDetail(String(repeating: "*", count: 63))
        Display.displayDetail("#! Warning: MunkiReport's Python 2 detected!")
        Display.displayDetail("#! This is no longer used by MunkiReport and should be removed!")
        Display.displayDetail(String(repeating: "*", count: 63))
    }

    // Run postflight scripts (unless --uploadonly)
    if options.uploadOnly {
        Display.displayDetail("# Skipping the execution of MunkiReport scripts")
    } else {
        let execPath = CommandLine.arguments[0]
        let scriptDir = URL(fileURLWithPath: execPath)
            .deletingLastPathComponent()
            .appendingPathComponent("scripts")
            .path
        let resolvedScriptDir = (scriptDir as NSString).resolvingSymlinksInPath
        ScriptRunner.runDir(scriptDir: resolvedScriptDir, runtype: runtype)
    }

    // Collect hardware info
    var hardwareInfo = SystemInfo.getHardwareInfo()
    hardwareInfo["computer_name"] = SystemInfo.getComputerName()
    hardwareInfo["cpu"] = SystemInfo.getCPUInfo()
    hardwareInfo["cpu_arch"] = SystemInfo.getCPUArch()
    hardwareInfo["hostname"] = SystemInfo.getHostname()
    hardwareInfo["os_version"] = SystemInfo.getOSVersion()
    hardwareInfo["buildversion"] = SystemInfo.getBuildVersion()

    var serial = (hardwareInfo["serial_number"] as? String) ?? "NO_SERIAL"

    // Retry if no serial
    if serial == "NO_SERIAL" {
        hardwareInfo = SystemInfo.getHardwareInfo()
        serial = (hardwareInfo["serial_number"] as? String) ?? "NO_SERIAL"
    }

    // Serialize hardware info as plist data, then to string for hashing
    let hwInfoPlistData = PlistHelper.writePlistToData(hardwareInfo) ?? Data()
    let hwInfoPlistString = String(data: hwInfoPlistData, encoding: .utf8) ?? ""

    // Collect report info
    let consoleUser = SystemInfo.getConsoleUser()
    let reportInfo: [String: Any] = [
        "console_user": consoleUser,
        "long_username": SystemInfo.getLongUsername(consoleUser),
        "uid": SystemInfo.getUID(consoleUser),
        "runtype": runtype,
        "runstate": "done",
        "uptime": SystemInfo.getUptime(),
    ]

    let reportInfoPlistData = PlistHelper.writePlistToData(reportInfo) ?? Data()
    let reportInfoPlistString = String(data: reportInfoPlistData, encoding: .utf8) ?? ""

    // Build items dictionary
    var items: [String: [String: Any]] = [
        "machine": [
            "hash": md5String(hwInfoPlistString),
            "data": hwInfoPlistString,
        ],
        "reportdata": [
            "hash": md5String(reportInfoPlistString),
            "data": reportInfoPlistString,
        ],
    ]

    // Upload cache files (unless --scriptsonly)
    if options.scriptsOnly {
        Display.displayDetail("# Skipping uploading cache files to MunkiReport server")
    } else {
        let configItems = (Preferences.pref("ReportItems") as? [String: String]) ?? [:]

        for (key, val) in configItems {
            Display.displayDetail("Requesting \(key)")
            items[key] = ["path": val]
        }

        do {
            try ReportCommon.process(serial: serial, items: &items, forceUpload: forceUpload)
        } catch {
            Display.displayError("Process failed: \(error)")
        }
    }

    ReportCommon.finishRun()
}

// MARK: - Utility

func md5String(_ input: String) -> String {
    guard let data = input.data(using: .utf8) else { return "" }

    var digest = [UInt8](repeating: 0, count: 16)
    _ = data.withUnsafeBytes { ptr in
        CC_MD5(ptr.baseAddress, CC_LONG(data.count), &digest)
    }
    return digest.map { String(format: "%02x", $0) }.joined()
}

import CommonCrypto

// Run
main()
