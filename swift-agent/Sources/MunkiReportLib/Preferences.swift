import Foundation

public final class Preferences {

    public static let defaultPrefs: [String: Any?] = [
        "AdditionalHttpHeaders": nil,
        "BaseUrl": nil,
        "FollowHTTPRedirects": false,
        "HttpConnectionTimeout": 60,
        "LogFile": Constants.logFile,
        "LogToSyslog": false,
        "Passphrase": nil,
        "scriptTimeOut": 30,
        "UseAdditionalHttpHeaders": false,
    ]

    public static func pref(_ key: String) -> Any? {
        let value = CFPreferencesCopyAppValue(key as CFString, Constants.bundleID)
        if value == nil {
            if let defaultValue = defaultPrefs[key] as? Any {
                // Write default to disk for admin discoverability
                setPref(key, value: defaultValue)
                return defaultValue
            }
            return nil
        }
        // Convert NSDate to string
        if let dateValue = value as? Date {
            return "\(dateValue)"
        }
        return value
    }

    public static func setPref(_ key: String, value: Any) {
        CFPreferencesSetValue(
            key as CFString,
            value as CFTypeRef,
            Constants.bundleID,
            kCFPreferencesAnyUser,
            kCFPreferencesCurrentHost
        )
        CFPreferencesAppSynchronize(Constants.bundleID)
    }

    public static func reloadPrefs() {
        CFPreferencesAppSynchronize(Constants.bundleID)
    }

    public static func printConfig() {
        print("Current MunkiReport configuration:")
        let maxLen = defaultPrefs.keys.map { $0.count }.max() ?? 0

        for key in defaultPrefs.keys.sorted() {
            let value = pref(key)
            let where_ = getConfigLevel(key: key, value: value)
            let displayValue: String
            if let v = value as? String {
                displayValue = "'\(v)'"
            } else if let v = value {
                displayValue = "\(v)"
            } else {
                displayValue = "None"
            }
            let padding = String(repeating: " ", count: maxLen - key.count)
            print("\(padding)\(key): \(displayValue) \(where_)")
        }
    }

    private static func getConfigLevel(key: String, value: Any?) -> String {
        guard value != nil else { return "[not set]" }

        if CFPreferencesAppValueIsForced(key as CFString, Constants.bundleID) {
            return "[MANAGED]"
        }

        let levels: [(file: String, user: CFString, host: CFString)] = [
            ("/var/root/Library/Preferences/ByHost/\(Constants.bundleIDString).xxxx.plist",
             kCFPreferencesCurrentUser, kCFPreferencesCurrentHost),
            ("/var/root/Library/Preferences/\(Constants.bundleIDString).plist",
             kCFPreferencesCurrentUser, kCFPreferencesAnyHost),
            ("/Library/Preferences/\(Constants.bundleIDString).plist",
             kCFPreferencesAnyUser, kCFPreferencesCurrentHost),
        ]

        for level in levels {
            let levelValue = CFPreferencesCopyValue(
                key as CFString,
                Constants.bundleID,
                level.user,
                level.host
            )
            if let levelValue = levelValue, let value = value {
                // Compare as strings for simplicity
                if "\(levelValue)" == "\(value)" {
                    return "[\(level.file)]"
                }
            }
        }

        // Check if it's the default
        if let defaultVal = defaultPrefs[key] as? Any {
            if "\(defaultVal)" == "\(value!)" {
                return "[default]"
            }
        }

        return "[unknown]"
    }
}
