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
        /// A Mac never wakes the app for an extension's finished batch, so it looks this often.
        static let reconnectInterval: Duration = .seconds(30)
    }

    private static let periodicReconnect = PeriodicTask()

    /// `true` when `identifier` is one of these sessions and was taken care of.
    public static func handle(sessionIdentifier identifier: String, completion: @escaping @Sendable () -> Void) -> Bool {
        guard BackgroundUploader.ownsSession(identifier) else { return false }
        BackgroundUploader.shared.handleEvents(forSession: identifier, completion: completion)
        return true
    }

    /// Picks up share uploads that finished or are still running without the app. The directory
    /// scan and the notifications run off the main thread. Nothing is read from the keychain
    /// while no batch is pending.
    public static func reconnectPending() async {
        @Dependency(\.authClient) var authClient
        let sessions: @Sendable () async -> [SessionCredentials] = { await authClient.listSessions() }
        await Task.detached(priority: .utility) {
            await reconnectPending(
                hasPending: { BackgroundUploader.shared.hasPendingBatches() },
                sessions: sessions,
                reconnect: { BackgroundUploader.shared.reconnectPending(sessions: $0) }
            )
        }.value
    }

    static func reconnectPending(
        hasPending: @Sendable () -> Bool,
        sessions: @Sendable () async -> [SessionCredentials],
        reconnect: @Sendable ([SessionCredentials]) -> Void
    ) async {
        guard hasPending() else { return }
        await reconnect(sessions())
    }

    /// On a Mac: keeps reconnecting while the app runs, so a batch that finishes in the background
    /// is reported when it ends rather than the next time the app comes forward. Safe to call
    /// again: there is only ever one timer. An iPhone or iPad is woken by the system instead.
    public static func startPeriodicReconnect() {
        #if os(macOS)
            periodicReconnect.start(every: Constants.reconnectInterval, clock: ContinuousClock()) {
                await reconnectPending()
            }
        #endif
    }

    /// At launch, before the app finishes launching: result notifications show as banners even while
    /// the app is frontmost, and their Retry button works when it starts the app in the background.
    public static func installNotificationHandling() {
        UploadNotifications.install(
            retry: { batchID in await retry(batchID: batchID) },
            open: { accountID, folder in UploadNotificationTaps.send(.init(accountID: accountID, folder: folder)) }
        )
    }

    /// Whenever the app becomes active: a Mac app that was already running, or an iPhone app
    /// resumed from the background, is never told when an extension's batch ended, so it looks
    /// again. Also acts on a share upload the server refused as signed out.
    public static func sceneDidBecomeActive() async {
        await reconnectPending()
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
            notifyFailure: { UploadNotifications.notifyRetryFailed($0) }
        )
    }

    /// Retry never fails silently: no account for the batch or no file left to send says to share
    /// the files again, and no signed in session for the account says to sign in and retry.
    static func retry(
        batchID: String,
        authClient: AuthClient,
        accountID: @Sendable (String) -> String?,
        retryFailed: @Sendable (String, SessionCredentials) -> Int,
        notifyFailure: @Sendable (UploadNotifications.RetryFailure) -> Void
    ) async {
        guard let accountID = accountID(batchID) else {
            notifyFailure(.nothingToSend)
            return
        }
        guard let credentials = await authClient.listSessions().first(where: { $0.accountID == accountID }) else {
            notifyFailure(.needsSignIn)
            return
        }
        if retryFailed(batchID, credentials) == 0 {
            notifyFailure(.nothingToSend)
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
            _ = shareUploads.retryRefused(credentials)
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

/// Runs `perform` every `interval` until stopped, one timer at a time.
final class PeriodicTask: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Never>?

    var isRunning: Bool {
        lock.withLock { task != nil }
    }

    /// `false` when it was already running: the existing timer is kept.
    @discardableResult
    func start(every interval: Duration, clock: any Clock<Duration>, perform: @escaping @Sendable () async -> Void) -> Bool {
        lock.withLock {
            guard task == nil else { return false }
            task = Task {
                while !Task.isCancelled {
                    do {
                        try await clock.sleep(for: interval)
                    } catch {
                        return
                    }
                    await perform()
                }
            }
            return true
        }
    }

    func stop() {
        lock.withLock {
            task?.cancel()
            task = nil
        }
    }
}
