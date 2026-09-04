import CryptoKit
import Foundation

/// A PKCE (RFC 7636) verifier/challenge pair for the OIDC mobile bridge. The app keeps the
/// verifier, sends only the S256 challenge into the web flow, and proves possession at the
/// exchange, so a code intercepted on the custom scheme can't be redeemed by another app.
struct PKCE: Equatable, Sendable {
    let verifier: String
    let challenge: String

    static func generate() -> PKCE {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = base64URL(Data(bytes))
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return PKCE(verifier: verifier, challenge: base64URL(Data(digest)))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
