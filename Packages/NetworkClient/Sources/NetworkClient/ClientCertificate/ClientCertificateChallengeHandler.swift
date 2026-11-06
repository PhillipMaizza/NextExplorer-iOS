import Foundation

/// Answers `NSURLAuthenticationMethodClientCertificate` challenges from the identity store and
/// remembers how each origin's latest handshake went. A server that demands a certificate and
/// does not get an acceptable one simply drops the connection, which URLSession reports as
/// `networkConnectionLost` (indistinguishable from a real outage). The record lets
/// `NetworkError.from` turn that drop into `.clientCertificateRequired` or
/// `.clientCertificateRejected` instead of a false "offline".
///
/// `@unchecked Sendable`: all mutable state is behind `lock`.
public final class ClientCertificateChallengeHandler: @unchecked Sendable {
    enum Outcome: Equatable {
        case missing
        case presented
    }

    /// A rejected handshake fails within milliseconds of the challenge, while a reused
    /// connection that drops later never sees a new challenge. Only a failure this close to the
    /// challenge is attributed to the certificate.
    private static let attributionWindow: TimeInterval = 10

    private let store: ClientIdentityStore
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var outcomes: [ClientCertificateOrigin: (Outcome, Date)] = [:]

    public init(store: ClientIdentityStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
    }

    public static let shared = ClientCertificateChallengeHandler(store: .shared)

    /// Returns `nil` for any challenge that is not a client certificate request, so the caller
    /// falls through to its own handling (server trust).
    public func handle(_ challenge: URLAuthenticationChallenge) -> (URLSession.AuthChallengeDisposition, URLCredential?)? {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodClientCertificate else {
            return nil
        }
        let origin = ClientCertificateOrigin(protectionSpace: challenge.protectionSpace)
        let credential = store.credential(for: origin)
        record(credential == nil ? .missing : .presented, for: origin)
        guard let credential else {
            return (.performDefaultHandling, nil)
        }
        return (.useCredential, credential)
    }

    func recentOutcome(for url: URL?) -> Outcome? {
        guard let url, let origin = ClientCertificateOrigin(url: url) else { return nil }
        lock.lock()
        defer { lock.unlock() }
        guard let (outcome, date) = outcomes[origin], now().timeIntervalSince(date) <= Self.attributionWindow else {
            return nil
        }
        return outcome
    }

    private func record(_ outcome: Outcome, for origin: ClientCertificateOrigin) {
        lock.lock()
        outcomes[origin] = (outcome, now())
        lock.unlock()
    }
}
