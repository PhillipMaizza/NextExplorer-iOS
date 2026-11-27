@testable import CoreModels
import Foundation
import Testing
import TestUtils

struct SharePermissionsTests {
    struct ChoiceCase: Sendable, CustomTestStringConvertible {
        let accessMode: ShareAccessMode
        let permissions: SharePermissions
        let choice: ShareAccessChoice

        var testDescription: String {
            "\(accessMode) \(permissions) is \(choice)"
        }
    }

    @Test("A share opens on the choice its flags match, and on Custom when they match none", arguments: [
        ChoiceCase(accessMode: .readonly, permissions: SharePermissions(canDownload: false), choice: .viewOnly),
        ChoiceCase(accessMode: .readonly, permissions: SharePermissions(), choice: .canDownload),
        ChoiceCase(accessMode: .readonly, permissions: SharePermissions(canDelete: false), choice: .canDownload),
        ChoiceCase(accessMode: .readwrite, permissions: SharePermissions(), choice: .canEdit),
        ChoiceCase(accessMode: .readwrite, permissions: SharePermissions(canUpload: false), choice: .custom),
        ChoiceCase(accessMode: .readwrite, permissions: SharePermissions(canDownload: false), choice: .custom),
    ])
    func choiceFromFlags(_ testCase: ChoiceCase) {
        #expect(ShareAccessChoice(accessMode: testCase.accessMode, permissions: testCase.permissions) == testCase
            .choice)
    }

    @Test("Each preset sets the server flags behind it and leaves the rest as they were")
    func presetsSetTheirFlags() {
        let mixed = SharePermissions(canDelete: false, canUpload: false, showsVersions: true)

        #expect(ShareAccessChoice.viewOnly.applied(to: mixed, from: .custom) == SharePermissions(
            canDownload: false, canDelete: false, canUpload: false, showsVersions: true
        ))
        #expect(ShareAccessChoice.canDownload.applied(to: SharePermissions(canDownload: false), from: .viewOnly)
            == SharePermissions())
        #expect(ShareAccessChoice.canEdit.applied(to: mixed, from: .custom) == SharePermissions(showsVersions: true))
        #expect(ShareAccessChoice.custom.applied(to: mixed, from: .canEdit) == mixed)
        #expect(ShareAccessChoice.viewOnly.accessMode == .readonly)
        #expect(ShareAccessChoice.custom.accessMode == .readwrite)
    }

    @Test("Custom starts from what the previous preset allowed, so a read only share gains no changes")
    func customStartsFromThePreviousPreset() {
        let stored = SharePermissions(canDownload: false, showsVersions: true)

        #expect(ShareAccessChoice.custom.applied(to: stored, from: .viewOnly) == SharePermissions(
            canDownload: false, canDelete: false, canCreateFolders: false, canCreateFiles: false, canUpload: false,
            showsVersions: true
        ))
        #expect(ShareAccessChoice.custom.applied(to: SharePermissions(), from: .canDownload) == SharePermissions(
            canDelete: false, canCreateFolders: false, canCreateFiles: false, canUpload: false
        ))
        #expect(ShareAccessChoice.custom.applied(to: SharePermissions(), from: .canEdit) == SharePermissions())
    }

    @Test("Custom is offered for a folder, and for a file only when it already is Custom")
    func customOnlyForFolders() {
        #expect(ShareAccessChoice.options(isDirectory: true, current: .canDownload).contains(.custom))
        #expect(!ShareAccessChoice.options(isDirectory: false, current: .canDownload).contains(.custom))
        #expect(ShareAccessChoice.options(isDirectory: false, current: .custom).contains(.custom))
    }

    @Test("Versions are on by default for specific users and off for anyone with the link")
    func versionsDefaults() {
        #expect(SharePermissions.defaults(for: .users).showsVersions)
        #expect(SharePermissions.defaults(for: .users).canDownloadVersions)
        #expect(!SharePermissions.defaults(for: .anyone).showsVersions)
    }

    @Test("Every flag decodes from the share, and a share without them allows everything but versions")
    func decodesFlags() throws {
        let custom = try CoreModelsFixture.shareCustomPermissions.decodeISO(Share.self)
        let minimal = try CoreModelsFixture.shareUsersOwnerIntegerMinimal.decodeISO(Share.self)

        #expect(custom.permissions == SharePermissions(
            canDelete: false, canCreateFiles: false, showsVersions: true
        ))
        #expect(minimal.permissions == SharePermissions())
    }

    @Test("A cached share keeps its flags")
    func cachedShareKeepsItsFlags() throws {
        let share = try CoreModelsFixture.shareCustomPermissions.decodeISO(Share.self)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let cached = try decoder.decode(Share.self, from: encoder.encode(share))

        #expect(cached == share)
    }

    @Test("Downloading versions is never sent on while versions are hidden")
    func versionsDownloadNeedsVersionsVisible() throws {
        let data = try JSONEncoder().encode(SharePermissions(showsVersions: false, canDownloadVersions: true))
        let body = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Bool])

        #expect(body["versionsDownload"] == false)
        #expect(body.count == 7)
    }
}
