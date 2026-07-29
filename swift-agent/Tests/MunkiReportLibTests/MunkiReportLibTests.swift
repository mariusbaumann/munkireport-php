import XCTest
@testable import MunkiReportLib

final class MunkiReportLibTests: XCTestCase {

    func testConstants() {
        XCTAssertEqual(Constants.bundleIDString, "MunkiReport")
        XCTAssertEqual(Constants.touchFile, "/Users/Shared/.com.github.munkireport.run")
    }

    func testSizeofFmt() {
        XCTAssertEqual(ReportCommon.sizeofFmt(0), "0B")
        XCTAssertEqual(ReportCommon.sizeofFmt(500), "500B")
        XCTAssertEqual(ReportCommon.sizeofFmt(1500), "2KB")
        XCTAssertEqual(ReportCommon.sizeofFmt(1_500_000), "2MB")
    }

    func testMD5Hash() {
        // Test with a known string
        let testString = "hello world"
        let data = testString.data(using: .utf8)!
        let tempPath = NSTemporaryDirectory() + "munkireport_test_md5.txt"
        FileManager.default.createFile(atPath: tempPath, contents: data)
        defer { try? FileManager.default.removeItem(atPath: tempPath) }

        let hash = ReportCommon.md5Hash(ofFile: tempPath)
        XCTAssertEqual(hash, "5eb63bbbe01eeed093cb22bb8f5acdc3")
    }

    func testMD5HashNonexistentFile() {
        let hash = ReportCommon.md5Hash(ofFile: "/nonexistent/file/path")
        XCTAssertEqual(hash, "NOT A FILE")
    }

    func testPlistRoundtrip() {
        let original: [String: Any] = [
            "key1": "value1",
            "key2": 42,
            "key3": true,
        ]

        guard let data = PlistHelper.writePlistToData(original) else {
            XCTFail("Failed to write plist")
            return
        }

        guard let parsed = PlistHelper.readPlist(fromData: data) as? [String: Any] else {
            XCTFail("Failed to read plist")
            return
        }

        XCTAssertEqual(parsed["key1"] as? String, "value1")
        XCTAssertEqual(parsed["key2"] as? Int, 42)
        XCTAssertEqual(parsed["key3"] as? Bool, true)
    }

    // MARK: - Collectors

    func testMunkiReportFiltersAndDeduplicates() {
        let report: [String: Any] = [
            "StartTime": "2026-07-29 10:00:00 +0000",
            "EndTime": "2026-07-29 10:04:00 +0000",
            "ManifestName": "site_default",
            "RunType": "auto",
            "Errors": ["Could not retrieve catalog x", "Could not retrieve catalog x", "boom"],
            "Warnings": [],
            "ItemsToInstall": [["name": "Firefox"]],
        ]

        let out = Collectors.buildMunkiReport(from: report)

        XCTAssertEqual(out["ManifestName"] as? String, "site_default")
        XCTAssertEqual(out["Errors"] as? [String], ["Could not retrieve catalog x", "boom"])
        // Empty values and keys outside the whitelist are dropped
        XCTAssertNil(out["Warnings"])
        XCTAssertNil(out["ItemsToInstall"])
    }

    func testManagedInstallsStatusAndResults() {
        let report: [String: Any] = [
            "ManagedInstalls": [
                ["name": "Firefox", "display_name": "Firefox", "installed": true,
                 "installed_version": "141.0", "installed_size": 1024],
            ],
            "ItemsToInstall": [
                ["name": "Slack", "display_name": "Slack", "version_to_install": "4.2"],
            ],
            "AppleUpdates": [
                ["name": "macOS Update", "productKey": "MSU_UPDATE_26_patch",
                 "version_to_install": "26.1"],
            ],
            "RemovedItems": ["OldApp"],
            "InstallResults": [
                ["name": "Slack", "display_name": "Slack", "status": 0,
                 "time": Date(timeIntervalSince1970: 1_774_000_000)],
            ],
        ]

        let out = Collectors.buildManagedInstalls(report: report, log: [])

        let firefox = out["Firefox"] as? [String: Any]
        XCTAssertEqual(firefox?["status"] as? String, "installed")
        XCTAssertEqual(firefox?["type"] as? String, "munki")
        XCTAssertEqual(firefox?["installed_version"] as? String, "141.0")

        // Apple software updates are keyed by their product key
        XCTAssertNotNil(out["MSU_UPDATE_26_patch"])
        XCTAssertEqual((out["MSU_UPDATE_26_patch"] as? [String: Any])?["type"] as? String, "applesus")
        XCTAssertNil(out["macOS Update"])

        let removed = out["OldApp"] as? [String: Any]
        XCTAssertEqual(removed?["status"] as? String, "removed")
        XCTAssertEqual(removed?["installed"] as? Bool, false)

        // InstallResults promote the pending item to succeeded and add a timestamp
        let slack = out["Slack"] as? [String: Any]
        XCTAssertEqual(slack?["status"] as? String, "install_succeeded")
        XCTAssertEqual(slack?["installed"] as? Bool, true)
        XCTAssertEqual(slack?["timestamp"] as? String, "1774000000")
    }

    func testManagedInstallsFailedInstall() {
        let report: [String: Any] = [
            "ItemsToInstall": [["name": "Slack", "display_name": "Slack"]],
            "InstallResults": [["name": "Slack", "display_name": "Slack", "status": 1]],
        ]

        let out = Collectors.buildManagedInstalls(report: report, log: [])
        XCTAssertEqual((out["Slack"] as? [String: Any])?["status"] as? String, "install_failed")
    }

    func testManagedInstallsTimestampFromLog() {
        let report: [String: Any] = [
            "ManagedInstalls": [
                ["name": "Firefox", "display_name": "Firefox",
                 "installed": true, "installed_version": "141.0"],
            ],
        ]
        let log = ["Jul 06 2025 06:19:55 -0500 Install of Firefox-141.0: SUCCESSFUL"]

        let out = Collectors.buildManagedInstalls(report: report, log: log)
        let firefox = out["Firefox"] as? [String: Any]
        XCTAssertEqual(firefox?["timestamp"] as? String, "1751800795")
    }

    func testStringToTime() {
        // Munki 7 and newer log format: 07:22:52 -05:00 is 12:22:52 UTC
        XCTAssertEqual(Collectors.stringToTime("2025-07-20 07:22:52.533-05:00"), "1753014172")
        // Munki 6 and older log format
        XCTAssertEqual(Collectors.stringToTime("Jul 06 2025 06:19:55 -0500"), "1751800795")
        // Unparseable input is passed through, empty markers become empty
        XCTAssertEqual(Collectors.stringToTime("0"), "")
        XCTAssertEqual(Collectors.stringToTime("not a date"), "not a date")
    }

    // MARK: - DiskReport

    func testHalfGBPrecision() {
        // Sizes are truncated to a multiple of 512MB
        XCTAssertEqual(DiskReport.halfGB(0), 0)
        XCTAssertEqual(DiskReport.halfGB(536_870_911), 0)
        XCTAssertEqual(DiskReport.halfGB(536_870_912), 536_870_912)
        XCTAssertEqual(DiskReport.halfGB(493_921_239_040 + 12345), 493_921_239_040)
    }

    func testDiskInfoFilterUsesAPFSContainerFree() {
        let attrs: [String: Any] = [
            "VolumeName": "Macintosh HD",
            "MountPoint": "/",
            "TotalSize": 494_384_795_648 as Int64,
            "FreeSpace": 0 as Int64,
            "APFSContainerFree": 127_050_334_208 as Int64,
            "DeviceIdentifier": "disk3s1s1",
        ]

        let out = DiskReport.filter(attrs)

        // Sizes become .5GB-precision strings
        XCTAssertEqual(out["TotalSize"] as? String, "493921239040")
        XCTAssertEqual(out["FreeSpace"] as? String, "126701535232")
        XCTAssertEqual(out["VolumeName"] as? String, "Macintosh HD")
        // Keys outside the whitelist are dropped
        XCTAssertNil(out["DeviceIdentifier"])
    }

    func testDiskInfoFilterFallsBackToFreeSpace() {
        let attrs: [String: Any] = [
            "VolumeName": "Backup",
            "TotalSize": 2_000_000_000_000 as Int64,
            "FreeSpace": 1_000_000_000_000 as Int64,
        ]

        let out = DiskReport.filter(attrs)
        XCTAssertEqual(out["FreeSpace"] as? String, String(DiskReport.halfGB(1_000_000_000_000)))
    }

    // MARK: - MDMStatus

    func testParseEnrollmentStatus() {
        let output = """
        Enrolled via DEP: Yes
        MDM enrollment: Yes (User Approved)
        MDM server: https://mdm.example.com/mdm/checkin
        """

        let out = MDMStatus.parseEnrollmentStatus(output)
        XCTAssertEqual(out["mdm_enrolled_via_dep"] as? String, "Yes")
        XCTAssertEqual(out["mdm_enrolled"] as? String, "Yes (User Approved)")
    }

    func testParseEnrollmentStatusNotEnrolled() {
        let output = "Enrolled via DEP: No\nMDM enrollment: No"

        let out = MDMStatus.parseEnrollmentStatus(output)
        XCTAssertEqual(out["mdm_enrolled_via_dep"] as? String, "No")
        XCTAssertEqual(out["mdm_enrolled"] as? String, "No")
    }

    func testParseManagementStatus() {
        let output = """
            DeviceIsSupervised = 1;
            EnrolledInDEP = 0;
            OrganizationName = "Example AG";
            OrganizationCity = Zurich;
            ServerURL = "https://mdm.example.com/mdm/checkin?id=1";
        """

        let out = MDMStatus.parseManagementStatus(output)
        XCTAssertEqual(out["is_supervised"] as? Int, 1)
        XCTAssertEqual(out["enrolled_in_dep"] as? Int, 0)
        XCTAssertEqual(out["org_name"] as? String, "Example AG")
        XCTAssertEqual(out["org_city"] as? String, "Zurich")
        XCTAssertEqual(out["mdm_server_url_full"] as? String, "https://mdm.example.com/mdm/checkin?id=1")
    }

    func testMatchServerURLKeepsEverythingUpToLastSlash() {
        XCTAssertEqual(
            MDMStatus.matchServerURL("https://mdm.example.com/mdm/checkin"),
            "https://mdm.example.com/mdm"
        )
        XCTAssertEqual(MDMStatus.matchServerURL("not a url"), "")
    }

    func testWatchdogTimestamp() {
        // The offset is dropped and the remainder read as UTC, mirroring python
        XCTAssertEqual(MDMStatus.stringToTimestamp("2023-08-17T01:21:54.555443-04:00"), 1_692_235_314)
        // A "Z" makes the python helper raise, so nothing is reported
        XCTAssertNil(MDMStatus.stringToTimestamp("2023-08-17T01:21:54.555443Z"))
        XCTAssertNil(MDMStatus.stringToTimestamp("short"))
    }

    // MARK: - NetworkShares

    func testFlattenNetworkShares() {
        let items: [[String: Any]] = [
            [
                "_name": "smb_share",
                "spnetworkvolume_mntfromname": "//user@server/share",
                "spnetworkvolume_fstypename": "smbfs",
                "spnetworkvolume_fsmtnonname": "/Volumes/share",
                "spnetworkvolume_automounted": "Yes",
            ],
        ]

        let out = NetworkShares.flatten(items)
        XCTAssertEqual(out.count, 1)
        XCTAssertEqual(out[0]["name"] as? String, "smb_share")
        XCTAssertEqual(out[0]["mntfromname"] as? String, "//user@server/share")
        XCTAssertEqual(out[0]["fstypename"] as? String, "smbfs")
        XCTAssertEqual(out[0]["automounted"] as? Int, 1)
    }

    func testFlattenNetworkSharesUnnestsAndDefaults() {
        let items: [[String: Any]] = [
            ["_name": "parent", "_items": [["_name": "child"]]],
        ]

        let out = NetworkShares.flatten(items)
        // The nested item comes first, the parent is still reported
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out[0]["name"] as? String, "child")
        XCTAssertEqual(out[1]["name"] as? String, "parent")
        XCTAssertEqual(out[0]["automounted"] as? Int, 0)
    }

    // MARK: - SoftwareUpdate

    func testPythonStringKeepsRealsDecimal() {
        // A plist <real> keeps its decimal point the way python's str() does
        XCTAssertEqual(SoftwareUpdate.pythonString(NSNumber(value: 5353.0)), "5353.0")
        XCTAssertEqual(SoftwareUpdate.pythonString(NSNumber(value: 5353)), "5353")
        XCTAssertEqual(SoftwareUpdate.pythonString("2.1.7"), "2.1.7")
    }

    func testToBoolMatchesPythonTruthiness() {
        XCTAssertEqual(SoftwareUpdate.toBool("") as? String, "")
        XCTAssertEqual(SoftwareUpdate.toBool("Yes") as? Int, 1)
        XCTAssertEqual(SoftwareUpdate.toBool("1") as? Int, 1)
        XCTAssertEqual(SoftwareUpdate.toBool("No") as? Int, 0)
        XCTAssertEqual(SoftwareUpdate.toBool(true) as? Int, 1)
        XCTAssertEqual(SoftwareUpdate.toBool(false) as? Int, 0)
    }

    func testDeferredUpdatesParsing() {
        let output = """
        === OS Update Item ===
            Product Key: MSU_UPDATE_26A123_patch
            Deferred: YES  (Date: 2026-08-01 10:00:00 +0000)
            MacOSUpdate: YES
            Title: macOS Tahoe
            Version: 26.1 <Build: 26A123>
        Available updates (install debug profile for more details): (
            {
                Build = 26A123;
                DownloadSize = 4096;
                HumanReadableName = "macOS Tahoe 26.1";
                IsMajorOSUpdate = 0;
                IsSecurityResponse = 0;
            }
        )
        """

        guard let updates = SoftwareUpdate.parseAvailableOSUpdates(output) else {
            XCTFail("Expected the output to parse")
            return
        }
        XCTAssertEqual(updates.count, 1)
        XCTAssertEqual(updates[0].productKey, "MSU_UPDATE_26A123_patch")
        XCTAssertEqual(updates[0].deferred as? Int, 1)
        XCTAssertEqual(updates[0].build, "26A123")
        XCTAssertEqual(updates[0].downloadSize, "4096")
        XCTAssertEqual(updates[0].name, "macOS Tahoe 26.1")
    }

    func testDeferredUpdatesReturnsNilWherePythonRaises() {
        // No marker at all
        XCTAssertNil(SoftwareUpdate.parseAvailableOSUpdates("no updates here"))
        // Marker present but no update items to attach the detail blocks to
        XCTAssertNil(SoftwareUpdate.parseAvailableOSUpdates(
            "Available updates (install debug profile for more details): (\n)"
        ))
    }

    func testUniquePreservingOrder() {
        XCTAssertEqual(Collectors.uniquePreservingOrder(["b", "a", "b", "c", "a"]), ["b", "a", "c"])
    }
}
