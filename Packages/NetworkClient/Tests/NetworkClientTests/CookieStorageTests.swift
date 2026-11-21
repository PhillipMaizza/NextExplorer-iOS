import Foundation
@testable import NetworkClient
import Testing
import TestUtils

struct CookieStorageTests {
    @Test
    func aCookieWithAnExpiryStaysOutOfTheSharedDiskBackedJar() throws {
        let url = try #require(URL(string: TestHost.serverURLString))
        let cookie = try #require(HTTPCookie(properties: [
            .name: TestSession.cookieName,
            .value: TestSession.loginCookieValue,
            .domain: TestHost.server,
            .path: "/",
            .expires: Date.distantFuture,
        ]))

        HTTPCookieStorage.appSession.setCookie(cookie)
        defer { HTTPCookieStorage.appSession.deleteCookie(cookie) }

        #expect(HTTPCookieStorage.appSession !== HTTPCookieStorage.shared)
        #expect(HTTPCookieStorage.appSession.cookies(for: url)?.contains(cookie) == true)
        #expect(HTTPCookieStorage.shared.cookies(for: url)?.contains(cookie) != true)
    }
}
