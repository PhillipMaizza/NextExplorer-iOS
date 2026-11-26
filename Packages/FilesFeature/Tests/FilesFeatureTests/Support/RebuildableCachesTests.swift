import ComposableArchitecture
@testable import FilesClient
@testable import FilesFeature
import Foundation
import ShareUploads
import Testing
import TestUtils

struct RebuildableCachesTests {
    private enum Store: CaseIterable {
        case thumbnailMemory, directories, lists, previews, uploadThumbnails, uploadResumes
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
            previewCacheStore: PreviewCacheStore(size: { _ in 0 }, clear: { record(.previews) }),
            thumbnailCache: thumbnails,
            textEditorETagStore: etags,
            localThumbnailStore: uploadThumbnails,
            forgetUploadResumes: { record(.uploadResumes) }
        ).clearAll()

        #expect(Set(cleared.value) == Set(Store.allCases))
        #expect(cleared.value.count == Store.allCases.count)
        #expect(etags.etag(for: etagKey) == nil)
    }

    @Test("Clearing one account's cache leaves the other accounts' stores alone")
    func clearAccountClearsOnlyThatScope() {
        let scopes = LockIsolated<[String]>([])
        let wholeStores = LockIsolated(0)
        var directories = DirectoryCacheStore.testValue
        directories.clearScope = { scope in scopes.withValue { $0.append(scope) } }
        directories.clearAll = { wholeStores.withValue { $0 += 1 } }
        var lists = JSONCacheStore.testValue
        lists.clearScope = { scope in scopes.withValue { $0.append(scope) } }
        lists.clearAll = { wholeStores.withValue { $0 += 1 } }
        var uploadThumbnails = LocalThumbnailStore.testValue
        uploadThumbnails.clearScope = { scope in scopes.withValue { $0.append(scope) } }
        uploadThumbnails.clearAll = { wholeStores.withValue { $0 += 1 } }
        let previews = PreviewCacheStore(
            size: { _ in 0 },
            clear: { wholeStores.withValue { $0 += 1 } },
            clearAccount: { scope in scopes.withValue { $0.append(scope) } }
        )
        var thumbnails = ThumbnailCache.testValue
        thumbnails.clearMemory = {}
        let etags = TextEditorETagStore()
        let aliceKey = TextEditorETagStore.key(
            scope: TestAccountID.alice,
            serverURL: TestHost.serverURL,
            path: TestFolder.docs
        )
        let bobKey = TextEditorETagStore.key(
            scope: TestAccountID.bob,
            serverURL: TestHost.serverURL,
            path: TestFolder.docs
        )
        etags.set(TestETag.first, for: aliceKey)
        etags.set(TestETag.first, for: bobKey)

        RebuildableCaches(
            directoryCacheStore: directories,
            jsonCacheStore: lists,
            previewCacheStore: previews,
            thumbnailCache: thumbnails,
            textEditorETagStore: etags,
            localThumbnailStore: uploadThumbnails,
            forgetUploadResumes: { wholeStores.withValue { $0 += 1 } }
        ).clearAccount(TestAccountID.alice)

        #expect(scopes.value == Array(repeating: TestAccountID.alice, count: 4))
        #expect(wholeStores.value == 0)
        #expect(etags.etag(for: aliceKey) == nil)
        #expect(etags.etag(for: bobKey) == TestETag.first)
    }
}
