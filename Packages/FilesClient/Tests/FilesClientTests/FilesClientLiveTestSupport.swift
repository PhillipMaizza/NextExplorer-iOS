@testable import FilesClient
import Foundation
import NetworkClient
import Testing
import TestUtils

/// Parent of every live client suite that drives `StubURLProtocol`. The suites are nested extensions of this type so
/// they all
/// inherit `.serialized`: they share the protocol's statics and must never run concurrently.
@Suite(.serialized)
struct FilesClientLiveTests {}

/// Shared fixtures for the suites nested in `FilesClientLiveTests`.
protocol FilesClientLiveHarness {}

extension FilesClientLiveHarness {
    var serverURL: URL {
        URL(string: TestHost.exampleURLString)!
    }

    func makeClient() -> FilesClient {
        .live(
            networkClient: .live(protocolClasses: [StubURLProtocol.self]),
            directoryCacheStore: .testValue
        )
    }

    func stub(statusCode: Int, body: Data) {
        StubURLProtocol.failure = nil
        StubURLProtocol.stub = .init(
            statusCode: statusCode,
            headers: [HTTPHeaderField.contentType: MIMEType.json],
            body: body
        )
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

    func editorStub(
        statusCode: Int,
        etag: String? = nil,
        fixture: FilesClientFixture = .commonEmptyObject
    ) throws -> StubURLProtocol.Stub {
        var headers = [HTTPHeaderField.contentType: MIMEType.json]
        if let etag {
            headers[HTTPHeaderField.etag] = etag
        }
        return try .init(statusCode: statusCode, headers: headers, body: fixture.data())
    }
}
