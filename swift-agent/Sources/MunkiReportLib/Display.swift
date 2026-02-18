import Foundation

public final class Display {
    public static var verbose: Int = 0

    public static func displayError(_ msg: String) {
        let message = "ERROR: \(msg)"
        fputs("\(message)\n", stderr)
        Logging.logError(message)
    }

    public static func displayWarning(_ msg: String) {
        let message = "WARNING: \(msg)"
        if verbose >= 1 {
            print(message)
        }
        Logging.logWarning(message)
    }

    public static func displayDetail(_ msg: String) {
        if verbose >= 2 {
            print(msg)
        }
        Logging.logDetail(msg)
    }
}
