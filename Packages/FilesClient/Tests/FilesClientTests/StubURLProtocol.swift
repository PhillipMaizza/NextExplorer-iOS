import Foundation

/// Local copy of `NetworkClientTests`' stub: test targets can't import another target's
/// test only sources, so this intentionally mirrors `NetworkClient/Tests/.../StubURLProtocol.swift`.
///
/// Safe only because `FilesClientLiveTests` (the only suite that touches these statics) is
/// declared `@Suite(.serialized)`: tests never run concurrently against this shared state.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        let statusCode: Int
        let headers: [String: String]
        let body: Data
    }

    nonisolated(unsafe) static var stub: Stub?
    /// Per URL path answers that win over `stub`, for flows that make more than one request.
    nonisolated(unsafe) static var pathStubs: [String: Stub] = [:]
    /// Per `"METHOD /path"` answers that win over `pathStubs`, for flows that read and write one URL.
    nonisolated(unsafe) static var methodStubs: [String: Stub] = [:]
    /// Per `"METHOD /path"` answers handed out one per request, in order, before `methodStubs` takes over.
    nonisolated(unsafe) static var methodSequences: [String: [Stub]] = [:]
    /// `"METHOD /path"` keys whose requests are recorded and then left unanswered until cancelled.
    nonisolated(unsafe) static var heldMethodKeys: Set<String> = []
    /// Every intercepted request in order, for tests asserting on a multi request flow.
    /// Guarded by a lock: URLSession appends from its own thread while tests poll for requests.
    private nonisolated(unsafe) static var recordedRequests: [URLRequest] = []
    private static let requestsLock = NSLock()
    static var requests: [URLRequest] {
        get { requestsLock.withLock { recordedRequests } }
        set { requestsLock.withLock { recordedRequests = newValue } }
    }

    nonisolated(unsafe) static var failure: URLError?
    /// Runs as each request arrives, for tests that change app state while a transfer is in flight.
    nonisolated(unsafe) static var onRequest: (@Sendable () -> Void)?
    /// Last intercepted request, for tests asserting on URL/method/body construction.
    nonisolated(unsafe) static var capturedRequest: URLRequest?
    nonisolated(unsafe) static var capturedRequestBody: Data?

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.onRequest?()
        Self.capturedRequest = request
        Self.requestsLock.withLock { Self.recordedRequests.append(request) }
        Self.capturedRequestBody = request.httpBody ?? request.httpBodyStream.map { stream -> Data in
            stream.open()
            defer { stream.close() }
            var data = Data()
            let bufferSize = 4_096
            var buffer = [UInt8](repeating: 0, count: bufferSize)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: bufferSize)
                if read <= 0 {
                    break
                }
                data.append(buffer, count: read)
            }
            return data
        }
        if let failure = Self.failure {
            client?.urlProtocol(self, didFailWithError: failure)
            return
        }
        let methodKey = "\(request.httpMethod ?? "GET") \(request.url?.path ?? "")"
        if Self.heldMethodKeys.contains(methodKey) {
            return
        }
        var sequenced: Stub?
        if var queue = Self.methodSequences[methodKey], !queue.isEmpty {
            sequenced = queue.removeFirst()
            Self.methodSequences[methodKey] = queue
        }
        guard let url = request.url,
              let stub = sequenced ?? Self.methodStubs[methodKey] ?? Self.pathStubs[url.path] ?? Self.stub
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        guard let response = HTTPURLResponse(
            url: url,
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        ) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
