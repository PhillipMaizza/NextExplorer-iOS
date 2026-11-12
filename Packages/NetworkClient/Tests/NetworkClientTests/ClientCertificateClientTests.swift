import Foundation
import Keychain
@testable import NetworkClient
import Testing
import TestUtils

@Suite("ClientCertificateClient")
struct ClientCertificateClientTests {
    private let first = ClientCertificateOrigin(host: TestHost.firstServer, port: 443)
    private let second = ClientCertificateOrigin(host: TestHost.secondServer, port: 8443)

    @Test("the in memory client starts empty and installs a summary named after the host")
    func inMemoryInstall() async throws {
        let client = ClientCertificateClient.inMemory()
        #expect(await client.summary(first) == nil)

        let summary = try await client.install(Data(), TestAccount.password, first)

        #expect(summary == ClientCertificateSummary(subject: TestHost.firstServer))
        #expect(await client.summary(first) == summary)
        #expect(await client.summary(second) == nil)
    }

    @Test("the in memory client can be seeded and removes one origin without touching the other")
    func inMemoryRemove() async {
        let seeded = [first: ClientCertificateSummary(subject: "a"), second: ClientCertificateSummary(subject: "b")]
        let client = ClientCertificateClient.inMemory(seeded)

        await client.remove(first)

        #expect(await client.summary(first) == nil)
        #expect(await client.summary(second) == ClientCertificateSummary(subject: "b"))
    }

    @Test("removeAll keeps exactly the servers named and an empty set removes everything")
    func inMemoryRemoveAll() async {
        let seeded = [first: ClientCertificateSummary(subject: "a"), second: ClientCertificateSummary(subject: "b")]
        let client = ClientCertificateClient.inMemory(seeded)

        await client.removeAll([second])
        #expect(await client.summary(first) == nil)
        #expect(await client.summary(second) == ClientCertificateSummary(subject: "b"))

        await client.removeAll([])
        #expect(await client.summary(second) == nil)
    }

    @Test("two default test clients never share installed certificates")
    func testValueIsFreshEachTime() async throws {
        let one = ClientCertificateClient.testValue
        let other = ClientCertificateClient.testValue
        _ = try await one.install(Data(), "", first)
        #expect(await other.summary(first) == nil)
    }

    @Test("the live client installs, reads, removes and clears through the identity store")
    func liveClientUsesTheStore() async throws {
        let store = ClientIdentityStore(keychain: .inMemory())
        let client = ClientCertificateClient.live(store: store)

        let summary = try await client.install(MutualTLSFixtures.data(.clientIdentity), MutualTLSFixtures.passphrase, first)
        _ = try await client.install(MutualTLSFixtures.data(.clientIdentity), MutualTLSFixtures.passphrase, second)

        #expect(summary.subject == TestCertificate.subject)
        #expect(await client.summary(first) == summary)
        #expect(store.summary(for: first) == summary)

        await client.remove(first)
        #expect(store.summary(for: first) == nil)
        #expect(store.summary(for: second) != nil)

        await client.removeAll([])
        #expect(store.summary(for: second) == nil)
    }

    @Test("the live client reports a wrong passphrase as the import error and stores nothing")
    func liveClientInstallFailure() async {
        let store = ClientIdentityStore(keychain: .inMemory())
        let client = ClientCertificateClient.live(store: store)

        await #expect(throws: ClientCertificateImportError.wrongPassword) {
            _ = try await client.install(MutualTLSFixtures.data(.clientIdentity), TestAccount.rejectedPassword, first)
        }
        #expect(store.summary(for: first) == nil)
    }

    @Test("hasCertificate follows the URL's origin including its port and rejects a URL without a host")
    func hasCertificateByURL() throws {
        let store = ClientIdentityStore(keychain: .inMemory())
        try store.install(pkcs12: MutualTLSFixtures.data(.clientIdentity), passphrase: MutualTLSFixtures.passphrase, for: second)

        #expect(store.hasCertificate(for: URL(filePath: "/")) == false)
        #expect(try store.hasCertificate(for: #require(URL(string: "https://\(TestHost.secondServer):8443/api"))))
        #expect(try !store.hasCertificate(for: #require(URL(string: "https://\(TestHost.secondServer)"))))
        #expect(try !store.hasCertificate(for: #require(URL(string: "https://\(TestHost.firstServer):8443"))))
    }
}
