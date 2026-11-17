@testable import CoreModels
import Foundation
import Testing
import TestUtils

@Suite("Folder size decoding")
struct FolderSizeTests {
    @Test("an indexed folder carries its size and count")
    func indexedFolder() throws {
        let entries = try CoreModelsFixture.folderSizeBatchEntries.decode([FolderSize].self)
        #expect(entries[0].sizeBytes == 4096)
        #expect(entries[0].entryCount == 12)
        #expect(entries[0].hasSize)
        #expect(!entries[0].dirty)
    }

    @Test("a folder the user cannot enter still reports its size, and a dirty one is flagged")
    func lockedAndDirtyFolder() throws {
        let entries = try CoreModelsFixture.folderSizeBatchEntries.decode([FolderSize].self)
        #expect(!entries[1].canEnter)
        #expect(entries[1].hasSize)
        #expect(entries[1].dirty)
    }

    @Test("edge case: a folder the indexer has not reached shows no figure")
    func notIndexed() throws {
        let entries = try CoreModelsFixture.folderSizeBatchEntries.decode([FolderSize].self)
        #expect(entries[2].sizeBytes == nil)
        #expect(!entries[2].hasSize)
    }

    @Test("edge case: an excluded folder shows no figure")
    func excluded() throws {
        let entries = try CoreModelsFixture.folderSizeBatchEntries.decode([FolderSize].self)
        #expect(entries[3].excluded)
        #expect(!entries[3].hasSize)
    }

    @Test("edge case: a negative or missing size reads as unknown")
    func oddValues() throws {
        let entry = try CoreModelsFixture.folderSizeNegativeSize.decode(FolderSize.self)
        #expect(entry.sizeBytes == nil)
        #expect(!entry.hasSize)
    }
}
