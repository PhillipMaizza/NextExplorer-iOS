import AuthClient
import ComposableArchitecture
import FilesClient
import FilesFeature

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
    let thumbnailCache: ThumbnailCache
    let textEditorETagStore: TextEditorETagStore
    let pendingWipes: PendingAccountWipes

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
        textEditorETagStore.clear(scope: accountID)
        // One cache for every account, so it is dropped whole: the active account refills it.
        thumbnailCache.clearMemory()
    }
}

/// Finishes the account wipes an earlier run started and did not complete (the app was killed
/// before its second pass). Call once at launch.
public enum PendingAccountWipeRecovery {
    public static func runAtLaunch() async {
        @Dependency(\.authClient) var authClient
        @Dependency(\.directoryCacheStore) var directoryCacheStore
        @Dependency(\.jsonCacheStore) var jsonCacheStore
        @Dependency(\.previewCacheStore) var previewCacheStore
        @Dependency(\.offlineFileStore) var offlineFileStore
        @Dependency(\.thumbnailCache) var thumbnailCache
        @Dependency(\.textEditorETagStore) var textEditorETagStore
        @Dependency(\.pendingAccountWipes) var pendingAccountWipes
        await AccountCacheWipe(
            directoryCacheStore: directoryCacheStore,
            jsonCacheStore: jsonCacheStore,
            previewCacheStore: previewCacheStore,
            offlineFileStore: offlineFileStore,
            thumbnailCache: thumbnailCache,
            textEditorETagStore: textEditorETagStore,
            pendingWipes: pendingAccountWipes
        ).finishPending(authClient: authClient)
    }
}
