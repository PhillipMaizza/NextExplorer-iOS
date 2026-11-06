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
    /// Origins that have answered since the certificate last changed: the handshake works there,
    /// so a dropped connection is the network, never the certificate.
    private var verified: Set<ClientCertificateOrigin> = []

    public init(store: ClientIdentityStore, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.now = now
        store.addChangeObserver { [weak self] _ in self?.forgetVerified() }
    }

    public static let shared = ClientCertificateChallengeHandler(store: .shared)

    /// Swaps every session for a new one whenever a certificate changes, so the next request
    /// handshakes with the new identity (or none). Flushing is not enough: a flushed session
    /// resumes its cached TLS session and the server still sees the old identity. When every
    /// certificate is removed (the last account signed out) running requests are cancelled too.
    func replaceOnCertificateChange(_ sessions: [ReplaceableSession]) {
        store.addChangeObserver { [sessions = sessions.map(WeakSession.init)] change in
            for session in sessions {
                session.value?.replace(cancelsRunningTasks: change == .allRemoved)
            }
        }
    }

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
        // Read before taking `lock`: the store has its own lock and calls back into this one.
        let isExpired = store.summary(for: origin)?.isExpired(now: now()) == true
        lock.lock()
        defer { lock.unlock() }
        guard
            let (outcome, date) = outcomes[origin],
            now().timeIntervalSince(date) <= Self.attributionWindow
        else {
            return nil
        }
        // A certificate that expired since the origin last answered is the likely reason a fresh
        // handshake failed, so it still counts there.
        if verified.contains(origin), !(outcome == .presented && isExpired) {
            return nil
        }
        return outcome
    }

    /// nginx with `ssl_verify_client on` does not drop the handshake: it answers 400 with a page
    /// naming the certificate problem. Only that page counts, so a genuine 400 from the server
    /// behind the proxy is never mistaken for a certificate refusal.
    func certificateError(status: Int, bodyPrefix: @autoclosure () -> Data, url: URL?) -> NetworkError? {
        guard status == 400 else { return nil }
        let text = String(decoding: bodyPrefix().prefix(Self.proxyPageScanBytes), as: UTF8.self).lowercased()
        if text.contains("no required ssl certificate was sent") {
            return .clientCertificateRequired
        }
        guard text.contains("ssl certificate error") else { return nil }
        return recentOutcome(for: url) == .missing ? .clientCertificateRequired : .clientCertificateRejected
    }

    private static let proxyPageScanBytes = 4096

    /// The server answered, so the handshake went through: a later drop on this origin is a real
    /// outage (offline fallback applies), not the certificate.
    func recordResponse(for url: URL?) {
        guard let url, let origin = ClientCertificateOrigin(url: url) else { return }
        lock.lock()
        outcomes[origin] = nil
        verified.insert(origin)
        lock.unlock()
    }

    private func forgetVerified() {
        lock.lock()
        verified.removeAll()
        lock.unlock()
    }

    private func record(_ outcome: Outcome, for origin: ClientCertificateOrigin) {
        lock.lock()
        outcomes[origin] = (outcome, now())
        lock.unlock()
    }
}

private struct WeakSession: @unchecked Sendable {
    weak var value: ReplaceableSession?

    init(_ value: ReplaceableSession) {
        self.value = value
    }
}
