import Foundation
import Testing
@testable import NetworkClient

@Suite("NetworkClient live implementation", .serialized)
struct NetworkClientLiveTests {
    init() {
        StubURLProtocol.stub = nil
        StubURLProtocol.failure = nil
    }

    @Test("returns the response body and HTTPURLResponse on success")
    func successReturnsBodyAndResponse() async throws {
        StubURLProtocol.stub = .init(statusCode: 200, headers: [:], body: Data(#"{"ok":true}"#.utf8))
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        let request = URLRequest(url: URL(string: "https://example.com/api/auth/status")!)
        let (data, response) = try await client.send(request)

        #expect(response.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == #"{"ok":true}"#)
    }

    @Test("surfaces a 401 as a plain HTTPURLResponse, not a thrown error")
    func unauthorizedIsNotThrown() async throws {
        StubURLProtocol.stub = .init(statusCode: 401, headers: [:], body: Data())
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        let request = URLRequest(url: URL(string: "https://example.com/api/auth/me")!)
        let (_, response) = try await client.send(request)

        #expect(response.statusCode == 401)
    }

    @Test("wraps a transport failure (e.g. offline homelab server) as NetworkError.transport")
    func transportFailureIsWrapped() async {
        StubURLProtocol.failure = URLError(.cannotConnectToHost)
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        let request = URLRequest(url: URL(string: "https://example.com/api/auth/status")!)
        await #expect(throws: NetworkError.self) {
            _ = try await client.send(request)
        }
    }
}
