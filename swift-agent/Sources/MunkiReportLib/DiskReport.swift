import Foundation

/// Disk/Volume collector for munkireport.
///
/// Iterates over all partitions and returns a list of volumes with basic info
/// (TotalSize, FreeSpace, MountPoint, VolumeName). It also reports SMARTStatus
/// from the underlying physical disk(s) in case of an AppleRAID or CoreStorage
/// volume. Disk sizes are reported with .5GB precision.
public enum DiskReport {

    private static let diskutil = "/usr/sbin/diskutil"

    /// APFS system volumes that are of no interest for reporting
    private static let skipTheseMountpoints: Set<String> = [
        "/System/Volumes/Preboot", "/System/Volumes/VM",
        "/System/Volumes/Update", "/private/var/vm", "/System/Volumes/xarts",
        "/System/Volumes/iSCPreboot", "/System/Volumes/Update/SFR/mnt1",
        "/System/Volumes/Update/mnt1", "/System/Volumes/Hardware",
        "/System/Volumes/Data", "/System/Volumes/Recovery", "/Volumes/Recovery",
    ]

    private static let keys = [
        "APFSContainerFree", "BusProtocol", "Content", "CoreStorageCompositeDisk",
        "CoreStorageEncrypted", "CoreStorageLVGUUID", "Ejectable",
        "FilesystemName", "FreeSpace", "Internal", "MountPoint",
        "RAIDMaster", "RAIDMemberUUID", "RAIDSetMembers", "SMARTStatus",
        "SolidState", "TotalSize", "VolumeName", "FileVault",
    ]

    /// Retrieve a list of dicts containing disk info
    public static func collect() -> [[String: Any]] {
        var volumeList: [[String: Any]] = []
        var coreStorageDict: [String: [String: Any]] = [:]
        var appleRaidDict: [String: [String: Any]] = [:]
        var searchCS = false

        for disk in allDisksAndPartitions() {
            addAPFSInfo(&volumeList, disk: disk)

            if let partitions = disk["Partitions"] as? [[String: Any]] {
                for partition in partitions {
                    let content = partition["Content"] as? String ?? ""
                    guard let deviceID = partition["DeviceIdentifier"] as? String else { continue }

                    switch content {
                    case "Apple_HFS":
                        guard hasMountPoint(partition) else { continue }
                        let diskInfo = filteredDiskInfo(deviceID)
                        // Skip Disk Images
                        if isDiskImage(diskInfo) { continue }
                        volumeList.append(diskInfo)

                    case "Apple_CoreStorage":
                        let diskInfo = filteredDiskInfo(deviceID)
                        if let uuid = diskInfo["CoreStorageLVGUUID"] as? String, !uuid.isEmpty {
                            coreStorageDict[uuid] = diskInfo
                        } else {
                            // get CoreStorageLVGUUID
                            searchCS = true
                            let csInfo = dictFromDiskutil(["cs", "info", "-plist", deviceID])
                            if let group = csInfo["MemberOfCoreStorageLogicalVolumeGroup"] as? String {
                                coreStorageDict[group] = diskInfo
                            } else {
                                Display.displayWarning("No CS info found for \(deviceID)")
                            }
                        }

                    case "Apple_RAID":
                        let diskInfo = filteredDiskInfo(deviceID)
                        if let uuid = diskInfo["RAIDMemberUUID"] as? String {
                            appleRaidDict[uuid] = diskInfo
                        }

                    case "Microsoft Basic Data":
                        volumeList.append(filteredDiskInfo(deviceID))

                    default:
                        continue
                    }
                }
            } else {
                guard (disk["Content"] as? String) == "Apple_HFS", hasMountPoint(disk),
                      let deviceID = disk["DeviceIdentifier"] as? String else {
                    continue
                }

                var diskInfo = filteredDiskInfo(deviceID)

                // Skip Disk Images
                if isDiskImage(diskInfo) { continue }

                if let uuid = diskInfo["CoreStorageLVGUUID"] as? String, !uuid.isEmpty {
                    // Update SMART status from Physical Volume
                    if let pv = coreStorageDict[uuid], let status = pv["SMARTStatus"] {
                        diskInfo["SMARTStatus"] = status
                    }
                }

                if searchCS {
                    let csInfo = dictFromDiskutil(["cs", "info", "-plist", deviceID])
                    if let group = csInfo["MemberOfCoreStorageLogicalVolumeGroup"] as? String {
                        if let pv = coreStorageDict[group], let status = pv["SMARTStatus"] {
                            diskInfo["SMARTStatus"] = status
                        }
                    } else {
                        Display.displayWarning("No CS info found for \(deviceID)")
                    }
                }

                if let members = diskInfo["RAIDSetMembers"] as? [String], !members.isEmpty {
                    // Update SMART status from RAID members
                    for member in members {
                        guard let raidMember = appleRaidDict[member] else { continue }
                        let status = raidMember["SMARTStatus"] as? String ?? ""
                        diskInfo["SMARTStatus"] = status
                        // If we find a irregular status, break
                        if status != "Verified" && status != "Not Supported" {
                            break
                        }
                    }
                }

                volumeList.append(diskInfo)
            }
        }

        return volumeList
    }

    // MARK: - Volume collection

    private static func addAPFSInfo(_ volumeList: inout [[String: Any]], disk: [String: Any]) {
        guard let apfsVolumes = disk["APFSVolumes"] as? [[String: Any]] else { return }

        for volume in apfsVolumes {
            guard let mountpoint = volume["MountPoint"] as? String,
                  !mountpoint.isEmpty,
                  !skipTheseMountpoints.contains(mountpoint),
                  let deviceID = volume["DeviceIdentifier"] as? String else {
                continue
            }

            var diskInfo = filteredDiskInfo(deviceID)
            // Skip Disk Images
            if isDiskImage(diskInfo) { continue }

            diskInfo["encrypted"] = diskInfo["FileVault"] as? Bool ?? false
            volumeList.append(diskInfo)
        }
    }

    /// Returns a filtered dictionary
    static func filteredDiskInfo(_ deviceID: String) -> [String: Any] {
        return filter(dictFromDiskutil(["info", "-plist", deviceID]))
    }

    static func filter(_ attrs: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        for key in keys {
            // Not all objects have all these attributes
            if let value = attrs[key] {
                out[key] = value
            }
        }

        // Set sizes to string with .5GB precision
        if let total = int64(out["TotalSize"]), total != 0 {
            out["TotalSize"] = String(halfGB(total))
        }

        // Machines running > 10.15 do not use the FreeSpace key, the value has
        // to be taken from the APFS container instead
        if let containerFree = int64(out["APFSContainerFree"]), containerFree != 0 {
            out["FreeSpace"] = String(halfGB(containerFree))
        } else if let free = int64(out["FreeSpace"]) {
            out["FreeSpace"] = String(halfGB(free))
        }

        return out
    }

    // MARK: - Helpers

    /// Round to .5GB precision (29 bit)
    static func halfGB(_ size: Int64) -> Int64 {
        return (size >> 29) << 29
    }

    private static func isDiskImage(_ diskInfo: [String: Any]) -> Bool {
        return (diskInfo["BusProtocol"] as? String) == "Disk Image"
    }

    private static func hasMountPoint(_ dict: [String: Any]) -> Bool {
        guard let mountpoint = dict["MountPoint"] as? String else { return false }
        return !mountpoint.isEmpty
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let int = value as? Int { return Int64(int) }
        if let string = value as? String { return Int64(string) }
        return nil
    }

    /// Returns list of all disks and partitions
    private static func allDisksAndPartitions() -> [[String: Any]] {
        let list = dictFromDiskutil(["list", "-plist"])
        guard let disks = list["AllDisksAndPartitions"] as? [[String: Any]] else {
            Display.displayWarning("Unable to list all partitions.")
            return []
        }
        return disks
    }

    /// Returns a dict based upon a diskutil call with a -plist argument
    private static func dictFromDiskutil(_ arguments: [String]) -> [String: Any] {
        return Shell.plistDict(diskutil, arguments)
    }
}
