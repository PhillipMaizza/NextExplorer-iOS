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

    public func isExpired(now: Date) -> Bool {
        guard let expiresAt else { return false }
        return expiresAt <= now
    }
}

public enum ClientCertificateImportError: Error, Equatable, Sendable {
    case wrongPassword
    case invalidFile
    case noIdentity
    case storage
}
