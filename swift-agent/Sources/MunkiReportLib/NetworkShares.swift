import Foundation

/// Network shares for munkireport.
public enum NetworkShares {

    /// Uses system profiler to get network shares for this machine
    static func getNetworkShares() -> [[String: Any]] {
        let plist = Shell.plist(
            "/usr/sbin/system_profiler",
            ["SPNetworkVolumeDataType", "-xml"]
        )

        // system_profiler xml is an array
        guard let array = plist as? [[String: Any]],
              let spDict = array.first,
              let items = spDict["_items"] as? [[String: Any]] else {
            return []
        }
        return items
    }

    /// Un-nest network shares, return array with objects with relevant keys
    static func flatten(_ array: [[String: Any]]) -> [[String: Any]] {
        var out: [[String: Any]] = []

        for obj in array {
            var device: [String: Any] = ["name": "", "automounted": 0]

            for (key, value) in obj {
                switch key {
                case "_items":
                    if let nested = value as? [[String: Any]] {
                        out = out + flatten(nested)
                    }
                case "_name":
                    device["name"] = value
                case "spnetworkvolume_mntfromname":
                    device["mntfromname"] = value
                case "spnetworkvolume_fstypename":
                    device["fstypename"] = value
                case "spnetworkvolume_fsmtnonname":
                    device["fsmtnonname"] = value
                case "spnetworkvolume_automounted":
                    if (value as? String) == "Yes" {
                        device["automounted"] = 1
                    }
                default:
                    continue
                }
            }

            out.append(device)
        }

        return out
    }

    public static func collect() -> [[String: Any]] {
        return flatten(getNetworkShares())
    }
}
