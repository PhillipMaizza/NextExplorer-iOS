import Foundation
import Security

/// A decoded PKCS#12 identity, kept in process memory only. `SecIdentity` and `SecCertificate`
/// are immutable CoreFoundation objects that are safe to share across threads.
struct PKCS12Identity: @unchecked Sendable {
    let identity: SecIdentity
    let chain: [SecCertificate]

    /// Decoding runs a password based key derivation, so call it off the main actor.
    static func decode(_ data: Data, passphrase: String) throws(ClientCertificateImportError) -> PKCS12Identity {
        let options: [String: Any] = [
            kSecImportExportPassphrase as String: passphrase,
            kSecImportToMemoryOnly as String: true,
        ]
        var items: CFArray?
        let status = SecPKCS12Import(data as CFData, options as CFDictionary, &items)
        switch status {
        case errSecSuccess:
            break
        case errSecAuthFailed, errSecPkcs12VerifyFailure:
            throw .wrongPassword
        default:
            throw .invalidFile
        }
        guard
            let entries = items as? [[String: Any]],
            let entry = entries.first(where: { $0[kSecImportItemIdentity as String] != nil }),
            let identityRef = entry[kSecImportItemIdentity as String],
            CFGetTypeID(identityRef as CFTypeRef) == SecIdentityGetTypeID()
        else {
            throw .noIdentity
        }
        // swiftlint:disable:next force_cast
        let identity = identityRef as! SecIdentity
        let chain = (entry[kSecImportItemCertChain as String] as? [SecCertificate]) ?? []
        return PKCS12Identity(identity: identity, chain: chain)
    }

    var leafCertificate: SecCertificate? {
        var certificate: SecCertificate?
        guard SecIdentityCopyCertificate(identity, &certificate) == errSecSuccess else { return nil }
        return certificate
    }

    var summary: ClientCertificateSummary {
        let leaf = leafCertificate
        let subject = leaf.flatMap { SecCertificateCopySubjectSummary($0) as String? } ?? ""
        let issuer = chain.dropFirst().first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
        let expiresAt = leaf.flatMap { SecCertificateCopyNotValidAfterDate($0) as Date? }
        return ClientCertificateSummary(subject: subject, issuer: issuer, expiresAt: expiresAt)
    }

    /// The credential handed back to a client certificate challenge. The intermediates ride
    /// along so a server that trusts only the root can still build the path. A file without a
    /// chain must pass `nil`, never an empty array: CFNetwork indexes into a non nil array and
    /// traps on an empty one.
    var credential: URLCredential {
        let intermediates = Array(chain.dropFirst())
        return URLCredential(
            identity: identity,
            certificates: intermediates.isEmpty ? nil : intermediates,
            // Never cached by URLSession: every handshake asks the store again, so a removed or
            // replaced certificate is never presented from a cache.
            persistence: .none
        )
    }
}
