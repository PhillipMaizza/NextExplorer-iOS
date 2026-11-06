import Foundation
import Keychain

/// Holds the client certificates the user imported, one per server origin, and answers TLS
/// client certificate challenges with them. The PKCS#12 bytes and their passphrase persist in
/// the keychain (`ThisDeviceOnly`, so they never sync or restore onto another device); the
/// decoded identity is kept in memory after first use so a challenge never repeats the key
/// derivation. Every URLSession in the app shares the one live instance.
///
/// `@unchecked Sendable`: all mutable state is behind `lock`.
public final class ClientIdentityStore: @unchecked Sendable {
    private struct Record: Codable, Equatable {
        var pkcs12: Data
        var passphrase: String
        var summary: ClientCertificateSummary
    }

    /// What is known about one origin. The record (bytes, passphrase, summary) is a cheap keychain
    /// read; the identity costs a password based key derivation, so it is decoded only when a
    /// handshake first asks for it, and then kept.
    private enum Entry {
        case missing
        case stored(Record, PKCS12Identity?)
    }

    private let keychain: KeychainClient
    private let lock = NSLock()
    private var entries: [ClientCertificateOrigin: Entry] = [:]
    private var changeObservers: [@Sendable () -> Void] = []

    public init(keychain: KeychainClient) {
        self.keychain = keychain
    }

    public static let shared = ClientIdentityStore(keychain: .live(configuration: .clientIdentity))

    /// Validates and saves `pkcs12` for `origin`, replacing any certificate already there.
    @discardableResult
    public func install(
        pkcs12: Data,
        passphrase: String,
        for origin: ClientCertificateOrigin
    ) throws(ClientCertificateImportError) -> ClientCertificateSummary {
        let decoded = try PKCS12Identity.decode(pkcs12, passphrase: passphrase)
        let record = Record(pkcs12: pkcs12, passphrase: passphrase, summary: decoded.summary)
        do {
            try keychain.save(origin.keychainKey, JSONEncoder().encode(record))
        } catch {
            throw .storage
        }
        updateIndex { $0.insert(origin) }
        setEntry(.stored(record, decoded), for: origin)
        notifyChange()
        return record.summary
    }

    /// Every origin with a certificate stored, kept beside the records so they can all be found
    /// and removed at a session boundary (the keychain wrapper has no way to list its items).
    public func installedOrigins() -> Set<ClientCertificateOrigin> {
        lock.lock()
        defer { lock.unlock() }
        return loadIndex()
    }

    /// Removes every certificate except those for `keep`: the servers an account is still
    /// signed in to. Signing out of the last account passes an empty set, so the next person to
    /// use the device can't reach an mTLS server with the previous user's identity.
    public func removeAll(except keep: Set<ClientCertificateOrigin>) {
        for origin in installedOrigins().subtracting(keep) {
            remove(for: origin)
        }
    }

    /// A failed keychain delete leaves the certificate in place, so the caller reading the summary
    /// back sees the truth instead of a "None" that would come back on the next launch.
    public func remove(for origin: ClientCertificateOrigin) {
        guard (try? keychain.delete(origin.keychainKey)) != nil else { return }
        updateIndex { $0.remove(origin) }
        setEntry(.missing, for: origin)
        notifyChange()
    }

    private static let indexKey = "clientIdentity.index"

    /// Call with `lock` held.
    private func loadIndex() -> Set<ClientCertificateOrigin> {
        guard
            let data = try? keychain.load(Self.indexKey),
            let origins = try? JSONDecoder().decode(Set<ClientCertificateOrigin>.self, from: data)
        else { return [] }
        return origins
    }

    private func updateIndex(_ change: (inout Set<ClientCertificateOrigin>) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        var origins = loadIndex()
        change(&origins)
        if origins.isEmpty {
            try? keychain.delete(Self.indexKey)
        } else if let data = try? JSONEncoder().encode(origins) {
            try? keychain.save(Self.indexKey, data)
        }
    }

    /// Called after a certificate is installed, replaced or removed. Sessions use it to drop
    /// their pooled connections, which stay authenticated with the identity they opened with.
    func addChangeObserver(_ observer: @escaping @Sendable () -> Void) {
        lock.lock()
        changeObservers.append(observer)
        lock.unlock()
    }

    private func notifyChange() {
        lock.lock()
        let observers = changeObservers
        lock.unlock()
        observers.forEach { $0() }
    }

    /// Cheap enough for a view to ask: no key derivation, at most one keychain read per origin.
    public func summary(for origin: ClientCertificateOrigin) -> ClientCertificateSummary? {
        guard case let .stored(record, _) = entry(for: origin) else { return nil }
        return record.summary
    }

    public func hasCertificate(for url: URL) -> Bool {
        guard let origin = ClientCertificateOrigin(url: url) else { return false }
        return summary(for: origin) != nil
    }

    /// Decodes the identity on first use. Called from URLSession delegate queues, never the main
    /// actor.
    func credential(for origin: ClientCertificateOrigin) -> URLCredential? {
        guard case let .stored(record, cached) = entry(for: origin) else { return nil }
        if let cached {
            return cached.credential
        }
        guard let decoded = try? PKCS12Identity.decode(record.pkcs12, passphrase: record.passphrase) else {
            return nil
        }
        lock.lock()
        if case .stored(let current, nil) = entries[origin], current.pkcs12 == record.pkcs12 {
            entries[origin] = .stored(record, decoded)
        }
        lock.unlock()
        return decoded.credential
    }

    private func entry(for origin: ClientCertificateOrigin) -> Entry {
        lock.lock()
        let cached = entries[origin]
        lock.unlock()
        if let cached {
            return cached
        }
        let loaded = loadFromKeychain(origin)
        // An install or remove that landed while the keychain was being read wins.
        lock.lock()
        defer { lock.unlock() }
        if let raced = entries[origin] {
            return raced
        }
        entries[origin] = loaded
        return loaded
    }

    private func loadFromKeychain(_ origin: ClientCertificateOrigin) -> Entry {
        guard
            let data = try? keychain.load(origin.keychainKey),
            let record = try? JSONDecoder().decode(Record.self, from: data)
        else {
            return .missing
        }
        return .stored(record, nil)
    }

    private func setEntry(_ entry: Entry, for origin: ClientCertificateOrigin) {
        lock.lock()
        entries[origin] = entry
        lock.unlock()
    }
}

public extension KeychainConfiguration {
    static let clientIdentity = KeychainConfiguration(service: "app.nextplorer.clientIdentity")
}
