import Foundation

/// Software update, XProtect, Gatekeeper, MRT and seed program state.
public enum SoftwareUpdate {

    private static let softwareUpdateDomain = "com.apple.SoftwareUpdate"
    private static let commerceDomain = "com.apple.commerce"
    private static let applicationAccessDomain = "com.apple.applicationaccess"

    public static func collect() -> [String: Any] {
        var result: [String: Any] = [:]

        merge(&result, xprotect())
        merge(&result, softwareUpdatePrefs())
        merge(&result, updateHistory())
        merge(&result, gatekeeper())
        merge(&result, gatekeeperDisk())
        merge(&result, kextExclude())
        merge(&result, mrt())
        merge(&result, seedutil())
        merge(&result, xprotectPayloads())
        merge(&result, ddmInfo())

        // If greater than macOS 11 (Darwin 20), collect deferred macOS updates
        if darwinVersion() > 20 {
            merge(&result, deferredUpdates())
        }

        return result
    }

    // MARK: - Preference domains

    static func softwareUpdatePrefs() -> [String: Any] {
        var out: [String: Any] = [:]

        // com.apple.SoftwareUpdate
        out["skip_download_lack_space"] = bool("DidSkipBackgroundDownloadLackingDiskSpace", softwareUpdateDomain)
        out["eval_critical_if_unchanged"] = bool("EvaluateCriticalEvenIfUnchanged", softwareUpdateDomain)
        out["lastattemptsystemversion"] = value("LastAttemptSystemVersion", softwareUpdateDomain)
        out["lastbackgroundsuccessfuldate"] = time("LastBackgroundSuccessfulDate", softwareUpdateDomain)
        out["lastfullsuccessfuldate"] = time("LastFullSuccessfulDate", softwareUpdateDomain)
        out["lastrecommendedupdatesavailable"] = value("LastRecommendedUpdatesAvailable", softwareUpdateDomain)
        out["lastresultcode"] = value("LastResultCode", softwareUpdateDomain)
        out["lastsessionsuccessful"] = bool("LastSessionSuccessful", softwareUpdateDomain)
        out["lastsuccessfuldate"] = time("LastSuccessfulDate", softwareUpdateDomain)
        out["lastupdatesavailable"] = value("LastUpdatesAvailable", softwareUpdateDomain)
        out["one_time_force_scan_enabled"] = bool("OneTimeForceScanEnabled", softwareUpdateDomain)
        out["skiplocalcdn"] = bool("SkipLocalCDN", softwareUpdateDomain)
        out["recommendedupdates"] = value("RecommendedUpdates", softwareUpdateDomain)
        out["configdatainstall"] = bool("ConfigDataInstall", softwareUpdateDomain)
        out["criticalupdateinstall"] = bool("CriticalUpdateInstall", softwareUpdateDomain)
        out["automaticdownload"] = bool("AutomaticDownload", softwareUpdateDomain)
        out["inactiveupdates"] = value("InactiveUpdates", softwareUpdateDomain)
        out["catalogurl"] = value("CatalogURL", softwareUpdateDomain)
        out["automaticcheckenabled"] = bool("AutomaticCheckEnabled", softwareUpdateDomain)
        out["managed_do_it_later_deferral_count"] = value("ManagedDoItLaterDeferralCount", softwareUpdateDomain)
        out["managed_product_keys"] = value("ManagedProductKeys", softwareUpdateDomain)
        out["maximum_managed_do_it_later_deferral_count"] = value("MaximumManagedDoItLaterDeferralCount", softwareUpdateDomain)

        // com.apple.commerce
        out["auto_update"] = bool("AutoUpdate", commerceDomain)
        out["auto_update_restart_required"] = bool("AutoUpdateRestartRequired", commerceDomain)

        // com.apple.applicationaccess
        out["force_delayed_minor_updates"] = bool("forceDelayedSoftwareUpdates", applicationAccessDomain)
        out["force_delayed_major_updates"] = bool("forceDelayedMajorSoftwareUpdates", applicationAccessDomain)
        out["minor_deferred_delay"] = value("enforcedSoftwareUpdateMinorOSDeferredInstallDelay", applicationAccessDomain)
        out["major_deferred_delay"] = value("enforcedSoftwareUpdateMajorOSDeferredInstallDelay", applicationAccessDomain)
        out["allow_rapid_security_response_installation"] = bool("allowRapidSecurityResponseInstallation", applicationAccessDomain)
        out["allow_rapid_security_response_removal"] = bool("allowRapidSecurityResponseRemoval", applicationAccessDomain)

        // If greater than macOS 13 (Darwin 22), default this key if blank
        out["allow_prerelease_installation"] = bool("AllowPreReleaseInstallation", softwareUpdateDomain)
        if darwinVersion() > 21, isBlank(out["allow_prerelease_installation"]) {
            out["allow_prerelease_installation"] = 1
        }

        // Use the old enforcedSoftwareUpdateDelay key if the minor OS one is unset
        if isBlank(out["minor_deferred_delay"]) {
            out["minor_deferred_delay"] = value("enforcedSoftwareUpdateDelay", applicationAccessDomain)
        }

        // Set key defaults, for macOS 13 (Darwin 22)
        if darwinVersion() > 21, isBlank(out["allow_rapid_security_response_installation"]) {
            out["allow_rapid_security_response_installation"] = 1
        }
        if darwinVersion() > 21, isBlank(out["allow_rapid_security_response_removal"]) {
            out["allow_rapid_security_response_removal"] = 1
        }

        // Set key defaults, for macOS 11 (Darwin 20)
        if darwinVersion() > 19, isBlank(out["force_delayed_minor_updates"]) {
            out["force_delayed_minor_updates"] = 0
        }
        if darwinVersion() > 19, isBlank(out["force_delayed_major_updates"]) {
            out["force_delayed_major_updates"] = 0
        }

        return out
    }

    // MARK: - Install history

    static func updateHistory() -> [String: Any] {
        guard let entries = PlistHelper.readPlist(atPath: "/Library/Receipts/InstallHistory.plist")
                as? [[String: Any]] else {
            return [:]
        }

        var history: [[String: Any]] = []

        for entry in entries {
            let process = entry["processName"] as? String ?? ""
            guard process == "softwareupdated" || process == "Software Update" else { continue }

            var historyEntry: [String: Any] = [:]
            if let value = entry["contentType"] { historyEntry["content_type"] = value }
            if let value = entry["date"] { historyEntry["date"] = stringToTime(value) }
            if let value = entry["displayName"] { historyEntry["display_name"] = value }
            if let value = entry["displayVersion"] { historyEntry["display_version"] = value }
            if let value = entry["packageIdentifiers"] { historyEntry["package_identifiers"] = value }
            history.append(historyEntry)
        }

        return ["softwareupdate_history": history]
    }

    // MARK: - Bundle versions

    static func xprotect() -> [String: Any] {
        let candidates = [
            "/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/XProtect.meta.plist",
            "/System/Library/CoreServices/XProtect.bundle/Contents/Resources/XProtect.meta.plist",
            "/Library/Apple/System/Library/CoreServices/XProtect.bundle/Contents/Resources/XProtect.meta.plist",
        ]
        guard let path = firstExisting(candidates),
              let plist = PlistHelper.readPlist(atPath: path) as? [String: Any] else {
            return [:]
        }

        var out: [String: Any] = [:]
        if let version = plist["Version"] {
            out["xprotect_version"] = pythonString(version)
        }
        out["mrxprotect"] = modificationTime(path)
        return out
    }

    static func xprotectPayloads() -> [String: Any] {
        let path = "/Library/Apple/System/Library/CoreServices/XProtect.app/Contents/Info.plist"
        guard FileManager.default.fileExists(atPath: path),
              let plist = PlistHelper.readPlist(atPath: path) as? [String: Any] else {
            return [:]
        }

        var out: [String: Any] = [:]
        if let version = plist["Bundle version string (short)"] {
            out["xprotect_payloads_version"] = pythonString(version)
        }
        if let version = plist["CFBundleShortVersionString"] {
            out["xprotect_payloads_version"] = pythonString(version)
        }
        out["xprotect_payloads_last_modified"] = modificationTime(path)
        return out
    }

    static func gatekeeper() -> [String: Any] {
        // If less than 10.8 (Darwin 12), don't collect Gatekeeper data
        guard darwinVersion() >= 12 else { return [:] }
        return bundleVersion(
            at: "/private/var/db/gkopaque.bundle/Contents/Info.plist",
            versionKey: "gatekeeper_version",
            modifiedKey: "gatekeeper_last_modified"
        )
    }

    static func gatekeeperDisk() -> [String: Any] {
        guard darwinVersion() >= 8 else { return [:] }
        return bundleVersion(
            at: "/private/var/db/gke.bundle/Contents/Info.plist",
            versionKey: "gatekeeper_disk_version",
            modifiedKey: "gatekeeper_disk_last_modified"
        )
    }

    static func kextExclude() -> [String: Any] {
        let candidates = [
            "/System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist",
            "/Library/Apple/System/Library/Extensions/AppleKextExcludeList.kext/Contents/Info.plist",
        ]
        guard let path = firstExisting(candidates) else { return [:] }
        return bundleVersion(
            at: path,
            versionKey: "kext_exclude_version",
            modifiedKey: "kext_exclude_last_modified"
        )
    }

    static func mrt() -> [String: Any] {
        let candidates = [
            "/System/Library/CoreServices/MRT.app/Contents/Info.plist",
            "/Library/Apple/System/Library/CoreServices/MRT.app/Contents/Info.plist",
        ]
        guard let path = firstExisting(candidates) else { return [:] }
        return bundleVersion(
            at: path,
            versionKey: "mrt_version",
            modifiedKey: "mrt_last_modified"
        )
    }

    private static func bundleVersion(
        at path: String,
        versionKey: String,
        modifiedKey: String
    ) -> [String: Any] {
        guard let plist = PlistHelper.readPlist(atPath: path) as? [String: Any] else { return [:] }

        var out: [String: Any] = [:]
        if let version = plist["CFBundleShortVersionString"] {
            out[versionKey] = pythonString(version)
        }
        out[modifiedKey] = modificationTime(path)
        return out
    }

    // MARK: - Seed program

    static func seedutil() -> [String: Any] {
        var out: [String: Any] = [:]

        let seedutilPath = "/System/Library/PrivateFrameworks/Seeding.framework/Resources/seedutil"
        if FileManager.default.fileExists(atPath: seedutilPath) {
            let output = Shell.run(seedutilPath, ["current"]).text

            for line in output.components(separatedBy: "\n") {
                if line.contains("Currently enrolled in: ") {
                    if line.contains("(null)") {
                        out["program_seed"] = "0"
                    } else if line.contains("CustomerSeed") {
                        out["program_seed"] = "1"
                    } else if line.contains("DeveloperSeed") {
                        out["program_seed"] = "2"
                    } else if line.contains("PublicSeed") {
                        out["program_seed"] = "3"
                    }
                } else if line.contains("Build is seed: ") {
                    out["build_is_seed"] = toBool(strip(line, "Build is seed: "))
                } else if line.contains("NSShowFeedbackMenu: ") {
                    out["show_feedback_menu"] = toBool(strip(line, "NSShowFeedbackMenu: "))
                } else if line.contains("DisableSeedOptOut: ") {
                    out["disable_seed_opt_out"] = toBool(strip(line, "DisableSeedOptOut: "))
                } else if line.contains("CatalogURL: "), !line.contains("(null)") {
                    out["catalog_url_seed"] = strip(line, "CatalogURL: ")
                }
            }
        }

        // Check what kind of seed it is, file is only on macOS 13.4+
        let betaEnrollment = "/Users/Shared/.BetaEnrollmentData.plist"
        if FileManager.default.fileExists(atPath: betaEnrollment),
           let plist = PlistHelper.readPlist(atPath: betaEnrollment) as? [String: Any],
           let objects = plist["$objects"] as? [Any] {
            for item in objects {
                if let string = item as? String, string.contains("macOS"), string.contains("Beta") {
                    out["enrolled_seed"] = string
                }
            }
        }

        return out
    }

    // MARK: - Declarative Device Management

    /// Information about macOS 14+ DDM software updates
    static func ddmInfo() -> [String: Any] {
        let path = "/private/var/db/softwareupdate/SoftwareUpdateDDMStatePersistence.plist"
        guard FileManager.default.fileExists(atPath: path),
              let plist = PlistHelper.readPlist(atPath: path) as? [String: Any],
              let fields = plist["SUCorePersistedStatePolicyFields"] as? [String: Any],
              let declarations = fields["Declarations"] as? [String: Any],
              !declarations.isEmpty else {
            return [:]
        }

        var ddmInfo = ""
        var keyIndex = 1

        for (_, declaration) in declarations {
            guard let declaration = declaration as? [String: Any],
                  let targetVersion = declaration["TargetOSVersion"] as? String,
                  let targetTime = declaration["TargetLocalDateTime"] as? String else {
                continue
            }
            let time = targetTime.replacingOccurrences(of: "T", with: " ")
            ddmInfo += "Declaration \(keyIndex): macOS \(targetVersion) install by \(time)\n"
            keyIndex += 1
        }

        return ["ddm_info": ddmInfo.trimmingCharacters(in: .whitespacesAndNewlines)]
    }

    // MARK: - Deferred updates

    struct DeferredUpdate {
        var deferred: Any = 0
        var minorOSUpdate: Any = 0
        var majorOSUpdate: Any = 0
        var securityResponseUpdate: Any = 0
        var productKey = ""
        var build = ""
        var deferredUntil: Any = ""
        var downloadSize = ""
        var name = ""
        var version = ""

        var dictionary: [String: Any] {
            return [
                "deferred": deferred,
                "minor_os_update": minorOSUpdate,
                "major_os_update": majorOSUpdate,
                "security_response_update": securityResponseUpdate,
                "product_key": productKey,
                "build": build,
                "deferred_until": deferredUntil,
                "download_size": downloadSize,
                "name": name,
                "version": version,
            ]
        }
    }

    /// Information about deferred and available OS updates
    static func deferredUpdates() -> [String: Any] {
        let output = Shell.run("/usr/libexec/mdmclient", ["AvailableOSUpdates"]).text

        // parseAvailableOSUpdates returns nil where the python version raises
        // and the caller swallows it, leaving the key out entirely
        guard let updates = parseAvailableOSUpdates(output) else { return [:] }

        guard let data = try? JSONSerialization.data(
            withJSONObject: updates.map { $0.dictionary },
            options: [.sortedKeys]
        ) else {
            return [:]
        }

        return ["deferred_updates": String(decoding: data, as: UTF8.self)]
    }

    static let availableUpdatesMarker = "Available updates (install debug profile for more details): "

    /// Returns nil in the cases where the python original raises: no marker in
    /// the output, or more detail blocks than update items to attach them to
    static func parseAvailableOSUpdates(_ output: String) -> [DeferredUpdate]? {
        let sections = output.components(separatedBy: availableUpdatesMarker)

        var updates: [DeferredUpdate] = []

        // First pass: the "=== OS Update Item ===" blocks
        for block in sections[0].components(separatedBy: "=== OS Update Item ===") {
            var update = DeferredUpdate()

            for line in block.components(separatedBy: "\n") {
                if line.contains("Product Key:") {
                    update.productKey = strip(line, "Product Key:")
                } else if line.contains("Deferred:") {
                    let value = strip(line, "Deferred:").components(separatedBy: "  (Date: ")[0]
                        .trimmingCharacters(in: .whitespaces)
                    update.deferred = toBool(value)
                } else if line.contains("MacOSUpdate:") {
                    update.minorOSUpdate = toBool(strip(line, "MacOSUpdate:"))
                } else if line.contains("Title:") || line.contains("Major Title:") {
                    update.name = clean(line, keys: ["Major Title:", "Title:"])
                } else if line.contains("Version:") && !line.contains("Major Version:") {
                    let versionList = clean(line, keys: ["Version:"]).components(separatedBy: " <")
                    update.version = versionList[0].trimmingCharacters(in: .whitespaces)
                    guard versionList.count > 1 else { continue }
                    if !versionList[1].contains("(null)") {
                        update.build = versionList[1]
                            .replacingOccurrences(of: "Build: ", with: "")
                            .replacingOccurrences(of: ">", with: "")
                            .trimmingCharacters(in: .whitespaces)
                    }
                } else if line.contains("Major Version:") {
                    update.version = clean(line, keys: ["Major Version:"])
                }
            }

            if !update.productKey.isEmpty {
                updates.append(update)
            }
        }

        // Second pass: the plist-ish listing after the marker adds details
        guard sections.count > 1 else { return nil }
        let listing = sections[1].trimmingCharacters(in: .whitespacesAndNewlines)

        let blocks = listing.components(separatedBy: "    },")
        // The python version indexes into the update list without a bounds
        // check and blows up as soon as it runs past the end
        guard blocks.count <= updates.count else { return nil }

        var index = 0
        for block in blocks {
            for line in block.components(separatedBy: "\n") {
                if line.contains("Build = ") {
                    updates[index].build = clean(line, keys: ["Build = "])
                } else if line.contains("DeferredUntil = "), isTrue(updates[index].deferred) {
                    updates[index].deferredUntil = stringToTime(clean(line, keys: ["DeferredUntil = "]))
                } else if line.contains("DownloadSize = ") {
                    updates[index].downloadSize = clean(line, keys: ["DownloadSize = "])
                } else if line.contains("HumanReadableName = ") {
                    updates[index].name = clean(line, keys: ["HumanReadableName = "])
                } else if line.contains("IsMajorOSUpdate = ") {
                    updates[index].majorOSUpdate = toBool(clean(line, keys: ["IsMajorOSUpdate = "]))
                } else if line.contains("IsSecurityResponse = ") {
                    updates[index].securityResponseUpdate = toBool(clean(line, keys: ["IsSecurityResponse = "]))
                } else if line.contains("Version = ") {
                    updates[index].version = clean(line, keys: ["Version = "])
                }
            }

            index += 1
        }

        return updates
    }

    // MARK: - Helpers

    /// The major Darwin version, e.g. 19 for 19.6.0
    static func darwinVersion() -> Int {
        return SystemInfo.darwinMajorVersion()
    }

    /// Reads a preference, returning "" when it is not set
    static func value(_ key: String, _ domain: String) -> Any {
        let value = CFPreferencesCopyAppValue(key as CFString, domain as CFString)
        guard let value = value else { return "" }
        return value
    }

    static func bool(_ key: String, _ domain: String) -> Any {
        return toBool(value(key, domain))
    }

    static func time(_ key: String, _ domain: String) -> Any {
        return stringToTime(value(key, domain))
    }

    /// Returns "" for an unset value, 1 for an affirmative one and 0 otherwise
    static func toBool(_ value: Any) -> Any {
        if let string = value as? String {
            if string.isEmpty { return "" }
            return ["YES", "Yes", "yes", "1"].contains(string) ? 1 : 0
        }
        if let bool = value as? Bool { return bool ? 1 : 0 }
        if let number = value as? NSNumber { return number.intValue == 1 ? 1 : 0 }
        return 0
    }

    /// Converts the various date formats found in the preferences to a unix
    /// timestamp string, passing through anything it cannot parse.
    ///
    /// Note the timezone handling: the python original stringifies its NSDates
    /// to a UTC wall clock, strips the " +0000" and then feeds the result to
    /// time.mktime(), which reads it back as *local* time. That shifts every
    /// value by the local UTC offset. We reproduce it so the numbers stay
    /// comparable to what the server has been receiving all along.
    static func stringToTime(_ value: Any) -> Any {
        if let number = value as? NSNumber, number.intValue == 0, !(value is Date) { return "" }

        let string: String
        if let date = value as? Date {
            string = utcFormatter.string(from: date)
        } else if let stringValue = value as? String {
            string = stringValue
        } else {
            return value
        }

        if string == "0" { return "" }

        let cleaned = string.replacingOccurrences(of: " +0000", with: "")
        let formats = ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss'Z'"]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current

        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: cleaned) {
                return String(Int(date.timeIntervalSince1970))
            }
        }

        return string
    }

    /// Renders NSDates the way python's str() does: "2026-07-29 11:03:40 +0000"
    private static let utcFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// Mirrors python's str(): a plist <real> keeps its decimal point
    static func pythonString(_ value: Any) -> String {
        if let string = value as? String { return string }
        if let number = value as? NSNumber {
            return CFNumberIsFloatType(number)
                ? String(number.doubleValue)
                : String(number.int64Value)
        }
        return "\(value)"
    }

    private static func isTrue(_ value: Any) -> Bool {
        if let int = value as? Int { return int == 1 }
        return false
    }

    private static func isBlank(_ value: Any?) -> Bool {
        guard let string = value as? String else { return false }
        return string.isEmpty
    }

    private static func strip(_ line: String, _ key: String) -> String {
        return line
            .replacingOccurrences(of: key, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func clean(_ line: String, keys: [String]) -> String {
        var out = line
        for key in keys {
            out = out.replacingOccurrences(of: key, with: "")
        }
        return out
            .replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func firstExisting(_ paths: [String]) -> String? {
        return paths.first { FileManager.default.fileExists(atPath: $0) }
    }

    /// The file's mtime as a whole-second string
    private static func modificationTime(_ path: String) -> String {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
              let date = attrs[.modificationDate] as? Date else {
            return ""
        }
        return String(Int(date.timeIntervalSince1970))
    }

    private static func merge(_ target: inout [String: Any], _ source: [String: Any]) {
        for (key, value) in source {
            target[key] = value
        }
    }
}
