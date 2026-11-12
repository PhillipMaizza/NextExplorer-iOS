@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("Share decoding")
struct ShareDecodingTests {
    @Test("decodes a shared by me link with every field")
    func decodesFullShare() throws {
        let share = try CoreModelsFixture.shareAnyoneOwnerString.decodeISO(Share.self)
        #expect(share.id == "s1")
        #expect(share.shareToken == "tok1")
        #expect(share.ownerId == "u-owner")
        #expect(share.sourcePath == "Docs/Reports")
        #expect(share.sourceName == nil)
        #expect(share.isDirectory)
        #expect(share.accessMode == .readwrite)
        #expect(share.sharingType == .anyone)
        #expect(share.hasPassword)
        #expect(share.expiresAt == MockDate.date)
        #expect(share.label == "Quarterly")
        #expect(share.downloadCount == 7)
        #expect(share.lastAccessedAt == MockDate.date.addingTimeInterval(600))
        #expect(share.permittedUserIds == nil)
        #expect(share.createdAt == MockDate.date.addingTimeInterval(-600))
        #expect(share.updatedAt == MockDate.date)
    }

    @Test("an integer owner id decodes as a string and a missing download count is zero")
    func decodesIntegerOwnerAndDefaults() throws {
        let share = try CoreModelsFixture.shareUsersOwnerIntegerMinimal.decodeISO(Share.self)
        #expect(share.ownerId == "42")
        #expect(share.downloadCount == 0)
        #expect(share.sourcePath == nil)
        #expect(share.sourceName == "photo.jpg")
        #expect(share.sharingType == .users)
        #expect(share.accessMode == .readonly)
        #expect(share.permittedUserIds == ["u1", "u2"])
        #expect(share.expiresAt == nil)
        #expect(share.label == nil)
    }

    @Test("a share without its token fails to decode instead of producing an unusable link")
    func missingTokenThrows() {
        #expect(throws: DecodingError.self) {
            try CoreModelsFixture.shareMissingShareToken.decodeISO(Share.self)
        }
    }
}

@Suite("Share display and expiry")
struct ShareDisplayTests {
    private func share(label: String? = nil, sourceName: String? = nil, sourcePath: String? = nil, expiresAt: Date? = nil) -> Share {
        Share(
            id: "s",
            shareToken: "token",
            ownerId: "o",
            sourcePath: sourcePath,
            sourceName: sourceName,
            isDirectory: false,
            accessMode: .readonly,
            sharingType: .anyone,
            hasPassword: false,
            expiresAt: expiresAt,
            label: label,
            createdAt: MockDate.date,
            updatedAt: MockDate.date
        )
    }

    private struct NameCase: Sendable {
        let label: String?
        let sourceName: String?
        let sourcePath: String?
        let expected: String
    }

    private static let nameCases = [
        NameCase(label: "Label", sourceName: "leaf", sourcePath: "a/b", expected: "Label"),
        NameCase(label: "", sourceName: "leaf", sourcePath: "a/b", expected: "leaf"),
        NameCase(label: nil, sourceName: "leaf", sourcePath: "a/b", expected: "leaf"),
        NameCase(label: nil, sourceName: "", sourcePath: "a/b", expected: "b"),
        NameCase(label: nil, sourceName: nil, sourcePath: "a/b/", expected: "b"),
        NameCase(label: nil, sourceName: nil, sourcePath: "single", expected: "single"),
        NameCase(label: nil, sourceName: nil, sourcePath: "", expected: "token"),
        NameCase(label: nil, sourceName: nil, sourcePath: "/", expected: "token"),
        NameCase(label: nil, sourceName: nil, sourcePath: nil, expected: "token"),
    ]

    @Test("displayName prefers the label, then the leaf name, then the path leaf, then the token", arguments: nameCases)
    private func displayNamePriority(_ testCase: NameCase) {
        let value = share(label: testCase.label, sourceName: testCase.sourceName, sourcePath: testCase.sourcePath)
        #expect(value.displayName == testCase.expected)
    }

    @Test("a share with no expiry never expires")
    func noExpiryNeverExpires() {
        #expect(!share().isExpired)
    }

    @Test("a share whose expiry is long past is expired")
    func pastExpiryIsExpired() {
        #expect(share(expiresAt: .distantPast).isExpired)
        #expect(share(expiresAt: MockDate.date).isExpired)
    }

    @Test("a share whose expiry is far in the future is not expired")
    func futureExpiryIsNotExpired() {
        #expect(!share(expiresAt: .distantFuture).isExpired)
    }
}

@Suite("CreatedShare")
struct CreatedShareTests {
    private func created() throws -> CreatedShare {
        try CoreModelsFixture.shareCreatedWithUrls.decodeISO(CreatedShare.self)
    }

    @Test("decodes the share together with its two links")
    func decodesFlattenedBody() throws {
        let value = try created()
        #expect(value.share.id == "s5")
        #expect(value.share.sourcePath == "Docs/a.txt")
        #expect(value.shareUrl.absoluteString == "https://files.example.com/share/tok5")
        #expect(value.directFileUrl.absoluteString == Constants.directFileURL)
    }

    @Test("a body without the links fails to decode")
    func missingLinksThrow() {
        #expect(throws: DecodingError.self) {
            try CoreModelsFixture.shareCreatedMissingUrls.decodeISO(CreatedShare.self)
        }
    }

    @Test("the auto mode is the bare direct link and every other mode appends ?mode=")
    func directLinkModes() throws {
        let value = try created()
        let base = Constants.directFileURL
        #expect(value.directLink(mode: .auto).absoluteString == base)
        #expect(value.directLink(mode: .inline).absoluteString == base + "?mode=inline")
        #expect(value.directLink(mode: .raw).absoluteString == base + "?mode=raw")
        #expect(value.directLink(mode: .download).absoluteString == base + "?mode=download")
    }

    @Test("a mode replaces an existing query rather than stacking")
    func directLinkReplacesQuery() throws {
        let share = try CoreModelsFixture.shareCreatedWithUrls.decodeISO(Share.self)
        let value = try CreatedShare(
            share: share,
            shareUrl: TestHost.serverURL,
            directFileUrl: #require(URL(string: "https://files.example.com/file?mode=raw&x=1"))
        )
        #expect(value.directLink(mode: .download).absoluteString == "https://files.example.com/file?mode=download")
    }
}

private enum Constants {
    static let directFileURL = "https://files.example.com/api/share/tok5/file"
}
