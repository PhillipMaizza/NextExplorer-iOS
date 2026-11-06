import Foundation
import Keychain
@testable import NetworkClient
import Testing

@Suite("Client certificates (mTLS)", .serialized)
struct ClientCertificateTests {
    private func makeClient(store: ClientIdentityStore) throws -> NetworkClient {
        let anchor = try MutualTLSFixtures.certificateAuthority()
        return NetworkClient.live(
            trustEvaluator: DevCATrustEvaluator(anchor: anchor),
            certificates: ClientCertificateChallengeHandler(store: store),
            cookieStorage: HTTPCookieStorage()
        )
    }

    private func install(_ name: String, in store: ClientIdentityStore, for url: URL) throws {
        let origin = try #require(ClientCertificateOrigin(url: url))
        try store.install(
            pkcs12: MutualTLSFixtures.data(name, "p12"),
            passphrase: MutualTLSFixtures.passphrase,
            for: origin
        )
    }

    private func request(_ client: NetworkClient, _ baseURL: URL) async throws -> (Data, HTTPURLResponse) {
        try await client.send(URLRequest(url: baseURL.appending(path: "api/auth/status")))
    }

    @Test("A valid certificate gets through the handshake", arguments: ["client", "client-legacy"])
    func validCertificate(fixture: String) async throws {
        let server = try MutualTLSTestServer()
        let baseURL = try await server.start()
        defer { server.stop() }
        let store = ClientIdentityStore(keychain: .inMemory())
        try install(fixture, in: store, for: baseURL)

        let (data, response) = try await request(makeClient(store: store), baseURL)

        #expect(response.statusCode == 200)
        #expect(String(decoding: data, as: UTF8.self) == "ok")
    }

    @Test("No certificate is reported as required, never as offline")
    func missingCertificate() async throws {
        let server = try MutualTLSTestServer()
        let baseURL = try await server.start()
        defer { server.stop() }
        let client = try makeClient(store: ClientIdentityStore(keychain: .inMemory()))

        await #expect(throws: NetworkError.clientCertificateRequired) {
            try await request(client, baseURL)
        }
    }

    @Test("A certificate from an untrusted issuer is reported as rejected")
    func rejectedCertificate() async throws {
        let server = try MutualTLSTestServer()
        let baseURL = try await server.start()
        defer { server.stop() }
        let store = ClientIdentityStore(keychain: .inMemory())
        try install("rogue-client", in: store, for: baseURL)

        await #expect(throws: NetworkError.clientCertificateRejected) {
            try await request(makeClient(store: store), baseURL)
        }
    }

    @Test("Downloads present the certificate too")
    func downloadPresentsCertificate() async throws {
        let server = try MutualTLSTestServer()
        let baseURL = try await server.start()
        defer { server.stop() }
        let store = ClientIdentityStore(keychain: .inMemory())
        try install("client", in: store, for: baseURL)

        let (fileURL, response) = try await makeClient(store: store).download(URLRequest(url: baseURL))
        defer { try? FileManager.default.removeItem(at: fileURL) }

        #expect(response.statusCode == 200)
        #expect(try String(contentsOf: fileURL, encoding: .utf8) == "ok")
    }

    @Test("A wrong password and a junk file are told apart")
    func importErrors() throws {
        let store = ClientIdentityStore(keychain: .inMemory())
        let origin = ClientCertificateOrigin(host: "localhost", port: 443)

        #expect(throws: ClientCertificateImportError.wrongPassword) {
            try store.install(pkcs12: MutualTLSFixtures.data("client", "p12"), passphrase: "nope", for: origin)
        }
        #expect(throws: ClientCertificateImportError.invalidFile) {
            try store.install(pkcs12: Data("not a certificate".utf8), passphrase: "", for: origin)
        }
        #expect(store.summary(for: origin) == nil)
    }

    @Test("An installed certificate survives a relaunch and can be removed")
    func persistence() throws {
        let keychain = KeychainClient.inMemory()
        let origin = ClientCertificateOrigin(host: "Files.Example.com", port: 8443)
        let summary = try ClientIdentityStore(keychain: keychain).install(
            pkcs12: MutualTLSFixtures.data("client", "p12"),
            passphrase: MutualTLSFixtures.passphrase,
            for: origin
        )
        #expect(summary.subject == "Dev Client")
        #expect(summary.issuer == "NextExplorer mTLS Dev CA")
        #expect(summary.expiresAt != nil)

        let relaunched = ClientIdentityStore(keychain: keychain)
        #expect(relaunched.summary(for: ClientCertificateOrigin(host: "files.example.com", port: 8443)) == summary)
        #expect(relaunched.credential(for: origin) != nil)
        #expect(relaunched.summary(for: ClientCertificateOrigin(host: "files.example.com", port: 443)) == nil)

        relaunched.remove(for: origin)
        #expect(relaunched.summary(for: origin) == nil)
        #expect(ClientIdentityStore(keychain: keychain).summary(for: origin) == nil)
    }

    @Test("Origins use the scheme default port when the URL has none")
    func origins() {
        #expect(ClientCertificateOrigin(url: URL(string: "https://Example.com")!) == ClientCertificateOrigin(host: "example.com", port: 443))
        #expect(ClientCertificateOrigin(url: URL(string: "http://example.com/api")!) == ClientCertificateOrigin(host: "example.com", port: 80))
        #expect(ClientCertificateOrigin(url: URL(string: "https://192.168.1.10:3662")!)?.port == 3662)
        #expect(ClientCertificateOrigin(url: URL(string: "file:///tmp/x")!) == nil)
    }

    @Test("A dropped connection is only blamed on the certificate right after a challenge")
    func attribution() {
        let clock = MutableClock()
        let handler = ClientCertificateChallengeHandler(
            store: ClientIdentityStore(keychain: .inMemory()),
            now: { clock.now }
        )
        let url = URL(string: "https://example.com/api/browse")!
        let dropped = URLError(.networkConnectionLost)

        #expect(NetworkError.from(dropped, url: url, certificates: handler) == .offline)

        _ = handler.handle(ClientCertificateChallengeFixture.make(host: "example.com", port: 443))
        #expect(NetworkError.from(dropped, url: url, certificates: handler) == .clientCertificateRequired)
        #expect(NetworkError.from(URLError(.notConnectedToInternet), url: url, certificates: handler) == .offline)
        #expect(NetworkError.from(dropped, url: URL(string: "https://other.example.com")!, certificates: handler) == .offline)

        clock.advance(by: 60)
        #expect(NetworkError.from(dropped, url: url, certificates: handler) == .offline)
    }

    @Test("Server trust challenges are left to the trust evaluator")
    func ignoresOtherChallenges() {
        let handler = ClientCertificateChallengeHandler(store: ClientIdentityStore(keychain: .inMemory()))
        let challenge = ClientCertificateChallengeFixture.make(
            host: "example.com", port: 443, method: NSURLAuthenticationMethodServerTrust
        )
        #expect(handler.handle(challenge) == nil)
    }
}

private final class MutableClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current = Date(timeIntervalSince1970: 1_800_000_000)

    var now: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current += seconds
        lock.unlock()
    }
}

private enum ClientCertificateChallengeFixture {
    private final class Sender: NSObject, URLAuthenticationChallengeSender {
        func use(_: URLCredential, for _: URLAuthenticationChallenge) {}
        func continueWithoutCredential(for _: URLAuthenticationChallenge) {}
        func cancel(_: URLAuthenticationChallenge) {}
    }

    static func make(
        host: String,
        port: Int,
        method: String = NSURLAuthenticationMethodClientCertificate
    ) -> URLAuthenticationChallenge {
        let space = URLProtectionSpace(host: host, port: port, protocol: "https", realm: nil, authenticationMethod: method)
        return URLAuthenticationChallenge(
            protectionSpace: space,
            proposedCredential: nil,
            previousFailureCount: 0,
            failureResponse: nil,
            error: nil,
            sender: Sender()
        )
    }
}
