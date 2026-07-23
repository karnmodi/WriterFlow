import Foundation

/// Deterministic URLSession stubbing for network-dependent tests — no real
/// requests leave the process. Register handlers via `stub(_:)`; each is
/// consumed in order (FIFO) for the matching HTTP method + path suffix.
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub {
        let statusCode: Int
        let body: Data
    }

    private struct Key: Hashable {
        let method: String
        let pathSuffix: String
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queuedStubs: [Key: [Stub]] = [:]
    nonisolated(unsafe) private static var recordedRequests: [URLRequest] = []

    static func reset() {
        lock.lock()
        queuedStubs = [:]
        recordedRequests = []
        lock.unlock()
    }

    static func stub(method: String, pathSuffix: String, statusCode: Int, json: Data) {
        lock.lock()
        let key = Key(method: method, pathSuffix: pathSuffix)
        queuedStubs[key, default: []].append(Stub(statusCode: statusCode, body: json))
        lock.unlock()
    }

    static func requests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recordedRequests
    }

    static var session: URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var capturedRequest = request
        if capturedRequest.httpBody == nil, let stream = capturedRequest.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 4096)
            defer { buffer.deallocate() }
            while stream.hasBytesAvailable {
                let count = stream.read(buffer, maxLength: 4096)
                guard count > 0 else { break }
                data.append(buffer, count: count)
            }
            capturedRequest.httpBody = data
        }
        Self.lock.lock()
        Self.recordedRequests.append(capturedRequest)
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? ""
        let matchingKey = Self.queuedStubs.keys.first { $0.method == method && path.hasSuffix($0.pathSuffix) }
        let stub = matchingKey.flatMap { key -> MockURLProtocol.Stub? in
            guard var list = Self.queuedStubs[key], !list.isEmpty else { return nil }
            let first = list.removeFirst()
            Self.queuedStubs[key] = list
            return first
        }
        Self.lock.unlock()

        guard let stub, let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
