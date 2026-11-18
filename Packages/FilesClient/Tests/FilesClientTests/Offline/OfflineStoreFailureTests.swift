import CoreModels
@testable import FilesClient
import Foundation
import Testing
import TestUtils

/// A failed store leaves no half slot that could never be listed, sized or removed. The simulator does not
/// report data protection classes, so the class itself cannot be read back here.
@Suite("Offline store failure")
struct OfflineStoreFailureTests {
    private enum Constants {
        static let scopePrefix = "offline-protect-"
        static let sourcePrefix = "offline-protect-src-"
        static let folder = "Docs"
        static let bytes = 4
    }

    private func item() -> FileItem {
        FileItem(
            name: TestFile.aText,
            path: Constants.folder,
            dateModified: MockDate.date,
            size: Int64(Constants.bytes),
            kind: TestKind.text
        )
    }

    private func source() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Constants.sourcePrefix)\(TestID.name())")
        try Data(repeating: 0x61, count: Constants.bytes).write(to: url)
        return url
    }

    @Test
    func aFailedStoreLeavesNoSlotBehind() throws {
        let scope = "\(Constants.scopePrefix)\(TestID.name())"
        let store = OfflineFileStore.liveValue
        defer { store.removeAccount(scope) }
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Constants.sourcePrefix)\(TestID.name())-missing")

        #expect(throws: (any Error).self) {
            try OfflineCache.store(downloadedURL: missing, item: item(), scope: scope)
        }

        #expect(store.pinned(to: scope).totalSizeBytes() == 0)
        #expect(store.pinned(to: scope).localURL(item()) == nil)
    }
}
