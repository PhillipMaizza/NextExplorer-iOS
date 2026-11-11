@testable import CoreModels
import Foundation
import Testing

struct VersionedFilesTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    @Test
    func aPageDecodesItsRowsTotalsAndVolumes() throws {
        let page = try decode(VersionedFilesPage.self, """
        {
            "files": [
                { "id": "f1", "name": "a.txt", "relativePath": "Docs/a.txt", "folder": "Docs", "path": "files/Docs/a.txt",
                  "state": "live", "versions": 3, "bytes": 3000, "newest": "2026-11-11T07:00:00.000Z",
                  "zone": { "id": "z1", "kind": "volume", "name": "files" } },
                { "id": "f2", "name": "b.txt", "relativePath": "b.txt", "folder": "", "path": null,
                  "state": "orphaned", "versions": 1, "bytes": 10, "newest": null,
                  "zone": { "id": "z2", "kind": "personal", "name": "alice" } }
            ],
            "total": 52, "totalBytes": 99999, "totalVersions": 80, "limit": 25, "offset": 25,
            "zones": [ { "id": "z1", "kind": "volume", "name": "files" } ],
            "states": ["live", "trashed", "orphaned"], "sorts": ["bytes"]
        }
        """)

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
        let file = try decode(VersionedFile.self, #"{ "id": "f", "name": "x", "state": "weird", "zone": { "id": "z", "kind": "other", "name": "n" } }"#)

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
        let detail = try decoder.decode(VersionedFileDetail.self, from: Data("""
        {
            "file": { "id": "f1", "name": "a.txt" },
            "versions": [
                { "id": "v1", "size": 100, "modifiedAt": "2026-11-11T07:00:00Z", "capturedAt": "2026-11-11T07:01:00Z",
                  "author": { "label": "alice" }, "label": "before edit", "pinned": true, "available": false }
            ],
            "totalBytes": 100
        }
        """.utf8))

        #expect(detail.versions.map(\.id) == ["v1"])
        #expect(detail.versions.first?.isPinned == true)
        #expect(detail.versions.first?.isAvailable == false)
        #expect(detail.totalBytes == 100)
    }

    @Test
    func aDeletionReportsWhatWasDeletedAndWhatRemains() throws {
        let outcome = try decode(VersionsDeletion.self, #"{ "items": [ { "id": "v1", "status": "purged" } ], "deleted": 1, "remaining": 4 }"#)

        #expect(outcome == VersionsDeletion(deleted: 1, remaining: 4))
        #expect(try decode(VersionsDeletion.self, "{}") == VersionsDeletion())
    }

    @Test
    func aDeletionCountsTheVersionsTheServerCouldNotDelete() throws {
        let outcome = try decode(VersionsDeletion.self, #"{ "items": [ { "id": "a", "status": "purged" }, { "id": "b", "status": "failed" }, { "id": "c", "status": "not-found" }, { "id": "d", "status": "pending" } ], "deleted": 2, "remaining": 3 }"#)

        #expect(outcome == VersionsDeletion(deleted: 2, remaining: 3, failed: 2))
    }
}
