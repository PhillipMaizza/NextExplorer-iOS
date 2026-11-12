@testable import AuthClient
import CryptoKit
import Foundation
import Testing

@Suite("PKCE")
struct PKCETests {
    /// The S256 transform written out from RFC 7636 section 4.2, independent of the production code,
    /// and proven against the RFC's own example below before it judges `generate()`.
    private func s256Challenge(of verifier: String) -> String {
        Data(SHA256.hash(data: Data(verifier.utf8)))
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    @Test("the reference transform reproduces the RFC 7636 appendix B example")
    func referenceTransformMatchesRFCVector() {
        #expect(s256Challenge(of: Constants.rfcVerifier) == Constants.rfcChallenge)
    }

    @Test("the challenge is the S256 transform of the verifier")
    func challengeIsS256OfVerifier() {
        let pkce = PKCE.generate()
        #expect(pkce.challenge == s256Challenge(of: pkce.verifier))
    }

    @Test("the verifier is 43 URL safe characters, the shortest length RFC 7636 allows, and carries no padding")
    func verifierIsURLSafe() {
        let pkce = PKCE.generate()
        #expect(pkce.verifier.count == 43)
        #expect(pkce.challenge.count == 43)
        let allowed = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        #expect(pkce.verifier.allSatisfy(allowed.contains))
        #expect(pkce.challenge.allSatisfy(allowed.contains))
    }

    @Test("every flow gets a fresh verifier")
    func verifiersDiffer() {
        let pairs = (0 ..< 8).map { _ in PKCE.generate() }
        #expect(Set(pairs.map(\.verifier)).count == pairs.count)
        #expect(Set(pairs.map(\.challenge)).count == pairs.count)
    }
}

private enum Constants {
    static let rfcVerifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
    static let rfcChallenge = "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM"
}
