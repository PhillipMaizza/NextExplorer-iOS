@testable import CoreModels
import Testing

@Suite("CredentialRules")
struct CredentialRulesTests {
    // MARK: Email shape

    @Test("accepts a plain address")
    func acceptsPlainAddress() {
        #expect(CredentialRules.isEmailShaped("jane@example.com"))
        #expect(CredentialRules.isEmailShaped("a@b.co"))
        #expect(CredentialRules.isEmailShaped("first.last+tag@sub.example.co.uk"))
    }

    @Test("trims surrounding whitespace before checking")
    func trimsWhitespace() {
        #expect(CredentialRules.isEmailShaped("  jane@example.com \n"))
    }

    @Test("rejects clearly-not-an-email input")
    func rejectsMalformed() {
        #expect(!CredentialRules.isEmailShaped(""))
        #expect(!CredentialRules.isEmailShaped("   "))
        #expect(!CredentialRules.isEmailShaped("jane"))
        #expect(!CredentialRules.isEmailShaped("jane@"))
        #expect(!CredentialRules.isEmailShaped("@example.com"))
        #expect(!CredentialRules.isEmailShaped("jane@example"))
        #expect(!CredentialRules.isEmailShaped("jane @example.com"))
        #expect(!CredentialRules.isEmailShaped("jane@@example.com"))
        #expect(!CredentialRules.isEmailShaped("jane@exa mple.com"))
    }

    // MARK: Password length

    @Test("mirrors the server's 6-character minimum")
    func passwordMinimum() {
        #expect(CredentialRules.minimumPasswordLength == 6)
        #expect(!CredentialRules.isPasswordLongEnough(""))
        #expect(!CredentialRules.isPasswordLongEnough("12345"))
        #expect(CredentialRules.isPasswordLongEnough("123456"))
        #expect(CredentialRules.isPasswordLongEnough("a much longer passphrase"))
    }

    @Test("edge case: counts characters, not bytes")
    func countsCharacters() {
        // Six emoji = 6 characters even though each is multiple bytes.
        #expect(CredentialRules.isPasswordLongEnough("😀😀😀😀😀😀"))
        #expect(!CredentialRules.isPasswordLongEnough("😀😀😀😀😀"))
    }
}
