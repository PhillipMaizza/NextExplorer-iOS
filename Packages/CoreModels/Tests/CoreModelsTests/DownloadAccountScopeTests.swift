@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("DownloadAccountScope")
struct DownloadAccountScopeTests {
    private struct Case: Sendable {
        let serverURL: String
        let userID: String
        let expected: String
    }

    // Each expected value is the first 16 bytes of SHA256("<server url>\n<user id>") in hex.
    private static let cases = [
        Case(serverURL: TestHost.serverURLString, userID: TestAccount.username, expected: "436be0c9b422c8fbf1109c9b784d62ae"),
        Case(serverURL: TestHost.serverURLString, userID: TestUser.alice, expected: "ca3a7aa61f638c98c6cf60832296a577"),
        Case(serverURL: "https://\(TestHost.serverWithPort)", userID: TestAccount.username, expected: "9327c2349c43308461afad3979a060f9"),
        Case(serverURL: TestHost.serverURLString, userID: "", expected: "d61861fc371442b64349057ca03d8171"),
    ]

    @Test("derives the folder name from the server URL and user id", arguments: cases)
    private func derivesKnownIdentifier(_ testCase: Case) throws {
        let url = try #require(URL(string: testCase.serverURL))
        #expect(DownloadAccountScope.identifier(serverURL: url, userID: testCase.userID) == testCase.expected)
    }

    @Test("a different user, server or port gives a different folder so accounts never share files")
    func differentAccountsNeverCollide() throws {
        let identifiers = try Set(Self.cases.map { testCase in
            try DownloadAccountScope.identifier(serverURL: #require(URL(string: testCase.serverURL)), userID: testCase.userID)
        })
        #expect(identifiers.count == Self.cases.count)
    }

    @Test("the identifier is 32 lowercase hex characters, safe as a folder name")
    func identifierIsFilesystemSafe() {
        let identifier = DownloadAccountScope.identifier(serverURL: TestHost.serverURL, userID: TestAccount.username)
        #expect(identifier.count == 32)
        #expect(identifier.allSatisfy { "0123456789abcdef".contains($0) })
    }

}
