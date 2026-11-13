import Dependencies
import DependenciesMacros
import Foundation

/// Feature facing access to the client certificates the app presents during TLS handshakes.
@DependencyClient
public struct ClientCertificateClient: Sendable {
    public var summary: @Sendable (_ origin: ClientCertificateOrigin) async -> ClientCertificateSummary?
    /// Decodes and stores a PKCS#12 file for `origin`, replacing any existing certificate.
    public var install: @Sendable (
        _ pkcs12: Data,
        _ passphrase: String,
        _ origin: ClientCertificateOrigin
    ) async throws -> ClientCertificateSummary
    public var remove: @Sendable (_ origin: ClientCertificateOrigin) async -> Void
    /// Removes every certificate except those for the given servers (an empty set removes all).
    public var removeAll: @Sendable (_ except: Set<ClientCertificateOrigin>) async -> Void
}

public extension ClientCertificateClient {
    static func live(store: ClientIdentityStore) -> ClientCertificateClient {
        ClientCertificateClient(
            summary: { origin in
                await Task.detached(priority: .userInitiated) { store.summary(for: origin) }.value
            },
            install: { pkcs12, passphrase, origin in
                try await Task.detached(priority: .userInitiated) {
                    try store.install(pkcs12: pkcs12, passphrase: passphrase, for: origin)
                }.value
            },
            remove: { origin in
                await Task.detached(priority: .userInitiated) { store.remove(for: origin) }.value
            },
            removeAll: { keep in
                await Task.detached(priority: .userInitiated) { store.removeAll(except: keep) }.value
            }
        )
    }

    /// An in memory stand in for previews and tests, optionally seeded with installed summaries.
    static func inMemory(_ seeded: [ClientCertificateOrigin: ClientCertificateSummary] = [:])
        -> ClientCertificateClient
    {
        let storage = LockIsolated(seeded)
        return ClientCertificateClient(
            summary: { storage.value[$0] },
            install: { _, _, origin in
                let summary = ClientCertificateSummary(subject: origin.host)
                storage.withValue { $0[origin] = summary }
                return summary
            },
            remove: { origin in storage.withValue { $0[origin] = nil } },
            removeAll: { keep in storage.withValue { $0 = $0.filter { keep.contains($0.key) } } }
        )
    }
}

extension ClientCertificateClient: DependencyKey {
    public static var liveValue: ClientCertificateClient {
        .live(store: .shared)
    }

    public static let previewValue: ClientCertificateClient = .inMemory()
    /// Nothing installed by default, so a feature that only reads the status on appear needs no
    /// override in its tests. A fresh store each time, so tests never share what they install.
    public static var testValue: ClientCertificateClient {
        .inMemory()
    }
}

public extension DependencyValues {
    var clientCertificateClient: ClientCertificateClient {
        get { self[ClientCertificateClient.self] }
        set { self[ClientCertificateClient.self] = newValue }
    }
}
