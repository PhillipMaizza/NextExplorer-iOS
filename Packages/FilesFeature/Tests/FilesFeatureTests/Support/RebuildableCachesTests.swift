import ComposableArchitecture
@testable import FilesClient
@testable import FilesFeature
import Foundation
import ShareUploads
import Testing
import TestUtils

struct RebuildableCachesTests {
    private enum Store: CaseIterable {
        case thumbnailMemory, directories, lists, previews, uploadThumbnails
    }

    @Test
    func clearAllEmptiesEveryStore() {
        let cleared = LockIsolated<[Store]>([])
        @Sendable func record(_ store: Store) {
            cleared.withValue { $0.append(store) }
        }
        var directories = DirectoryCacheStore.testValue
        directories.clearAll = { record(.directories) }
        var lists = JSONCacheStore.testValue
        lists.clearAll = { record(.lists) }
        var uploadThumbnails = LocalThumbnailStore.testValue
        uploadThumbnails.clearAll = { record(.uploadThumbnails) }
        var thumbnails = ThumbnailCache.testValue
        thumbnails.clearMemory = { record(.thumbnailMemory) }
        let etags = TextEditorETagStore()
        let etagKey = TextEditorETagStore.key(
            scope: TestAccountID.alice,
            serverURL: TestHost.serverURL,
            path: TestFolder.docs
        )
        etags.set(TestETag.first, for: etagKey)

        RebuildableCaches(
            directoryCacheStore: directories,
            jsonCacheStore: lists,
            previewCacheStore: PreviewCacheStore(size: { 0 }, clear: { record(.previews) }),
            thumbnailCache: thumbnails,
            textEditorETagStore: etags,
            localThumbnailStore: uploadThumbnails
        ).clearAll()

        #expect(Set(cleared.value) == Set(Store.allCases))
        #expect(cleared.value.count == Store.allCases.count)
        #expect(etags.etag(for: etagKey) == nil)
    }
}
