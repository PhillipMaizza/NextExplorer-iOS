@testable import CoreModels
import Testing
import TestUtils

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
        #expect(!CredentialRules.isEmailShaped(TestValue.blank))
        #expect(!CredentialRules.isEmailShaped(TestUser.jane))
        #expect(!CredentialRules.isEmailShaped("jane@"))
        #expect(!CredentialRules.isEmailShaped("@example.com"))
        #expect(CredentialRules.isEmailShaped("admin@localhost"))
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
        #expect(CredentialRules.isPasswordLongEnough(TestAccount.totpCode))
        #expect(CredentialRules.isPasswordLongEnough("a much longer passphrase"))
    }

    @Test("edge case: counts UTF-16 units like the server's JavaScript length")
    func countsUTF16Units() {
        #expect(CredentialRules.isPasswordLongEnough("abcd\u{1F600}"))
        #expect(CredentialRules.isPasswordLongEnough("\u{1F600}\u{1F600}\u{1F600}"))
        #expect(!CredentialRules.isPasswordLongEnough("abcd\u{E9}"))
    }
}
