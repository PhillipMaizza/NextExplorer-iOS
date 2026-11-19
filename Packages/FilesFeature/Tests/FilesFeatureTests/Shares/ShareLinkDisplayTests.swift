import CoreModels
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

struct ShareLinkDisplayTests {
    private enum Constants {
        static let token = "AbC123xyz0"
    }

    private func share() -> Share {
        Share(
            id: "s1", shareToken: Constants.token, ownerId: "u1", isDirectory: false, accessMode: .readonly,
            sharingType: .anyone, hasPassword: false, createdAt: MockDate.date, updatedAt: MockDate.date
        )
    }

    struct OriginCase: Sendable {
        let server: String
        let expectedOrigin: String
    }

    nonisolated static let origins = [
        OriginCase(server: TestHost.serverURLString, expectedOrigin: TestHost.serverURLString),
        OriginCase(server: "https://\(TestHost.serverWithPort)", expectedOrigin: "https://\(TestHost.serverWithPort)"),
        OriginCase(server: "http://\(TestHost.server)/nextcloud/sub?x=1", expectedOrigin: "http://\(TestHost.server)"),
    ]

    @Test(arguments: origins)
    func theShareLinkIsBuiltOnTheServersOriginOnly(_ testCase: OriginCase) throws {
        let serverURL = try #require(URL(string: testCase.server))

        #expect(share().shareLink(serverURL: serverURL) == "\(testCase.expectedOrigin)/share/\(Constants.token)")
    }

    @Test
    func aServerAddressWithoutAHostIsUsedAsWritten() throws {
        let serverURL = try #require(URL(string: TestHost.server))

        #expect(share().shareLink(serverURL: serverURL) == "\(TestHost.server)/share/\(Constants.token)")
    }

    struct ModeCase: Sendable {
        let mode: DirectLinkMode
        let expectedSuffix: String
    }

    nonisolated static let modes = [
        ModeCase(mode: .auto, expectedSuffix: ""),
        ModeCase(mode: .inline, expectedSuffix: "?mode=inline"),
        ModeCase(mode: .raw, expectedSuffix: "?mode=raw"),
        ModeCase(mode: .download, expectedSuffix: "?mode=download"),
    ]

    @Test(arguments: modes)
    func theDirectLinkOnlyCarriesAModeQueryWhenTheModeIsNotAuto(_ testCase: ModeCase) {
        #expect(
            share().directLink(serverURL: TestHost.serverURL, mode: testCase.mode)
                == "\(TestHost.serverURLString)/api/share/\(Constants.token)/file\(testCase.expectedSuffix)"
        )
    }
}
