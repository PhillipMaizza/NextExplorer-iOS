import ComposableArchitecture
import FilesClient
import ShareUploads

/// Every cache the server can refill, for every account: listings, saved lists, previews, decoded
/// and upload thumbnails, and editor ETags. Offline pins and downloads are the user's files, so
/// callers that also drop those do it themselves.
public struct RebuildableCaches: Sendable {
    let directoryCacheStore: DirectoryCacheStore
    let jsonCacheStore: JSONCacheStore
    let previewCacheStore: PreviewCacheStore
    let thumbnailCache: ThumbnailCache
    let textEditorETagStore: TextEditorETagStore
    let localThumbnailStore: LocalThumbnailStore

    /// Built from the current dependencies; read it in the reducer, clear inside the effect.
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

    /// Disk work: run it inside an effect, never in the reducer.
    public func clearAll() {
        thumbnailCache.clearMemory()
        directoryCacheStore.clearAll()
        jsonCacheStore.clearAll()
        try? previewCacheStore.clear()
        textEditorETagStore.clearAll()
        localThumbnailStore.clearAll()
    }
}
