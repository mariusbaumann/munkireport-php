import Foundation

public enum HTTPClientError: Error, CustomStringConvertible {
    case invalidURL(String)
    case requestFailed(statusCode: Int, message: String)
    case networkError(Error)
    case timeout

    public var description: String {
        switch self {
        case .invalidURL(let url): return "Invalid URL: \(url)"
        case .requestFailed(let code, let msg): return "HTTP \(code): \(msg)"
        case .networkError(let err): return "Network error: \(err.localizedDescription)"
        case .timeout: return "Request timed out"
        }
    }
}

public final class HTTPClient {

    public static func postJSON(
        url urlString: String,
        body: [String: Any],
        timeout: TimeInterval = 60,
        followRedirects: Bool = false,
        additionalHeaders: [String: String]? = nil
    ) throws -> Data {
        guard let url = URL(string: urlString) else {
            throw HTTPClientError.invalidURL(urlString)
        }

        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add custom headers
        if let headers = additionalHeaders {
            for (key, value) in headers {
                request.setValue(value, forHTTPHeaderField: key)
            }
        }

        // Serialize body as JSON
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let semaphore = DispatchSemaphore(value: 0)
        var responseData: Data?
        var responseError: Error?
        var httpResponse: HTTPURLResponse?

        let config = URLSessionConfiguration.default
        let delegate = followRedirects ? nil : RedirectBlocker()
        let session = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)

        let task = session.dataTask(with: request) { data, response, error in
            responseData = data
            responseError = error
            httpResponse = response as? HTTPURLResponse
            semaphore.signal()
        }
        task.resume()

        let result = semaphore.wait(timeout: .now() + timeout + 5)
        if result == .timedOut {
            task.cancel()
            throw HTTPClientError.timeout
        }

        if let error = responseError {
            throw HTTPClientError.networkError(error)
        }

        if let status = httpResponse?.statusCode, status >= 300 {
            let body = responseData.flatMap { String(data: $0, encoding: .utf8) } ?? "No response body"
            throw HTTPClientError.requestFailed(statusCode: status, message: body)
        }

        return responseData ?? Data()
    }
}

private class RedirectBlocker: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        Display.displayDetail("Denying redirect to: \(request.url?.absoluteString ?? "unknown")")
        completionHandler(nil)
    }
}
