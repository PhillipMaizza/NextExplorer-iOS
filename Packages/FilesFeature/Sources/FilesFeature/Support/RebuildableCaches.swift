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
    var forgetUploadResumes: @Sendable () -> Void = { UploadResumeLinks.forgetAll() }

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
        forgetUploadResumes()
    }

    public func clearAccount(_ scope: String) {
        thumbnailCache.clearMemory()
        directoryCacheStore.clearScope(scope)
        jsonCacheStore.clearScope(scope)
        previewCacheStore.clearAccount(scope)
        textEditorETagStore.clear(scope: scope)
        localThumbnailStore.clearScope(scope)
    }
}
