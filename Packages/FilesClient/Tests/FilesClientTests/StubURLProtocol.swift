import Foundation

/// Local copy of `NetworkClientTests`' stub: test targets can't import another target's
/// test-only sources, so this intentionally mirrors `NetworkClient/Tests/.../StubURLProtocol.swift`.
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
    /// Every intercepted request in order, for tests asserting on a multi request flow.
    nonisolated(unsafe) static var requests: [URLRequest] = []
    nonisolated(unsafe) static var failure: URLError?
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
        Self.capturedRequest = request
        Self.requests.append(request)
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
        guard let url = request.url,
              let stub = Self.methodStubs[methodKey] ?? Self.pathStubs[url.path] ?? Self.stub
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
