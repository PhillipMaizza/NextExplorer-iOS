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
            cookieIsSecure: true,
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
        // which would have silently broken plain-HTTP homelab logins.
        let credentials = SessionCredentials(
            serverBaseURL: URL(string: "http://192.168.1.50:3000")!,
            authMode: .local,
            cookieName: TestSession.cookieName,
            cookieValue: TestSession.cookieValue,
            cookieDomain: "192.168.1.50",
            cookiePath: "/",
            cookieIsSecure: false,
            expiresAt: nil,
            username: nil
        )
        let cookie = try #require(credentials.httpCookie)
        #expect(cookie.isSecure == false)
    }
}

private enum Constants {
    static let homeServerHost = "nextexplorer.home.arpa"
}
