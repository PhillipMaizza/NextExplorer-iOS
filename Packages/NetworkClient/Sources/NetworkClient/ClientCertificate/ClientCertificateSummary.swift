import Foundation

/// What the app shows about an installed client certificate. Read once at import time so the
/// UI never has to decode the PKCS#12 file again.
public struct ClientCertificateSummary: Equatable, Sendable, Codable {
    public var subject: String
    public var issuer: String?
    public var expiresAt: Date?

    public init(subject: String, issuer: String? = nil, expiresAt: Date? = nil) {
        self.subject = subject
        self.issuer = issuer
        self.expiresAt = expiresAt
    }

    public enum Expiry: Equatable, Sendable {
        case valid
        /// Within `expiryWarningWindow` of expiring: time to ask for a new one.
        case expiringSoon
        case expired
    }

    /// Two weeks: enough notice to get a new certificate before the server starts refusing it.
    public static let expiryWarningWindow: TimeInterval = 14 * 24 * 60 * 60

    public func isExpired(now: Date) -> Bool {
        expiry(now: now) == .expired
    }

    public func expiry(now: Date) -> Expiry {
        guard let expiresAt else { return .valid }
        if expiresAt <= now {
            return .expired
        }
        return expiresAt.timeIntervalSince(now) <= Self.expiryWarningWindow ? .expiringSoon : .valid
    }
}

public enum ClientCertificateImportError: Error, Equatable, Sendable {
    case wrongPassword
    case invalidFile
    case noIdentity
    case storage
}
