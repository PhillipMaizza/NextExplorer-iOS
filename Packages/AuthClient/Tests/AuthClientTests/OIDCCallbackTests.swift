@testable import AuthClient
import Foundation
import Testing

@Suite("OIDC callback")
struct OIDCCallbackTests {
    private enum Constants {
        static let base = "nextexplorer://oidc-callback"
        static let code = "a1b2c3"
        static let serverError = "access_denied"
        static let missingCode = AuthClientError.oidcFailed("callback missing code")
    }

    private func callback(_ query: String) throws -> URL {
        try #require(URL(string: "\(Constants.base)?\(query)"))
    }

    @Test("the code is read from the callback, whatever else it carries")
    func readsCode() throws {
        let url = try callback("state=x&code=\(Constants.code)&extra=1")
        #expect(try OIDCCallback.code(from: url) == Constants.code)
    }

    @Test("a server error wins, even next to a code")
    func serverErrorWins() throws {
        let url = try callback("error=\(Constants.serverError)&code=\(Constants.code)")
        #expect(throws: AuthClientError.oidcFailed(Constants.serverError)) {
            try OIDCCallback.code(from: url)
        }
    }

    @Test("a callback with no code, or an empty one, is refused", arguments: ["", "state=x", "code="])
    func missingOrEmptyCodeIsRefused(query: String) throws {
        let url = try callback(query)
        #expect(throws: Constants.missingCode) {
            try OIDCCallback.code(from: url)
        }
    }
}
