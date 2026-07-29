import Foundation

public enum CollectorError: Error, CustomStringConvertible {
    case unknownModule(String)
    case writeFailed(String)

    public var description: String {
        switch self {
        case .unknownModule(let name): return "Unknown collector: \(name)"
        case .writeFailed(let path): return "Could not write \(path)"
        }
    }
}

/// Paths to munki's report and log files, as configured in the ManagedInstalls domain.
public enum MunkiPaths {
    static let defaultInstallDir = "/Library/Managed Installs"
    private static let managedInstallsDomain = "ManagedInstalls" as CFString

    static func munkiPref(_ key: String) -> String? {
        guard let value = CFPreferencesCopyAppValue(key as CFString, managedInstallsDomain) as? String,
              !value.isEmpty else {
            return nil
        }
        return value
    }

    public static var managedInstallDir: String {
        return munkiPref("ManagedInstallDir") ?? defaultInstallDir
    }

    public static var installReportPath: String {
        return (managedInstallDir as NSString).appendingPathComponent("ManagedInstallReport.plist")
    }

    public static var installLogPath: String {
        if let logFile = munkiPref("LogFile") {
            return logFile.replacingOccurrences(of: "ManagedSoftwareUpdate.log", with: "Install.log")
        }
        return (managedInstallDir as NSString).appendingPathComponent("Logs/Install.log")
    }
}

public enum Collectors {

    public static let available = [
        "disk_report", "managedinstalls", "mdm_status",
        "munkireport", "network_shares", "softwareupdate",
    ]

    public static func run(module: String, cacheDir: String) throws {
        switch module {
        case "munkireport":
            try collectMunkiReport(cacheDir: cacheDir)
        case "managedinstalls":
            try collectManagedInstalls(cacheDir: cacheDir)
        case "disk_report":
            try collectDiskReport(cacheDir: cacheDir)
        case "mdm_status":
            try write(MDMStatus.collect(), to: path(cacheDir, "mdm_status.plist"))
        case "network_shares":
            try write(NetworkShares.collect(), to: path(cacheDir, "network_shares.plist"))
        case "softwareupdate":
            try write(SoftwareUpdate.collect(), to: path(cacheDir, "softwareupdate.plist"))
        default:
            throw CollectorError.unknownModule(module)
        }
    }

    // MARK: - munkireport

    /// Filters MANAGED_INSTALL_REPORT.plist down to the run metadata munkireport tracks.
    static func collectMunkiReport(cacheDir: String) throws {
        let out = buildMunkiReport(from: readInstallReport())
        try write(out, to: (cacheDir as NSString).appendingPathComponent("munkireport.plist"))
    }

    static func buildMunkiReport(from report: [String: Any]) -> [String: Any] {
        let keys = ["EndTime", "StartTime", "ManifestName", "ManagedInstallVersion",
                    "Errors", "Warnings", "RunType"]

        var out: [String: Any] = [:]
        for key in keys {
            guard let value = report[key], isTruthy(value) else { continue }

            // Munki lists missing catalogs once per section (installs, removals,
            // managed updates), so the same entry shows up several times.
            if key == "Errors" || key == "Warnings" {
                if let list = value as? [String] {
                    out[key] = uniquePreservingOrder(list)
                } else {
                    out[key] = value
                }
            } else {
                out[key] = value
            }
        }

        return out
    }

    // MARK: - managedinstalls

    /// Filters MANAGED_INSTALL_REPORT.plist down to the items munki installed, removed or queued.
    static func collectManagedInstalls(cacheDir: String) throws {
        let out = buildManagedInstalls(report: readInstallReport(), log: readInstallLog())
        try write(out, to: (cacheDir as NSString).appendingPathComponent("managedinstalls.plist"))
    }

    static func buildManagedInstalls(report: [String: Any], log: [String]) -> [String: Any] {
        var list: [String: [String: Any]] = [:]

        if let items = itemDicts(report["ManagedInstalls"]) {
            addItems(items, to: &list, status: "installed", type: "munki", log: log)
        }
        if let items = itemDicts(report["AppleUpdates"]) {
            addItems(items, to: &list, status: "pending_install", type: "applesus", log: nil)
        }
        if let items = itemDicts(report["ProblemInstalls"]) {
            addItems(items, to: &list, status: "install_failed", type: "munki", log: nil)
        }
        if let items = itemDicts(report["ItemsToRemove"]) {
            addItems(items, to: &list, status: "pending_removal", type: "munki", log: nil)
        }
        if let items = report["RemovedItems"] as? [Any], !items.isEmpty {
            addRemovedItems(items, to: &list, log: log)
        }
        if let items = itemDicts(report["ItemsToInstall"]) {
            addItems(items, to: &list, status: "pending_install", type: "munki", log: nil)
        }

        // Update the list with the results of this run
        if let results = itemDicts(report["RemovalResults"]) {
            applyRemovalResults(results, to: &list)
        }
        if let results = itemDicts(report["InstallResults"]) {
            applyInstallResults(results, to: &list)
        }

        var out: [String: Any] = [:]
        for (key, value) in list {
            out[key] = value
        }
        return out
    }

    private static let itemKeys = ["display_name", "installed_version", "installed_size",
                                   "version_to_install", "installed", "note"]

    /// Add items to the list and set their status
    private static func addItems(
        _ items: [[String: Any]],
        to list: inout [String: [String: Any]],
        status: String,
        type: String,
        log: [String]?
    ) {
        for item in items {
            guard let name = itemName(item) else { continue }

            var entry = filterItem(item)
            if let log = log, !log.isEmpty {
                if let timestamp = installTimestamp(for: item, name: name, log: log) {
                    entry["timestamp"] = timestamp
                }
            }

            entry["status"] = status
            entry["type"] = type
            list[name] = entry
        }
    }

    /// Add removed items to the list and set their status
    private static func addRemovedItems(
        _ items: [Any],
        to list: inout [String: [String: Any]],
        log: [String]
    ) {
        for item in items {
            // Munki reports removals as plain names, but has used dicts as well
            let name: String
            if let stringItem = item as? String {
                name = stringItem
            } else if let dictItem = item as? [String: Any], let dictName = itemName(dictItem) {
                name = dictName
            } else {
                continue
            }

            var entry: [String: Any] = [
                "name": name,
                "status": "removed",
                "installed": false,
                "display_name": name,
                "type": "munki",
            ]

            // Try to get the removal time from The Log™
            if !log.isEmpty {
                let search = " Removal of \(name): SUCCESSFUL"
                if let line = log.first(where: { $0.contains(search) }) {
                    let datePart = line.components(separatedBy: " Removal of ")[0]
                    entry["timestamp"] = stringToTime(datePart)
                }
            }

            list[name] = entry
        }
    }

    private static func applyRemovalResults(
        _ results: [[String: Any]],
        to list: inout [String: [String: Any]]
    ) {
        for item in results {
            guard let name = item["name"] as? String else { continue }

            // Sometimes an item is only in RemovalResults, so we may have to add it here
            var entry = list[name] ?? [:]

            if let time = item["time"] as? Date {
                entry["timestamp"] = String(Int(time.timeIntervalSince1970))
            }

            if intValue(item["status"]) == 0 {
                entry["installed"] = false
                entry["status"] = "uninstalled"
            } else {
                entry["status"] = "uninstall_failed"
            }

            entry["type"] = "munki"

            if (entry["display_name"] as? String)?.isEmpty ?? true {
                entry["display_name"] = item["display_name"] ?? name
            }

            list[name] = entry
        }
    }

    private static func applyInstallResults(
        _ results: [[String: Any]],
        to list: inout [String: [String: Any]]
    ) {
        for item in results {
            guard let name = itemName(item) else { continue }

            var entry = list[name] ?? [:]

            if let time = item["time"] as? Date {
                entry["timestamp"] = String(Int(time.timeIntervalSince1970))
            }

            if intValue(item["status"]) == 0 {
                entry["installed"] = true
                entry["status"] = "install_succeeded"
            } else {
                entry["status"] = "install_failed"
            }

            list[name] = entry
        }
    }

    /// Only return the keys the server stores
    private static func filterItem(_ item: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for key in itemKeys {
            // Not all objects have all these attributes
            if let value = item[key] {
                out[key] = value
            }
        }
        return out
    }

    /// Try to get the install time from The Log™
    private static func installTimestamp(for item: [String: Any], name: String, log: [String]) -> String? {
        guard let version = item["installed_version"] as? String else { return nil }

        // Search for display name by default, if that fails search by name
        let displayName = item["display_name"] as? String
        let searchName = (displayName?.isEmpty == false) ? displayName! : name

        let search = " Install of \(searchName)-\(version): SUCCESSFUL"
        guard let line = log.first(where: { $0.contains(search) }) else { return nil }

        let datePart = line.components(separatedBy: " Install of ")[0]
        return stringToTime(datePart)
    }

    // MARK: - disk_report

    /// Writes the list of volumes reported by diskutil
    static func collectDiskReport(cacheDir: String) throws {
        let volumes = DiskReport.collect()
        try write(volumes, to: (cacheDir as NSString).appendingPathComponent("disk.plist"))
    }

    // MARK: - Reading munki's files

    static func readInstallReport() -> [String: Any] {
        let path = MunkiPaths.installReportPath

        guard FileManager.default.fileExists(atPath: path) else {
            print("\(path) is missing.")
            return [:]
        }
        guard let report = PlistHelper.readPlist(atPath: path) as? [String: Any] else {
            Display.displayWarning("Error creating plist from \(path)")
            return [:]
        }
        return report
    }

    /// Reads Install.log newest line first, which is the order the timestamp lookups expect.
    static func readInstallLog() -> [String] {
        let path = MunkiPaths.installLogPath

        guard FileManager.default.fileExists(atPath: path) else {
            print("\(path) is missing.")
            return []
        }
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else {
            Display.displayWarning("Could not read \(path)")
            return []
        }
        return contents.components(separatedBy: "\n").reversed()
    }

    // MARK: - Helpers

    /// Returns a UTC timestamp from a local time zone string
    static func stringToTime(_ dateTime: String) -> String {
        let trimmed = dateTime.trimmingCharacters(in: .whitespaces)
        if trimmed == "0" || trimmed.isEmpty {
            return ""
        }

        let formats = [
            "yyyy-MM-dd HH:mm:ss.SSSXXXXX",  // Munki 7 and newer: 2025-07-20 07:22:52.533-05:00
            "MMM dd yyyy HH:mm:ss Z",        // Munki 6 and older: Jul 06 2025 06:19:55 -0500
        ]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return String(Int(date.timeIntervalSince1970))
            }
        }

        return dateTime
    }

    static func uniquePreservingOrder(_ seq: [String]) -> [String] {
        var seen = Set<String>()
        return seq.filter { seen.insert($0).inserted }
    }

    /// Prefer the Apple software update product key over the item name
    private static func itemName(_ item: [String: Any]) -> String? {
        if let productKey = item["productKey"] as? String, !productKey.isEmpty {
            return productKey
        }
        return item["name"] as? String
    }

    private static func itemDicts(_ value: Any?) -> [[String: Any]]? {
        guard let items = value as? [[String: Any]], !items.isEmpty else { return nil }
        return items
    }

    private static func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? -1 }
        return -1
    }

    /// Mirrors python's truthiness check, so empty values are left out of the report
    private static func isTruthy(_ value: Any) -> Bool {
        if let string = value as? String { return !string.isEmpty }
        if let array = value as? [Any] { return !array.isEmpty }
        if let dict = value as? [String: Any] { return !dict.isEmpty }
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.intValue != 0 }
        return true
    }

    static func path(_ cacheDir: String, _ filename: String) -> String {
        return (cacheDir as NSString).appendingPathComponent(filename)
    }

    static func write(_ contents: Any, to path: String) throws {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: dir, withIntermediateDirectories: true, attributes: nil
        )

        guard let data = PlistHelper.writePlistToData(contents) else {
            throw CollectorError.writeFailed(path)
        }
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            throw CollectorError.writeFailed("\(path): \(error.localizedDescription)")
        }
    }
}
