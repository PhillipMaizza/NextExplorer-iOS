@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("AccountSummary")
struct AccountSummaryTests {
    private func summary(url: URL, username: String = TestAccount.username, email: String? = nil) -> AccountSummary {
        AccountSummary(id: "id", username: username, serverURL: url, isActive: true, email: email)
    }

    private struct HostCase: Sendable {
        let url: String
        let expected: String
    }

    private static let hostCases = [
        HostCase(url: TestHost.serverURLString, expected: TestHost.server),
        HostCase(url: "https://\(TestHost.serverWithPort)", expected: TestHost.serverWithPort),
        HostCase(url: "http://192.168.1.187:3660", expected: "192.168.1.187:3660"),
        HostCase(url: "\(TestHost.serverURLString)/nextexplorer", expected: TestHost.server),
    ]

    @Test("serverHost keeps an explicit port and drops a default one", arguments: hostCases)
    private func serverHostKeepsExplicitPort(_ testCase: HostCase) throws {
        let url = try #require(URL(string: testCase.url))
        #expect(summary(url: url).serverHost == testCase.expected)
    }

    @Test("a URL without a host falls back to its full text")
    func serverHostFallsBackToAbsoluteString() throws {
        let url = try #require(URL(string: "mailto:someone"))
        #expect(summary(url: url).serverHost == "mailto:someone")
    }

    @Test("displayName is the username, or the server host when the username is empty")
    func displayNameFallsBackToHost() {
        #expect(summary(url: TestHost.serverURL).displayName == TestAccount.username)
        #expect(summary(url: TestHost.serverURL, username: "").displayName == TestHost.server)
    }

    @Test("displayName falls back to the email before the server host when the username is empty")
    func displayNameFallsBackToEmail() {
        #expect(summary(url: TestHost.serverURL, email: TestAccount.email).displayName == TestAccount.username)
        let noUsername = summary(url: TestHost.serverURL, username: "", email: TestAccount.email)
        #expect(noUsername.displayName == TestAccount.email)
        #expect(summary(url: TestHost.serverURL, username: "", email: "").displayName == TestHost.server)
    }

    @Test("displayName is the server's display name first, as the web names the account")
    func displayNamePrefersTheFullName() {
        var named = summary(url: TestHost.serverURL, email: TestAccount.email)
        named.fullName = TestAccount.fullName
        #expect(named.displayName == TestAccount.fullName)
        named.fullName = ""
        #expect(named.displayName == TestAccount.username)
    }

    @Test("the server line is left out when the name already is the server")
    func serverSubtitleSkipsADuplicate() {
        #expect(summary(url: TestHost.serverURL).serverSubtitle == TestHost.server)
        #expect(summary(url: TestHost.serverURL, username: "").serverSubtitle == nil)
    }
}
