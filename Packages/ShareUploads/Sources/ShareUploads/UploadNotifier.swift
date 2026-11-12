import Foundation
import Localization
import UserNotifications

/// What a finished batch tells the user, before it becomes a system notification.
struct UploadNotification: Equatable {
    var title: String
    /// The server's host, so uploads to different accounts can be told apart.
    var subtitle: String
    var body: String
    var batchID: String
    var accountID: String
    var failedNames: [String]
    /// The folder the files went to, for a tap to open the app there.
    var destination: String

    var hasFailures: Bool {
        !failedNames.isEmpty
    }

    /// The batch id, plus the account and folder a tap opens. File names, causes and the server
    /// are looked up from the batch's manifest when needed, so they never ride in the notification.
    var userInfo: [String: Any] {
        [
            UploadNotificationKey.batchID: batchID,
            UploadNotificationKey.accountID: accountID,
            UploadNotificationKey.destination: destination,
        ]
    }
}

enum UploadNotificationKey {
    static let batchID = "batchID"
    static let accountID = "accountID"
    static let destination = "destination"
}

enum UploadNotificationIdentifier {
    static let failedCategory = "shareUpload.failed"
    static let doneCategory = "shareUpload.done"
    static let retryFailureNotification = "shareUpload.retryFailed"
    static let retryAction = "shareUpload.retry"
}

extension UploadNotification {
    /// How many failed names the body lists before it says "and N more".
    private static let listedNames = 3

    init(outcome: BatchOutcome) {
        let folder = (outcome.destination as NSString).lastPathComponent
        batchID = outcome.batchID
        accountID = outcome.accountID
        destination = outcome.destination
        subtitle = outcome.host
        failedNames = outcome.failedNames
        if outcome.failures.isEmpty {
            title = L10n.ShareUpload.notificationDoneTitle
            body = L10n.ShareUpload.notificationDoneBody(outcome.uploaded, folder)
        } else {
            title = outcome.uploaded > 0 ? L10n.ShareUpload.notificationFailedTitle : L10n.ShareUpload.notificationAllFailedTitle
            body = Self.failureBody(outcome.failures)
        }
    }

    private static func failureBody(_ failures: [FailedUpload]) -> String {
        var lines: [String] = UploadFailureCause.allCases.compactMap { cause in
            let count = failures.filter { $0.cause == cause }.count
            return count == 0 ? nil : causeText(cause, count: count)
        }
        lines.append(namesLine(failures.map(\.name)))
        return lines.joined(separator: "\n")
    }

    /// The first names, then how many more there are, joined the way the language writes a list.
    static func namesLine(_ names: [String]) -> String {
        var items = Array(names.prefix(listedNames))
        if names.count > listedNames {
            items.append(L10n.ShareUpload.notificationMoreNames(names.count - listedNames))
        }
        let formatter = ListFormatter()
        formatter.locale = LocalizationOverride.locale
        return formatter.string(from: items) ?? items.joined()
    }

    static func causeText(_ cause: UploadFailureCause, count: Int) -> String {
        switch cause {
        case .unauthorized: L10n.ShareUpload.failureUnauthorized(count)
        case .forbidden: L10n.ShareUpload.failureForbidden(count)
        case .serverFull: L10n.ShareUpload.failureServerFull(count)
        case .network: L10n.ShareUpload.failureNetwork(count)
        case .other: L10n.ShareUpload.failureOther(count)
        }
    }
}

/// The notification permission as the system reports it, and what asking does.
struct NotificationAuthorization: Sendable {
    var status: @Sendable () async -> UNAuthorizationStatus
    var request: @Sendable (UNAuthorizationOptions) async throws -> Bool

    static let live = NotificationAuthorization(
        status: { await UNUserNotificationCenter.current().notificationSettings().authorizationStatus },
        request: { try await UNUserNotificationCenter.current().requestAuthorization(options: $0) }
    )
}

/// The system notification center, reduced to what uploads use, so tests never touch the real one.
struct NotificationCenterClient: Sendable {
    var add: @Sendable (UNNotificationRequest) -> Void
    /// Removes the delivered and the pending notifications with these identifiers.
    var remove: @Sendable ([String]) -> Void
    var setCategories: @Sendable (Set<UNNotificationCategory>) -> Void

    static let live = NotificationCenterClient(
        add: { UNUserNotificationCenter.current().add($0) },
        remove: { identifiers in
            UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: identifiers)
            UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
        },
        setCategories: { UNUserNotificationCenter.current().setNotificationCategories($0) }
    )
}

/// Tells the user how a background batch went, once for the whole batch.
struct UploadNotifier: Sendable {
    var batchFinished: @Sendable (BatchOutcome) -> Void

    static let live = posting(to: .live)

    static func posting(to center: NotificationCenterClient) -> UploadNotifier {
        UploadNotifier { outcome in
            let notification = UploadNotification(outcome: outcome)
            let content = UNMutableNotificationContent()
            content.title = notification.title
            content.subtitle = notification.subtitle
            content.body = notification.body
            content.userInfo = notification.userInfo
            content.threadIdentifier = notification.accountID
            registerCategories(using: center)
            content.categoryIdentifier = notification.hasFailures
                ? UploadNotificationIdentifier.failedCategory
                : UploadNotificationIdentifier.doneCategory
            // One notification per batch: a retry's result replaces the earlier one.
            center.add(UNNotificationRequest(identifier: notification.batchID, content: content, trigger: nil))
        }
    }

    /// The failure category carries the Retry button. Both categories replace the body with a
    /// placeholder when the user hides previews, since the body names files and a folder. A
    /// dismissal is not reported: it never deletes anything.
    static func categories() -> [UNNotificationCategory] {
        let retry = UNNotificationAction(
            identifier: UploadNotificationIdentifier.retryAction,
            title: L10n.ShareUpload.notificationRetry,
            options: []
        )
        return [
            UNNotificationCategory(
                identifier: UploadNotificationIdentifier.failedCategory,
                actions: [retry],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: L10n.ShareUpload.notificationHiddenPreview,
                options: []
            ),
            UNNotificationCategory(
                identifier: UploadNotificationIdentifier.doneCategory,
                actions: [],
                intentIdentifiers: [],
                hiddenPreviewsBodyPlaceholder: L10n.ShareUpload.notificationHiddenPreview,
                options: []
            ),
        ]
    }

    static func registerCategories(using center: NotificationCenterClient = .live) {
        center.setCategories(Set(categories()))
    }

    /// Said when Retry could not start anything, so the user is never left with silence.
    static func postRetryFailed(_ reason: UploadNotifications.RetryFailure, using center: NotificationCenterClient = .live) {
        let content = UNMutableNotificationContent()
        content.title = L10n.ShareUpload.retryFailedTitle
        switch reason {
        case .nothingToSend: content.body = L10n.ShareUpload.retryFailedBody
        case .needsSignIn: content.body = L10n.ShareUpload.retrySignInBody
        }
        center.add(UNNotificationRequest(
            identifier: UploadNotificationIdentifier.retryFailureNotification, content: content, trigger: nil
        ))
    }

    enum PermissionRequest: Equatable {
        case full
        case none
    }

    /// Only a permission never asked for is asked for: an answer, or a quiet grant, stays as it is.
    static func permissionRequest(for status: UNAuthorizationStatus) -> PermissionRequest {
        status == .notDetermined ? .full : .none
    }

    /// Asks for full permission once, so results show as banners. Where the system cannot show
    /// the prompt (an extension may be refused), the quiet provisional permission is the fallback:
    /// results then land in Notification Center without asking the user anything.
    static func requestPermission(using authorization: NotificationAuthorization = .live) async {
        guard await permissionRequest(for: authorization.status()) == .full else { return }
        do {
            _ = try await authorization.request([.alert, .sound])
        } catch {
            _ = try? await authorization.request([.alert, .provisional])
        }
    }
}

public enum UploadNotifications {
    public static func requestPermission() async {
        await UploadNotifier.requestPermission()
    }

    /// Why a Retry could not send anything.
    public enum RetryFailure: Sendable {
        /// The files are gone, or the batch is: they have to be shared again.
        case nothingToSend
        /// The batch's account has no valid session: signing in and tapping Retry again works.
        case needsSignIn
    }

    public static func notifyRetryFailed(_ reason: RetryFailure) {
        UploadNotifier.postRetryFailed(reason)
    }

    /// Makes the app the notification center's delegate (banners while it is frontmost, the Retry
    /// button) and registers the failure category. Call once at launch, before the
    /// app finishes launching, so a notification action that starts the app is delivered.
    ///
    /// `open` is called on the main thread when the user taps a notification, with the batch's
    /// account and the folder its files went to.
    public static func install(
        retry: @escaping @Sendable (_ batchID: String) async -> Void,
        open: @escaping @Sendable (_ accountID: String, _ folder: String) -> Void
    ) {
        let handler = UploadNotificationHandler(retry: retry, open: open)
        UploadNotificationHandler.retain(handler)
        UNUserNotificationCenter.current().delegate = handler
        UploadNotifier.registerCategories()
    }
}
