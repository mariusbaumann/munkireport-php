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
}
