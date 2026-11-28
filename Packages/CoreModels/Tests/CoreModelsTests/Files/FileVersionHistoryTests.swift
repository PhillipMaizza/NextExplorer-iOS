@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("FileVersionHistory decoding")
struct FileVersionHistoryTests {
    @Test("decodes the flags, the rights and the versions newest first")
    func decodesFullHistory() throws {
        let history = try CoreModelsFixture.fileVersionHistoryFull.decodeISO(FileVersionHistory.self)
        #expect(history.isEnabled)
        #expect(history.totalBytes == 3_000_000_000)
        #expect(history.rights == FileVersionHistory.Rights(
            canSee: true,
            canDownload: true,
            canRestore: false,
            canRemove: true
        ))
        #expect(history.versions.map(\.id) == ["v2", "v1"])
    }

    @Test("a version keeps its pin, label, author and availability")
    func decodesVersionDetails() throws {
        let history = try CoreModelsFixture.fileVersionHistoryFull.decodeISO(FileVersionHistory.self)
        let pinned = try #require(history.versions.first)
        #expect(pinned == FileVersion(
            id: "v2",
            size: 2_000_000_000,
            modifiedAt: MockDate.date,
            capturedAt: MockDate.date.addingTimeInterval(600),
            author: FileVersion.Author(label: "alice"),
            label: "Before refactor",
            isPinned: true,
            isAvailable: false
        ))
    }

    @Test("a version without optional fields is unpinned, anonymous and availability unknown")
    func decodesMinimalVersion() throws {
        let history = try CoreModelsFixture.fileVersionHistoryFull.decodeISO(FileVersionHistory.self)
        let plain = try #require(history.versions.last)
        #expect(plain.author == nil)
        #expect(plain.label == nil)
        #expect(!plain.isPinned)
        #expect(plain.isAvailable == nil)
        #expect(plain.modifiedAt == MockDate.date.addingTimeInterval(-3600))
        #expect(plain.capturedAt == MockDate.date.addingTimeInterval(-3000))
    }

    @Test("a history without the rights object fails to decode instead of granting rights")
    func missingRightsThrows() {
        #expect(throws: DecodingError.self) {
            try CoreModelsFixture.fileVersionHistoryMissingRights.decodeISO(FileVersionHistory.self)
        }
    }

    @Test("a version has actions when any right to restore, download or remove it is given")
    func versionActionsFollowTheRights() {
        let none = FileVersionHistory.Rights(canSee: true, canDownload: false, canRestore: false, canRemove: false)
        let removeOnly = FileVersionHistory.Rights(canSee: true, canDownload: false, canRestore: false, canRemove: true)
        #expect(!none.hasVersionActions)
        #expect(removeOnly.hasVersionActions)
    }

    @Test("a version name is capped at the server's 200 UTF-16 units, never inside a character")
    func aVersionNameIsCappedLikeTheServer() {
        let max = FileVersion.maxLabelLength
        #expect(FileVersion.cappedLabel(String(repeating: "a", count: max + 5)).utf16.count == max)
        #expect(FileVersion.cappedLabel(String(repeating: "a", count: max - 1) + "\u{1F511}") == String(
            repeating: "a",
            count: max - 1
        ))
        #expect(FileVersion.cappedLabel("v1/final") == "v1/final")
    }
}
