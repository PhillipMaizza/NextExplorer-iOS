import ComposableArchitecture
import FilesClient
import ShareUploads

public struct RebuildableCaches: Sendable {
    let directoryCacheStore: DirectoryCacheStore
    let jsonCacheStore: JSONCacheStore
    let previewCacheStore: PreviewCacheStore
    let thumbnailCache: ThumbnailCache
    let textEditorETagStore: TextEditorETagStore
    let localThumbnailStore: LocalThumbnailStore

    public static var fromDependencies: RebuildableCaches {
        @Dependency(\.directoryCacheStore) var directoryCacheStore
        @Dependency(\.jsonCacheStore) var jsonCacheStore
        @Dependency(\.previewCacheStore) var previewCacheStore
        @Dependency(\.thumbnailCache) var thumbnailCache
        @Dependency(\.textEditorETagStore) var textEditorETagStore
        @Dependency(\.localThumbnailStore) var localThumbnailStore
        return RebuildableCaches(
            directoryCacheStore: directoryCacheStore,
            jsonCacheStore: jsonCacheStore,
            previewCacheStore: previewCacheStore,
            thumbnailCache: thumbnailCache,
            textEditorETagStore: textEditorETagStore,
            localThumbnailStore: localThumbnailStore
        )
    }

    public func clearAll() {
        thumbnailCache.clearMemory()
        directoryCacheStore.clearAll()
        jsonCacheStore.clearAll()
        try? previewCacheStore.clear()
        textEditorETagStore.clearAll()
        localThumbnailStore.clearAll()
    }
}
