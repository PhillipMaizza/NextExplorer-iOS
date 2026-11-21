@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("Folder size decoding")
struct FolderSizeTests {
    @Test("an indexed folder shows its size")
    func indexedFolder() throws {
        let entries = try CoreModelsFixture.folderSizeBatchEntries.decode([FolderSize].self)
        #expect(entries[0].shownBytes == 4096)
        #expect(!entries[0].isDirty)
    }

    @Test("a folder the user cannot enter still shows its size, and a dirty one is flagged")
    func lockedAndDirtyFolder() throws {
        let entries = try CoreModelsFixture.folderSizeBatchEntries.decode([FolderSize].self)
        #expect(entries[1].shownBytes == 9_000_000)
        #expect(entries[1].isDirty)
    }

    @Test("edge case: a folder the indexer has not reached shows no figure")
    func notIndexed() throws {
        let entries = try CoreModelsFixture.folderSizeBatchEntries.decode([FolderSize].self)
        #expect(entries[2].sizeBytes == nil)
        #expect(entries[2].shownBytes == nil)
    }

    @Test("edge case: an excluded folder shows no figure")
    func excluded() throws {
        let entries = try CoreModelsFixture.folderSizeBatchEntries.decode([FolderSize].self)
        #expect(entries[3].isExcluded)
        #expect(entries[3].shownBytes == nil)
    }

    @Test("edge case: a negative size reads as unknown")
    func negativeSize() throws {
        let entry = try CoreModelsFixture.folderSizeNegativeSize.decode(FolderSize.self)
        #expect(entry.sizeBytes == nil)
        #expect(entry.shownBytes == nil)
    }
}
