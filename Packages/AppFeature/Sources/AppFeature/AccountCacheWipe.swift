import AuthClient
import ComposableArchitecture
import FilesClient
import FilesFeature
import ShareUploads

/// Removes one account's data from every cache while other accounts stay signed in (rule #11): the
/// disk stores, the preview and offline files, and the in memory thumbnails and text editor ETags.
/// A full teardown still uses each store's `clearAll`.
///
/// Effects of the account's screens may still be writing when the wipe starts, so it runs twice:
/// `markPending` lists the account before its session is dropped, `wipe` clears it, and
/// `finishPending` runs again once the account's screens are gone (their effects cancelled) and
/// unlists it. Anything left listed by a kill is wiped by `finishPending` at the next launch. An
/// account that has a stored session again (signed back in) is unlisted without being wiped.
struct AccountCacheWipe: Sendable {
    let directoryCacheStore: DirectoryCacheStore
    let jsonCacheStore: JSONCacheStore
    let previewCacheStore: PreviewCacheStore
    let offlineFileStore: OfflineFileStore
    let localDownloadStore: LegacyDownloadStore
    let thumbnailCache: ThumbnailCache
    let textEditorETagStore: TextEditorETagStore
    let localThumbnailStore: LocalThumbnailStore
    let deviceSaver: DeviceSaver
    let pendingWipes: PendingAccountWipes

    /// Built from the current dependencies, for every place that wipes an account.
    static var fromDependencies: AccountCacheWipe {
        @Dependency(\.directoryCacheStore) var directoryCacheStore
        @Dependency(\.jsonCacheStore) var jsonCacheStore
        @Dependency(\.previewCacheStore) var previewCacheStore
        @Dependency(\.offlineFileStore) var offlineFileStore
        @Dependency(\.localDownloadStore) var localDownloadStore
        @Dependency(\.thumbnailCache) var thumbnailCache
        @Dependency(\.textEditorETagStore) var textEditorETagStore
        @Dependency(\.localThumbnailStore) var localThumbnailStore
        @Dependency(\.deviceSaver) var deviceSaver
        @Dependency(\.pendingAccountWipes) var pendingAccountWipes
        return AccountCacheWipe(
            directoryCacheStore: directoryCacheStore,
            jsonCacheStore: jsonCacheStore,
            previewCacheStore: previewCacheStore,
            offlineFileStore: offlineFileStore,
            localDownloadStore: localDownloadStore,
            thumbnailCache: thumbnailCache,
            textEditorETagStore: textEditorETagStore,
            localThumbnailStore: localThumbnailStore,
            deviceSaver: deviceSaver,
            pendingWipes: pendingAccountWipes
        )
    }

    func callAsFunction(_ accountID: String) {
        markPending(accountID)
        wipe(accountID)
    }

    func markPending(_ accountID: String) {
        pendingWipes.add(accountID)
    }

    func finishPending(liveAccountIDs: Set<String>) {
        for accountID in pendingWipes.accounts() {
            if !liveAccountIDs.contains(accountID) {
                wipe(accountID)
            }
            pendingWipes.remove(accountID)
        }
    }

    /// Does nothing when the stored sessions can't be read, so an unreadable keychain never makes a
    /// live account look signed out.
    func finishPending(authClient: AuthClient) async {
        guard let sessions = try? await authClient.listSessionsOrThrow() else { return }
        finishPending(liveAccountIDs: Set(sessions.map(\.accountID)))
    }

    func wipe(_ accountID: String) {
        directoryCacheStore.clear(scope: accountID)
        jsonCacheStore.clear(scope: accountID)
        previewCacheStore.clearAccount(accountID)
        offlineFileStore.removeAccount(accountID)
        localDownloadStore.removeAccount(accountID)
        textEditorETagStore.clear(scope: accountID)
        localThumbnailStore.clearScope(accountID)
        // Files staged for the Save to Files panel belong to the account that fetched them.
        deviceSaver.discardAll()
        // One cache for every account, so it is dropped whole: the active account refills it.
        thumbnailCache.clearMemory()
    }
}

/// Finishes the account wipes an earlier run started and did not complete (the app was killed
/// before its second pass). Call once at launch.
public enum PendingAccountWipeRecovery {
    public static func runAtLaunch() async {
        @Dependency(\.authClient) var authClient
        let wipe = AccountCacheWipe.fromDependencies
        // A kill can leave staged copies behind: nothing is waiting for them at launch.
        wipe.deviceSaver.discardAll()
        // Older versions saved into folders the Files app shows: move them private, by owner.
        wipe.localDownloadStore.moveSharedFilesToPrivateStorage()
        await wipe.finishPending(authClient: authClient)
    }
}
