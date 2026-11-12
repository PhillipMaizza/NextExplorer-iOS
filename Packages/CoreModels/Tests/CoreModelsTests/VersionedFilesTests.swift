@testable import CoreModels
import Foundation
import Testing
import TestUtils

struct VersionedFilesTests {
    @Test
    func aPageDecodesItsRowsTotalsAndVolumes() throws {
        let page = try CoreModelsFixture.versionedFilesPageWithRowsTotalsAndVolumes.decode(VersionedFilesPage.self)

        #expect(page.files.count == 2)
        #expect(page.files[0].folder == "Docs")
        #expect(page.files[0].zone?.kind == .volume)
        #expect(page.files[1].state == .orphaned)
        #expect(page.files[1].path == nil)
        #expect(page.files[1].zone?.kind == .personal)
        #expect(page.total == 52)
        #expect(page.totalVersions == 80)
        #expect(page.offset == 25)
        #expect(page.zones.map(\.name) == ["files"])
    }

    @Test
    func anUnknownStateAndZoneKindFallBackToLiveAndVolume() throws {
        let file = try CoreModelsFixture.versionedFilesUnknownStateAndZoneKind.decode(VersionedFile.self)

        #expect(file.state == .live)
        #expect(file.zone?.kind == .volume)
    }

    @Test(arguments: [
        (0, 0, 0, 0, false, false),
        (52, 0, 25, 25, true, false),
        (52, 25, 25, 50, true, true),
        (52, 50, 2, 52, false, true),
        (10, 0, 10, 10, false, false),
    ])
    func theRangeAndPagingFlagsFollowTheOffset(total: Int, offset: Int, shown: Int, last: Int, hasNext: Bool, hasPrevious: Bool) {
        let files = (0 ..< shown).map { VersionedFile(id: "f\($0)", name: "n") }
        let page = VersionedFilesPage(files: files, total: total, offset: offset)

        #expect(page.lastShown == (total == 0 ? 0 : last))
        #expect(page.hasNext == hasNext)
        #expect(page.hasPrevious == hasPrevious)
    }

    @Test
    func theFirstShownIsOneBasedAndZeroWhenEmpty() {
        #expect(VersionedFilesPage().firstShown == 0)
        #expect(VersionedFilesPage(files: [VersionedFile(id: "a", name: "a")], total: 30, offset: 25).firstShown == 26)
    }

    @Test
    func aDetailDecodesItsVersionsAndTotal() throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let detail = try decoder.decode(VersionedFileDetail.self, from: try CoreModelsFixture.versionedFilesDetailWithPinnedUnavailableVersion.data())

        #expect(detail.versions.map(\.id) == ["v1"])
        #expect(detail.versions.first?.isPinned == true)
        #expect(detail.versions.first?.isAvailable == false)
        #expect(detail.totalBytes == 100)
    }

    @Test
    func aDeletionReportsWhatWasDeletedAndWhatRemains() throws {
        let outcome = try CoreModelsFixture.versionedFilesDeletionWithRemaining.decode(VersionsDeletion.self)

        #expect(outcome == VersionsDeletion(deleted: 1, remaining: 4))
        #expect(try CoreModelsFixture.emptyObject.decode(VersionsDeletion.self) == VersionsDeletion())
    }

    @Test
    func aDeletionCountsTheVersionsTheServerCouldNotDelete() throws {
        let outcome = try CoreModelsFixture.versionedFilesDeletionWithFailures.decode(VersionsDeletion.self)

        #expect(outcome == VersionsDeletion(deleted: 2, remaining: 3, failed: 2))
    }
}
