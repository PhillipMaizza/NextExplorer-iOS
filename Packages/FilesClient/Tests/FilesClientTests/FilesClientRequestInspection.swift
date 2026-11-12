import Foundation
import NetworkClient
import Testing

/// Reads back what `StubURLProtocol` last saw, so a route test states its method, path and body in one place.
extension FilesClientLiveHarness {
    /// Clears every stub and capture, then installs one answer for the next request.
    func prepare(statusCode: Int, fixture: FilesClientFixture) throws {
        resetStubs()
        try stub(statusCode: statusCode, body: fixture.data())
    }

    /// Clears every stub and capture, then installs an empty answer (a 204 style reply).
    func prepareEmpty(statusCode: Int) {
        resetStubs()
        stub(statusCode: statusCode, body: Data())
    }

    func expectRequest(_ method: HTTPMethod, _ path: String, sourceLocation: SourceLocation = #_sourceLocation) throws {
        let request = try #require(StubURLProtocol.capturedRequest, sourceLocation: sourceLocation)
        #expect(request.httpMethod == method.rawValue, sourceLocation: sourceLocation)
        #expect(request.url?.path == path, sourceLocation: sourceLocation)
    }

    func expectNoBody(sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(StubURLProtocol.capturedRequestBody == nil, sourceLocation: sourceLocation)
    }

    func expectJSONBody(_ expected: [String: Any], sourceLocation: SourceLocation = #_sourceLocation) throws {
        let data = try #require(StubURLProtocol.capturedRequestBody, sourceLocation: sourceLocation)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any], sourceLocation: sourceLocation)
        #expect(NSDictionary(dictionary: object) == NSDictionary(dictionary: expected), sourceLocation: sourceLocation)
    }
}
