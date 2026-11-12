@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("CachedDirectory")
struct CachedDirectoryTests {
    private func access() -> FileAccess {
        FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: true, canDownload: true)
    }

    private func listing(etag: String?) -> CachedDirectory {
        CachedDirectory(
            path: TestFolder.docs,
            items: [FileItem(name: TestFile.aText, path: TestFolder.docs, dateModified: MockDate.date, size: 12, kind: TestKind.text)],
            access: access(),
            fetchedAt: MockDate.date,
            etag: etag
        )
    }

    @Test("an entry survives being written to disk and read back, with or without an ETag", arguments: [TestETag.first, nil])
    func roundTripKeepsEtag(etag: String?) throws {
        let original = listing(etag: etag)
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(CachedDirectory.self, from: data) == original)
    }

    @Test("an old entry without an ETag decodes with its stored schema version so the reader can discard it")
    func staleSchemaIsReadAsStored() throws {
        let entry = try CoreModelsFixture.cachedDirectoryStaleSchemaWithoutEtag.decode(CachedDirectory.self)
        #expect(entry.etag == nil)
        #expect(entry.schemaVersion == 0)
        #expect(entry.schemaVersion != CachedDirectory.currentSchemaVersion)
        #expect(entry.path == TestFolder.docs)
        #expect(entry.fetchedAt == MockDate.date)
        #expect(entry.items.map(\.name) == [TestFile.aText])
        #expect(entry.items.first?.dateModified == MockDate.date.addingTimeInterval(-600))
        #expect(entry.access.canWrite)
        #expect(entry.access.canCreateFolder, "falls back to canUpload when the saved listing predates the flag")
    }
}
