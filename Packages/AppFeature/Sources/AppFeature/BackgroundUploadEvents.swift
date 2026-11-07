import AuthClient
import ComposableArchitecture
import CoreModels
import Foundation
import ShareUploads

/// The app's side of uploads started from the Share Extension: when the system wakes the app for
/// one of their sessions, the uploader finishes the batch (cleanup, the "done" notification).
public enum BackgroundUploadEvents {
    private enum Constants {
        static let unauthorizedStatusCode = 401
    }

    /// `true` when `identifier` is one of these sessions and was taken care of.
    public static func handle(sessionIdentifier identifier: String, completion: @escaping @Sendable () -> Void) -> Bool {
        guard BackgroundUploader.ownsSession(identifier) else { return false }
        BackgroundUploader.shared.handleEvents(forSession: identifier, completion: completion)
        return true
    }

    /// At launch: picks up share uploads that finished or are still running without the app.
    public static func reconnectPending() {
        BackgroundUploader.shared.reconnectPending()
    }

    /// At launch, before the app finishes launching: result notifications show as banners even while
    /// the app is frontmost, and their Retry button works when it starts the app in the background.
    public static func installNotificationHandling() {
        UploadNotifications.install { batchID in
            await retry(batchID: batchID)
        }
    }

    /// Whenever the app becomes active: a Mac app that was already running, or an iPhone app
    /// resumed from the background, is never told when an extension's batch ended, so it looks
    /// again. Also acts on a share upload the server refused as signed out.
    public static func sceneDidBecomeActive() async {
        BackgroundUploader.shared.reconnectPending()
        @Dependency(\.authClient) var authClient
        await checkRefusedSessions(
            shareUploads: ShareUploadsClient.liveValue,
            authClient: authClient,
            expireSession: {
                @Shared(.inMemory(SessionExpiry.sharedKey)) var sessionDidExpire = false
                $sessionDidExpire.withLock { $0 = true }
            }
        )
    }

    /// The notification's Retry button: sends the batch's failed files again with the batch
    /// account's current session cookie. When nothing can be sent the user is told so.
    public static func retry(batchID: String) async {
        @Dependency(\.authClient) var authClient
        await retry(
            batchID: batchID,
            authClient: authClient,
            accountID: { BackgroundUploader.shared.accountID(ofBatch: $0) },
            retryFailed: { BackgroundUploader.shared.retryFailed(batchID: $0, credentials: $1) },
            notifyFailure: { UploadNotifications.notifyRetryFailed() }
        )
    }

    /// Retry never fails silently: no account for the batch, no signed in session for it, or no
    /// file left to send each post the failure notice.
    static func retry(
        batchID: String,
        authClient: AuthClient,
        accountID: @Sendable (String) -> String?,
        retryFailed: @Sendable (String, SessionCredentials) -> Int,
        notifyFailure: @Sendable () -> Void
    ) async {
        guard
            let accountID = accountID(batchID),
            let credentials = await authClient.listSessions().first(where: { $0.accountID == accountID }),
            retryFailed(batchID, credentials) > 0
        else {
            notifyFailure()
            return
        }
    }

    /// An upload answered 401 for the active account. The flag may be old (the user has signed in
    /// again since), so the session is asked first: only a server that still rejects it trips the
    /// existing session expired path. A server that cannot be reached leaves the flag for later.
    static func checkRefusedSessions(
        shareUploads: ShareUploadsClient,
        authClient: AuthClient,
        expireSession: @Sendable () -> Void
    ) async {
        let flagged = shareUploads.accountsNeedingSignIn()
        guard
            !flagged.isEmpty,
            let activeID = await authClient.activeAccountID(),
            flagged.contains(activeID),
            let credentials = await authClient.listSessions().first(where: { $0.accountID == activeID })
        else { return }
        do {
            _ = try await authClient.me(credentials.serverBaseURL)
            shareUploads.clearNeedsSignIn(activeID)
        } catch let error as AuthClientError {
            switch error {
            case .sessionExpired, .sessionCookieMissing, .invalidCredentials, .server(statusCode: Constants.unauthorizedStatusCode):
                shareUploads.clearNeedsSignIn(activeID)
                expireSession()
            default:
                break
            }
        } catch {
            return
        }
    }
}
