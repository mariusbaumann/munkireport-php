import Foundation

/// MDM status reporting tool.
///
/// Requires macOS 10.13.4+ (Darwin 17.5.0) for `profiles status` output
/// compatibility, older systems fall back to parsing the profile payloads.
public enum MDMStatus {

    private static let profiles = "/usr/bin/profiles"
    private static let mdmclient = "/usr/libexec/mdmclient"
    private static let watchdogState = "/Library/Application Support/mdm-watchdog/state.json"

    public static func collect() -> [String: Any] {
        // Check if macOS 10.13.4 (Darwin 17.5.0) or higher
        var result = fullDarwinVersion() >= 1750 ? statusModern() : statusLegacy()

        result.merge(serverURL()) { _, new in new }
        result.merge(mdmInfo()) { _, new in new }
        result.merge(watchdogKickstarts()) { _, new in new }

        return result
    }

    // MARK: - profiles

    /// Uses profiles command to detect the MDM server hostname
    static func serverURL() -> [String: Any] {
        var mdmServerURL = ""

        for item in profileItems() {
            guard (item["PayloadType"] as? String) == "com.apple.mdm" else { continue }
            guard let content = item["PayloadContent"] as? [String: Any],
                  let fullURL = content["ServerURL"] as? String else {
                mdmServerURL = ""
                continue
            }
            mdmServerURL = matchServerURL(fullURL)
        }

        return ["mdm_server_url": mdmServerURL]
    }

    /// Mirrors the python regex r'http.?:\/\/[\S]+(?=\/)', which greedily keeps
    /// everything up to the last slash
    static func matchServerURL(_ url: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "^http.?://[\\S]+(?=/)") else {
            return ""
        }
        let range = NSRange(url.startIndex..., in: url)
        guard let match = regex.firstMatch(in: url, range: range),
              let matchRange = Range(match.range, in: url) else {
            return ""
        }
        return String(url[matchRange])
    }

    /// All ProfileItems of all computer level profiles
    private static func profileItems() -> [[String: Any]] {
        let plist = Shell.plist(profiles, ["-C", "-o", "stdout-xml"])
        guard let dict = plist as? [String: Any],
              let computerLevel = dict["_computerlevel"] as? [[String: Any]] else {
            return []
        }

        var items: [[String: Any]] = []
        for profile in computerLevel {
            if let profileItems = profile["ProfileItems"] as? [[String: Any]] {
                items.append(contentsOf: profileItems)
            }
        }
        return items
    }

    /// Uses profiles command to get MDM status for this machine.
    /// Requires macOS 10.13.4 due to MDM status output changes.
    static func statusModern() -> [String: Any] {
        let output = Shell.run(profiles, ["status", "-type", "enrollment"]).text
        return parseEnrollmentStatus(output)
    }

    static func parseEnrollmentStatus(_ output: String) -> [String: Any] {
        var enrolledViaDEP = ""
        var mdmEnrollment = ""

        for line in output.components(separatedBy: "\n") {
            if line.contains("Enrolled via DEP:") {
                enrolledViaDEP = secondField(of: line).contains("Yes") ? "Yes" : "No"
            }
            if line.contains("MDM enrollment:") {
                mdmEnrollment = secondField(of: line)
            }
        }

        return ["mdm_enrolled_via_dep": enrolledViaDEP, "mdm_enrolled": mdmEnrollment]
    }

    /// Uses profiles command on older versions of macOS to check if a machine
    /// is enrolled in MDM
    static func statusLegacy() -> [String: Any] {
        var mdmEnrolled = "No"
        for item in profileItems() {
            mdmEnrolled = (item["PayloadType"] as? String) == "com.apple.mdm"
                ? "Yes (User Approved)"
                : "No"
        }

        let depOutput = Shell.run(profiles, ["-e"]).text
        let enrolledViaDEP = depOutput.contains("ConfigurationURL") ? "Yes" : "No"

        return ["mdm_enrolled": mdmEnrolled, "mdm_enrolled_via_dep": enrolledViaDEP]
    }

    // MARK: - mdmclient

    /// Additional information about the MDM and the ABM/ASM org.
    /// The order of these rules matters, the first match for a line wins.
    private static let mdmInfoRules: [(needle: String, key: String, isBool: Bool)] = [
        ("DeviceIsSupervised = ", "is_supervised", true),
        ("EnrolledInDEP = ", "enrolled_in_dep", true),
        // We need the extra spaces in here
        ("            DeniesActivationLock = ", "denies_activation_lock", true),
        ("IsActivationLockManageable = ", "activation_lock_manageable", true),
        ("IsUserApproved = ", "is_user_approved", true),
        ("IsUserEnrollment = ", "is_user_enrollment", true),
        ("ManagedViaMDM = ", "managed_via_mdm", true),
        ("OrganizationAddress = ", "org_address_full", false),
        ("OrganizationAddressLine1 = ", "org_address", false),
        ("OrganizationCity = ", "org_city", false),
        ("OrganizationCountry = ", "org_country", false),
        ("OrganizationEmail = ", "org_email", false),
        ("OrganizationMagic = ", "org_magic", false),
        ("OrganizationName = ", "org_name", false),
        ("OrganizationPhone = ", "org_phone", false),
        ("OrganizationSupportEmail = ", "org_support_email", false),
        ("OrganizationZipCode = ", "org_zip_code", false),
        ("OrganizationDepartment = ", "org_department", false),
        ("OrigInstallOSVersion = ", "original_os_version", false),
        ("ServerURL = ", "mdm_server_url_full", false),
    ]

    static func mdmInfo() -> [String: Any] {
        return parseManagementStatus(Shell.run(mdmclient, ["dumpManagementStatus"]).text)
    }

    static func parseManagementStatus(_ output: String) -> [String: Any] {
        var result: [String: Any] = [:]

        for line in output.components(separatedBy: "\n") {
            guard let rule = mdmInfoRules.first(where: { line.contains($0.needle) }) else {
                continue
            }
            // The needle may carry indentation, the value is stripped without it
            let value = cleanValue(line, key: rule.needle.trimmingCharacters(in: .whitespaces))
            result[rule.key] = rule.isBool ? toBool(value) : value
        }

        return result
    }

    private static func cleanValue(_ line: String, key: String) -> String {
        return line
            .replacingOccurrences(of: key, with: "")
            .replacingOccurrences(of: ";", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - mdm-watchdog

    /// Picks up the kickstart timestamps if mdm-watchdog's state.json is present
    static func watchdogKickstarts() -> [String: Any] {
        guard FileManager.default.fileExists(atPath: watchdogState),
              let data = FileManager.default.contents(atPath: watchdogState),
              let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return [:]
        }

        var result: [String: Any] = [:]
        let wanted = [
            "last_mdm_kickstart": "last_mdm_kickstart",
            "last_software_update_kickstart": "last_software_update_kickstart",
        ]

        for (key, outKey) in wanted {
            guard let value = state[key] as? String, !value.contains("0001-01-01") else { continue }
            if let timestamp = stringToTimestamp(value) {
                result[outKey] = timestamp
            }
        }

        return result
    }

    /// Parses mdm-watchdog's RFC3339 timestamps.
    ///
    /// Mirrors the python helper, which drops the last 6 characters (the UTC
    /// offset) and reads the remainder as UTC.
    static func stringToTimestamp(_ timeString: String) -> Int? {
        // The python version builds a broken offset in this case and raises
        if timeString.contains("Z") { return nil }
        guard timeString.count > 6 else { return nil }

        let dateString = String(timeString.dropLast(6))
            .trimmingCharacters(in: .whitespaces)

        // %f accepts any fraction, but the result is truncated to whole seconds
        let withoutFraction = dateString.components(separatedBy: ".")[0]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"

        guard let date = formatter.date(from: withoutFraction) else { return nil }
        return Int(date.timeIntervalSince1970)
    }

    // MARK: - Helpers

    /// Returns the Darwin version without dots: 19.6.0 -> 1960
    static func fullDarwinVersion() -> Int {
        return Int(SystemInfo.darwinRelease().replacingOccurrences(of: ".", with: "")) ?? 0
    }

    /// Everything after the first colon, leading whitespace removed
    private static func secondField(of line: String) -> String {
        let parts = line.components(separatedBy: ":")
        guard parts.count > 1 else { return "" }
        return parts[1].trimmingCharacters(in: .whitespaces)
    }

    /// Returns "" for an empty value, 1 for an affirmative one and 0 otherwise
    static func toBool(_ value: String) -> Any {
        if value.isEmpty { return "" }
        if ["YES", "Yes", "yes", "1"].contains(value) { return 1 }
        return 0
    }
}
