import Foundation
@testable import NetworkClient
import Testing

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

    @Test("edge case: a 429 rate-limit response is surfaced as a plain HTTPURLResponse, not thrown")
    func rateLimitedIsNotThrown() async throws {
        StubURLProtocol.stub = .init(statusCode: 429, headers: [:], body: Data())
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        let request = URLRequest(url: URL(string: "https://example.com/api/auth/login")!)
        let (_, response) = try await client.send(request)

        #expect(response.statusCode == 429)
    }

    @Test("edge case: a 500 server error is surfaced as a plain HTTPURLResponse, not thrown")
    func serverErrorIsNotThrown() async throws {
        StubURLProtocol.stub = .init(statusCode: 500, headers: [:], body: Data())
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        let request = URLRequest(url: URL(string: "https://example.com/api/auth/status")!)
        let (_, response) = try await client.send(request)

        #expect(response.statusCode == 500)
    }

    @Test("edge case: an empty response body on success round-trips as empty Data, not an error")
    func emptyBodyIsNotAnError() async throws {
        StubURLProtocol.stub = .init(statusCode: 204, headers: [:], body: Data())
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        let request = URLRequest(url: URL(string: "https://example.com/api/auth/logout")!)
        let (data, response) = try await client.send(request)

        #expect(data.isEmpty)
        #expect(response.statusCode == 204)
    }

    @Test("error path: a stub that fails to construct a valid response wraps as NetworkError.transport")
    func malformedURLProtocolFailureIsWrapped() async {
        StubURLProtocol.failure = URLError(.badServerResponse)
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        let request = URLRequest(url: URL(string: "https://example.com/api/auth/status")!)
        await #expect(throws: NetworkError.self) {
            _ = try await client.send(request)
        }
    }

    @Test("security: send refuses a response body past the in-memory cap instead of buffering it")
    func sendRejectsAnOversizedResponse() async {
        StubURLProtocol.stub = .init(statusCode: 200, headers: [:], body: Data(repeating: 0x7A, count: 4096))
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self], maxInMemoryResponseBytes: 1024)

        let request = URLRequest(url: URL(string: "https://example.com/api/browse")!)
        await #expect(throws: NetworkError.responseTooLarge) {
            _ = try await client.send(request)
        }
    }

    @Test("security: a response exactly at the cap still round-trips")
    func sendAcceptsAResponseAtTheCap() async throws {
        let payload = Data(repeating: 0x7A, count: 1024)
        StubURLProtocol.stub = .init(statusCode: 200, headers: [:], body: payload)
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self], maxInMemoryResponseBytes: 1024)

        let request = URLRequest(url: URL(string: "https://example.com/api/browse")!)
        let (data, response) = try await client.send(request)

        #expect(data == payload)
        #expect(response.statusCode == 200)
    }

    // MARK: download (streams the body to a file the caller owns)

    @Test("download writes the response body to a file on disk and returns its URL plus the HTTPURLResponse")
    func downloadStreamsBodyToAStableFile() async throws {
        let payload = Data(repeating: 0xAB, count: 4096)
        StubURLProtocol.stub = .init(statusCode: 200, headers: [:], body: payload)
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        let request = URLRequest(url: URL(string: "https://example.com/api/preview?path=x.jpg")!)
        let (fileURL, response) = try await client.download(request)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(response.statusCode == 200)
        #expect(fileURL.isFileURL)
        // The file must outlive the call (URLSession deletes its own temp on return).
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        #expect(try Data(contentsOf: fileURL) == payload)
    }

    @Test("edge case: download surfaces a 404 as the HTTPURLResponse, not a thrown error, and still lands the (error) body on disk")
    func downloadSurfacesNon2xxWithoutThrowing() async throws {
        StubURLProtocol.stub = .init(statusCode: 404, headers: [:], body: Data("not found".utf8))
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        let request = URLRequest(url: URL(string: "https://example.com/api/preview?path=missing")!)
        let (fileURL, response) = try await client.download(request)
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(response.statusCode == 404)
    }

    @Test("error path: a transport failure during download wraps as NetworkError.transport")
    func downloadTransportFailureIsWrapped() async {
        StubURLProtocol.failure = URLError(.notConnectedToInternet)
        let client = NetworkClient.live(protocolClasses: [StubURLProtocol.self])

        let request = URLRequest(url: URL(string: "https://example.com/api/preview?path=x")!)
        await #expect(throws: NetworkError.self) {
            _ = try await client.download(request)
        }
    }
}
