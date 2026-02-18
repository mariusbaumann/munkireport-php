import Foundation

public enum PlistHelper {

    public static func readPlist(atPath path: String) -> Any? {
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return readPlist(fromData: data)
    }

    public static func readPlist(fromData data: Data) -> Any? {
        do {
            return try PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
            )
        } catch {
            Display.displayError("Failed to read plist: \(error.localizedDescription)")
            return nil
        }
    }

    public static func writePlistToData(_ obj: Any) -> Data? {
        do {
            return try PropertyListSerialization.data(
                fromPropertyList: obj,
                format: .xml,
                options: 0
            )
        } catch {
            Display.displayError("Failed to write plist: \(error.localizedDescription)")
            return nil
        }
    }
}
