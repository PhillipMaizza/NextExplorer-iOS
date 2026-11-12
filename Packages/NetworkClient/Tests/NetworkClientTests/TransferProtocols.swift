import Foundation
import Synchronization
import TestUtils

/// Answers every request with a response that is not HTTP, which a real server never does.
final class NonHTTPURLProtocol: URLProtocol {
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        client?.urlProtocol(self, didReceive: URLResponse(url: url, mimeType: nil, expectedContentLength: 0, textEncodingName: nil), cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

/// Never answers, so a request stays in flight until it is cancelled. Reports when a request has
/// started and when it was stopped. Only the suite that cancels a transfer may use it, since the
/// signals are process wide.
final class HangingURLProtocol: URLProtocol {
    static let signals = Mutex<(started: AsyncGate, stopped: AsyncGate)>((AsyncGate(), AsyncGate()))

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.signals.withLock { $0.started }.open()
    }

    override func stopLoading() {
        Self.signals.withLock { $0.stopped }.open()
    }
}
