@testable import FilesClient
import Foundation
import NetworkClient
import Testing

/// Parent of every live client suite that drives `StubURLProtocol`. The suites are nested extensions of this type so they all
/// inherit `.serialized`: they share the protocol's statics and must never run concurrently.
@Suite(.serialized)
struct FilesClientLiveTests {}

/// Shared fixtures for the suites nested in `FilesClientLiveTests`.
protocol FilesClientLiveHarness {}

extension FilesClientLiveHarness {
    var serverURL: URL {
        URL(string: "https://example.com")!
    }

    func makeClient() -> FilesClient {
        .live(
            networkClient: .live(protocolClasses: [StubURLProtocol.self]),
            directoryCacheStore: .testValue
        )
    }

    func stub(statusCode: Int, body: Data) {
        StubURLProtocol.failure = nil
        StubURLProtocol.stub = .init(statusCode: statusCode, headers: ["Content-Type": "application/json"], body: body)
    }

    func stub(statusCode: Int, body: Data, headers: [String: String]) {
        StubURLProtocol.failure = nil
        StubURLProtocol.stub = .init(statusCode: statusCode, headers: headers, body: body)
    }

    var browseResultJSON: Data {
        get throws { try FilesClientFixture.browseDocsDirectory.data() }
    }

    func resetStubs() {
        StubURLProtocol.stub = nil
        StubURLProtocol.failure = nil
        StubURLProtocol.pathStubs = [:]
        StubURLProtocol.methodStubs = [:]
        StubURLProtocol.requests = []
    }

    func editorStub(statusCode: Int, etag: String? = nil, fixture: FilesClientFixture = .commonEmptyObject) throws -> StubURLProtocol.Stub {
        var headers = ["Content-Type": "application/json"]
        if let etag {
            headers["ETag"] = etag
        }
        return .init(statusCode: statusCode, headers: headers, body: try fixture.data())
    }
}
