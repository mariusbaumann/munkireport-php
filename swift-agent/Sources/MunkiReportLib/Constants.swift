import Foundation

public enum Constants {
    public static let bundleID = "MunkiReport" as CFString
    public static let bundleIDString = "MunkiReport"

    // Plist paths
    public static let managedInstallsPlistPath = "/Library/Preferences/MunkiReport.plist"
    public static let secureManagedInstallsPlistPath = "/private/var/root/Library/Preferences/MunkiReport.plist"

    // Log paths
    public static let logFile = "/Library/MunkiReport/Logs/MunkiReport.log"
    public static let logDir = "/Library/MunkiReport/Logs"

    // Run file
    public static let touchFile = "/Users/Shared/.com.github.munkireport.run"

    // Receipt
    public static let receiptPlistPath = "/private/var/db/receipts/com.github.munkireport.plist"

    // HTTP headers key
    public static let additionalHTTPHeadersKey = "AdditionalHttpHeaders"

    // Exit codes
    public static let exitPreflightFailure: Int32 = 1
    public static let exitObjcMissing: Int32 = 100
    public static let exitMunkiDirsFailure: Int32 = 101
    public static let exitServerUnavailable: Int32 = 150
    public static let exitInvalidParameters: Int32 = 200
    public static let exitRootRequired: Int32 = 201
}
