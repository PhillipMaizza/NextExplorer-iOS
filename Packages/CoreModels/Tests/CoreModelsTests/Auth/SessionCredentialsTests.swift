@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("SessionCredentials")
struct SessionCredentialsTests {
    @Test("reconstructs an HTTPCookie with matching attributes")
    func reconstructsHTTPCookie() {
        let credentials = SessionCredentials(
            serverBaseURL: URL(string: "https://nextexplorer.home.arpa")!,
            authMode: .local,
            cookieName: "appSession",
            cookieValue: "xyz",
            cookieDomain: Constants.homeServerHost,
            cookiePath: "/",
            isCookieSecure: true,
            expiresAt: nil,
            username: nil
        )
        let cookie = credentials.httpCookie
        #expect(cookie?.name == "appSession")
        #expect(cookie?.value == "xyz")
        #expect(cookie?.domain == Constants.homeServerHost)
        #expect(cookie?.isSecure == true)
    }

    @Test("edge case: a non-secure cookie stays non-secure after reconstruction")
    func reconstructsNonSecureHTTPCookie() throws {
        // Regression test: HTTPCookiePropertyKey.secure's mere PRESENCE marks a cookie
        // secure regardless of its value: previously this always produced isSecure == true,
        // which would have silently broken plain HTTP homelab logins.
        let credentials = SessionCredentials(
            serverBaseURL: URL(string: "http://192.168.1.50:3000")!,
            authMode: .local,
            cookieName: TestSession.cookieName,
            cookieValue: TestSession.cookieValue,
            cookieDomain: "192.168.1.50",
            cookiePath: "/",
            isCookieSecure: false,
            expiresAt: nil,
            username: nil
        )
        let cookie = try #require(credentials.httpCookie)
        #expect(cookie.isSecure == false)
    }

    @Test("a session saved before the email was kept still loads, with no email")
    func decodesSessionSavedWithoutEmail() throws {
        let credentials = try CoreModelsFixture.sessionCredentialsSavedWithoutEmail.decode(SessionCredentials.self)
        #expect(credentials.username == TestAccount.username)
        #expect(credentials.cookieValue == TestSession.cookieValue)
        #expect(credentials.email == nil)
        #expect(credentials.displayName == nil)
        #expect(credentials.isCookieSecure)
    }

    @Test("a session saved again keeps the stored key names, so an older build still reads it")
    func encodesTheStoredKeyNames() throws {
        let credentials = try CoreModelsFixture.sessionCredentialsSavedWithoutEmail.decode(SessionCredentials.self)
        let json = try #require(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(credentials)) as? [String: Any]
        )
        #expect(json["cookieIsSecure"] as? Bool == true)
    }
}

private enum Constants {
    static let homeServerHost = "nextexplorer.home.arpa"
}
