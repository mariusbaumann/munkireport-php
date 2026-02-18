import Foundation
import CommonCrypto

public enum ReportCommon {

    // MARK: - Public API

    public static func process(
        serial: String,
        items: inout [String: [String: Any]],
        forceUpload: String?
    ) throws {
        // Sanitize serial
        let cleanSerial = serial.filter { $0.isLetter || $0.isNumber }

        // Get base URL
        guard let baseURL = Preferences.pref("BaseUrl") as? String ??
              ((Preferences.pref("SoftwareRepoURL") as? String).map { $0 + "/report/" }) else {
            Display.displayError("No BaseUrl configured")
            return
        }

        let hashURL = baseURL + "index.php?/report/hash_check"
        let checkURL = baseURL + "index.php?/report/check_in"
        let passphrase = Preferences.pref("Passphrase") as? String ?? ""

        // Get HTTP settings
        let timeout = TimeInterval((Preferences.pref("HttpConnectionTimeout") as? Int) ?? 60)
        let followRedirects = (Preferences.pref("FollowHTTPRedirects") as? Bool) ?? false
        let additionalHeaders = getAdditionalHeaders()

        // Compute hashes for file-based items
        for (key, _) in items {
            if let path = items[key]?["path"] as? String {
                items[key]?["hash"] = md5Hash(ofFile: path)
            }
        }

        // Build check dictionary (hashes only)
        var check: [String: [String: String]] = [:]
        for (key, item) in items {
            if let hash = item["hash"] as? String {
                check[key] = ["hash": hash]
            }
        }

        // Send hashes to server
        let hashBody: [String: Any] = [
            "serial": cleanSerial,
            "items": check,
            "passphrase": passphrase
        ]

        Display.displayDetail("Sending hash check to server")
        let responseData = try HTTPClient.postJSON(
            url: hashURL,
            body: hashBody,
            timeout: timeout,
            followRedirects: followRedirects,
            additionalHeaders: additionalHeaders
        )

        // Parse JSON response
        guard let result = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            Display.displayError("Could not parse server response")
            return
        }

        // Check for server errors
        if let error = result["error"] as? String, !error.isEmpty {
            Display.displayError("Server error: \(error)")
            return
        }

        if let info = result["info"] as? String, !info.isEmpty {
            Display.displayDetail("Server info: \(info)")
        }

        // Get upload limits
        var uploadMaxFilesize = (result["upload_max_filesize"] as? Int) ?? 0
        var postMaxSize = (result["post_max_size"] as? Int) ?? 0
        if uploadMaxFilesize == 0 { uploadMaxFilesize = 104_857_600 } // 100 MB
        if postMaxSize == 0 { postMaxSize = 104_857_600 }

        let uploadLimit: Int
        let phpFileLimitation: String
        if uploadMaxFilesize <= postMaxSize {
            uploadLimit = uploadMaxFilesize
            phpFileLimitation = "upload_max_filesize"
        } else {
            uploadLimit = postMaxSize
            phpFileLimitation = "post_max_size"
        }

        // Determine which server says need updating
        var serverResult = result

        // Override with force upload
        if forceUpload == "FORCE_UPLOAD_ALL" {
            Display.displayWarning("Forcing update for all modules!")
            for key in items.keys {
                serverResult[key] = 1
            }
        } else if let forceModules = forceUpload {
            for module in forceModules.split(separator: " ") {
                Display.displayWarning("Forcing update for \(module)!")
                serverResult[String(module)] = 1
            }
        }

        // Collect items that need updating
        var totalSize = 0
        var itemSizes: [String: Int] = [:]

        for key in Array(items.keys) {
            if serverResult[key] != nil && !(serverResult[key] is String) {
                // Read file data if needed
                if let path = items[key]?["path"] as? String {
                    do {
                        let data = try String(contentsOfFile: path, encoding: .utf8)
                        items[key]?["data"] = data
                    } catch {
                        do {
                            let data = try Data(contentsOf: URL(fileURLWithPath: path))
                            items[key]?["data"] = data.base64EncodedString()
                        } catch {
                            Display.displayWarning("Can't open \(path)")
                            items.removeValue(forKey: key)
                            continue
                        }
                    }
                }

                guard let data = items[key]?["data"] else {
                    items.removeValue(forKey: key)
                    continue
                }

                let size: Int
                if let strData = data as? String {
                    size = strData.utf8.count
                } else if let dataData = data as? Data {
                    size = dataData.count
                } else {
                    size = 0
                }

                // Check against upload limit
                if uploadLimit < (size + 256) {
                    Display.displayError("Unable to send \(key), file size is too big! (\(sizeofFmt(size)))")
                    Display.displayError("Must be smaller than PHP's \(phpFileLimitation) of \(sizeofFmt(uploadLimit))")
                    items.removeValue(forKey: key)
                    continue
                }

                Display.displayDetail("Need to update \(key) (\(sizeofFmt(size)))")
                itemSizes[key] = size
                totalSize += size
            } else {
                items.removeValue(forKey: key)
            }
        }

        // Send updated data
        guard !items.isEmpty else {
            Display.displayDetail("No changes")
            return
        }

        if uploadLimit < totalSize {
            Display.displayWarning("Unable to send complete data, size is too big! (\(sizeofFmt(totalSize)))")
            Display.displayWarning("Must be smaller than PHP's \(phpFileLimitation) of \(sizeofFmt(uploadLimit))")
            Display.displayDetail("Chunking data uploads...")

            // Sort items by size (smallest first)
            let sortedItems = itemSizes.sorted { $0.value < $1.value }
            var remaining = items
            var chunkCount = 0

            while chunkCount < 10 && !remaining.isEmpty {
                chunkCount += 1
                Display.displayDetail("Starting upload of chunk \(chunkCount)...")

                var uploadItems: [String: [String: Any]] = [:]
                var uploadTotalSize = 0

                for (key, size) in sortedItems {
                    guard remaining[key] != nil else { continue }

                    uploadTotalSize += size
                    if uploadLimit < uploadTotalSize {
                        uploadTotalSize -= size
                        if uploadItems.isEmpty {
                            // Single item too big, skip it
                            remaining.removeValue(forKey: key)
                        }
                        try sendData(
                            totalSize: uploadTotalSize,
                            url: checkURL,
                            serial: cleanSerial,
                            items: uploadItems,
                            passphrase: passphrase,
                            timeout: timeout,
                            followRedirects: followRedirects,
                            additionalHeaders: additionalHeaders
                        )
                        break
                    } else {
                        uploadItems[key] = remaining[key]
                        remaining.removeValue(forKey: key)
                    }
                }

                if chunkCount == 10 && !remaining.isEmpty {
                    Display.displayWarning("Unable to fully upload all data after \(chunkCount) chunks!")
                }
            }
        } else {
            try sendData(
                totalSize: totalSize,
                url: checkURL,
                serial: cleanSerial,
                items: items,
                passphrase: passphrase,
                timeout: timeout,
                followRedirects: followRedirects,
                additionalHeaders: additionalHeaders
            )
        }
    }

    public static func finishRun() {
        removeRunFile()
        Display.displayDetail("## Finished run")
        Logging.rotateMainLog()
    }

    // MARK: - Private

    private static func removeRunFile() {
        try? FileManager.default.removeItem(atPath: Constants.touchFile)
    }

    private static func sendData(
        totalSize: Int,
        url: String,
        serial: String,
        items: [String: [String: Any]],
        passphrase: String,
        timeout: TimeInterval,
        followRedirects: Bool,
        additionalHeaders: [String: String]?
    ) throws {
        Display.displayDetail("Sending items (\(sizeofFmt(totalSize)))")

        // Prepare items for JSON: include hash and data
        var jsonItems: [String: [String: Any]] = [:]
        for (key, item) in items {
            var entry: [String: Any] = [:]
            if let hash = item["hash"] as? String { entry["hash"] = hash }
            if let data = item["data"] as? String { entry["data"] = data }
            jsonItems[key] = entry
        }

        let body: [String: Any] = [
            "serial": serial,
            "items": jsonItems,
            "passphrase": passphrase
        ]

        let responseData = try HTTPClient.postJSON(
            url: url,
            body: body,
            timeout: timeout,
            followRedirects: followRedirects,
            additionalHeaders: additionalHeaders
        )

        if let response = String(data: responseData, encoding: .utf8), !response.isEmpty {
            let formatted = response
                .replacingOccurrences(of: "\n\nServer", with: "\nServer")
                .replacingOccurrences(of: "\nServer", with: "\n    Server")
            Display.displayDetail(formatted)
        }
    }

    private static func getAdditionalHeaders() -> [String: String]? {
        guard let useHeaders = Preferences.pref("UseAdditionalHttpHeaders") as? Bool, useHeaders else {
            return nil
        }

        guard let headerList = Preferences.pref(Constants.additionalHTTPHeadersKey) as? [String] else {
            Display.displayError("UseAdditionalHttpHeaders defined, but not found in MunkiReport preferences")
            return nil
        }

        var headers: [String: String] = [:]
        for header in headerList {
            let parts = header.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                headers[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                    String(parts[1]).trimmingCharacters(in: .whitespaces)
            }
        }
        return headers
    }

    // MARK: - Hashing

    public static func md5Hash(ofFile path: String) -> String {
        guard FileManager.default.isReadableFile(atPath: path),
              let handle = FileHandle(forReadingAtPath: path) else {
            return "NOT A FILE"
        }
        defer { handle.closeFile() }

        var context = CC_MD5_CTX()
        CC_MD5_Init(&context)

        while autoreleasepool(invoking: {
            let chunk = handle.readData(ofLength: 65536)
            if chunk.isEmpty { return false }
            chunk.withUnsafeBytes { ptr in
                _ = CC_MD5_Update(&context, ptr.baseAddress, CC_LONG(chunk.count))
            }
            return true
        }) {}

        var digest = [UInt8](repeating: 0, count: Int(CC_MD5_DIGEST_LENGTH))
        CC_MD5_Final(&digest, &context)

        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Formatting

    public static func sizeofFmt(_ num: Int) -> String {
        var n = Double(num)
        for unit in ["B", "KB", "MB", "GB", "TB", "PB", "EB", "ZB"] {
            if abs(n) < 1000.0 {
                return String(format: "%.0f%@", n, unit)
            }
            n /= 1000.0
        }
        return String(format: "%.1fYB", n)
    }
}
