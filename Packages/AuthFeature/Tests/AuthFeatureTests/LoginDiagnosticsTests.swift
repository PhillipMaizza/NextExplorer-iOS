import AuthClient
@testable import AuthFeature
import Foundation
import Testing
import TestUtils

@Suite("LoginDiagnostics")
struct LoginDiagnosticsTests {
    private let timestamp = MockDate.date

    private let allErrors: [AuthClientError] = [
        .invalidCredentials, .sessionExpired, .sessionCookieMissing, .network("n"), .decoding("d"),
        .keychain("k"), .server(statusCode: 500), .noAuthMethodsEnabled, .oidcCancelled, .oidcFailed("o"),
        .secondFactorRequired, .invalidCode, .secondFactorExpired, .rateLimited,
        .clientCertificateRequired, .clientCertificateRejected,
    ]

    // MARK: - What is described, never what was typed

    @Test("an email shaped name is described by shape and length, not by its text")
    func emailShapedIdentifier() {
        let text = LoginDiagnostics.describe(identifier: "alice.smith@example.com")
        #expect(text == "email shaped, 23 characters")
        #expect(!text.contains(TestUser.alice))
    }

    @Test("a username shaped name is described by shape and length, not by its text")
    func usernameShapedIdentifier() {
        let text = LoginDiagnostics.describe(identifier: TestUser.asmith)
        #expect(text == "username shaped, 6 characters")
        #expect(!text.contains(TestUser.asmith))
    }

    @Test("edge case: surrounding whitespace is reported, because it is a real cause of a refused sign in")
    func identifierWhitespaceIsReported() {
        let text = LoginDiagnostics.describe(identifier: "  asmith \n")
        #expect(text == "username shaped, 6 characters, surrounding whitespace removed")
    }

    @Test("edge case: non ASCII characters are reported")
    func identifierNonASCIIIsReported() {
        let text = LoginDiagnostics.describe(identifier: "jos\u{00E9}")
        #expect(text.contains("non ASCII characters"))
    }

    @Test("edge case: an empty name is described without crashing")
    func emptyIdentifier() {
        #expect(LoginDiagnostics.describe(identifier: TestValue.blank) == "username shaped, 0 characters, surrounding whitespace removed")
    }

    @Test("a password is only ever empty or set")
    func passwordIsEmptyOrSet() {
        #expect(LoginDiagnostics.describe(password: "") == "empty")
        #expect(LoginDiagnostics.describe(password: TestAccount.password) == "set")
    }

    @Test("a six digit code and a recovery code are told apart without printing either")
    func codeShapes() {
        #expect(LoginDiagnostics.describe(code: TestAccount.totpCode) == "6 digits")
        #expect(LoginDiagnostics.describe(code: " 123456 ") == "6 digits")
        #expect(LoginDiagnostics.describe(code: "12345") == "other, 5 characters")
        #expect(LoginDiagnostics.describe(code: TestAccount.recoveryCode) == "other, 11 characters")
        #expect(!LoginDiagnostics.describe(code: TestAccount.recoveryCode).contains("2HSMP"))
    }

    @Test("a server address is described by scheme and port only")
    func serverDescription() throws {
        let custom = try #require(URL(string: "http://192.168.1.187:3663"))
        let standard = try #require(URL(string: TestHost.serverURLString))
        #expect(LoginDiagnostics.describe(server: custom) == "http, port 3663")
        #expect(LoginDiagnostics.describe(server: standard) == "https, default port")
        #expect(!LoginDiagnostics.describe(server: custom).contains("192.168"))
    }

    // MARK: - Errors

    @Test("every error has a description")
    func everyErrorIsDescribed() {
        for error in allErrors {
            #expect(!LoginDiagnostics.describe(error, host: nil).isEmpty)
        }
    }

    @Test("a network error has the server's host blanked out, in any case")
    func networkErrorHostIsRedacted() {
        let text = LoginDiagnostics.describe(
            .network("Could not connect to Files.Example.com on port 443"),
            host: TestHost.server
        )
        #expect(!text.lowercased().contains(TestHost.server))
        #expect(text.contains("<server>"))
    }

    @Test("edge case: a long error detail is cut so the log stays readable")
    func longDetailIsCut() {
        let text = LoginDiagnostics.describe(.decoding(String(repeating: "x", count: 5000)), host: nil)
        #expect(text.count < 200)
    }

    @Test("only a second factor request and a dismissed single sign on are not problems")
    func problemClassification() {
        let notProblems = allErrors.filter { !LoginDiagnostics.isProblem($0) }
        #expect(notProblems == [.oidcCancelled, .secondFactorRequired])
    }

    // MARK: - The log

    @Test("hasProblem is false until a problem is recorded")
    func hasProblem() {
        var log = LoginDiagnostics()
        #expect(!log.hasProblem)
        log.record("connecting", at: timestamp)
        #expect(!log.hasProblem)
        log.record("sign in: rejected", isProblem: true, at: timestamp)
        #expect(log.hasProblem)
    }

    @Test("edge case: the log keeps only the newest 200 entries")
    func logIsBounded() {
        var log = LoginDiagnostics()
        for index in 0 ..< 250 {
            log.record("entry \(index)", at: timestamp)
        }
        #expect(log.entries.count == 200)
        #expect(log.entries.first?.text == "entry 50")
        #expect(log.entries.last?.text == "entry 249")
    }

    @Test("rendered text puts the header first, then dated lines with problems marked")
    func renderedText() {
        var log = LoginDiagnostics()
        log.record("connecting: https, default port", at: timestamp)
        log.record("sign in: rejected", isProblem: true, at: timestamp)
        let lines = log.rendered(header: ["NextExplorer 1.1.4 (1)"]).split(separator: "\n", omittingEmptySubsequences: false)
        #expect(lines.map(String.init) == [
            "NextExplorer 1.1.4 (1)",
            "",
            "2023-11-14T22:13:20.000Z connecting: https, default port",
            "2023-11-14T22:13:20.000Z PROBLEM sign in: rejected",
        ])
    }

    @Test("edge case: an empty log still renders its header")
    func emptyLogRendersHeader() {
        #expect(LoginDiagnostics().rendered(header: ["header"]) == "header\n")
    }

    @Test("the environment header names the app version and the OS")
    func environmentHeader() {
        let header = LoginDiagnostics.environmentHeader()
        #expect(header.count == 2)
        #expect(header[0].hasPrefix("NextExplorer "))
        #expect(header[1].hasPrefix("OS: "))
    }
}
