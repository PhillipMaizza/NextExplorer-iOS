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
    var primaryCause: UploadFailureCause?

    var hasFailures: Bool {
        !failedNames.isEmpty
    }

    /// Only the batch id: the account, names and cause are looked up from the batch's manifest
    /// when needed, so nothing about the files or the server rides in the notification itself.
    var userInfo: [String: Any] {
        [UploadNotificationKey.batchID: batchID]
    }
}

enum UploadNotificationKey {
    static let batchID = "batchID"
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
        subtitle = outcome.host
        failedNames = outcome.failedNames
        primaryCause = Self.primaryCause(of: outcome.failures)
        if outcome.failures.isEmpty {
            title = L10n.ShareUpload.notificationDoneTitle
            body = L10n.ShareUpload.notificationDoneBody(outcome.uploaded, folder)
        } else {
            title = outcome.uploaded > 0 ? L10n.ShareUpload.notificationFailedTitle : L10n.ShareUpload.notificationAllFailedTitle
            body = Self.failureBody(outcome.failures)
        }
    }

    /// The cause most of the failed files share; on a tie the one the user can fix soonest wins.
    static func primaryCause(of failures: [FailedUpload]) -> UploadFailureCause? {
        let counts = Dictionary(grouping: failures, by: \.cause).mapValues(\.count)
        return UploadFailureCause.allCases
            .filter { counts[$0] != nil }
            .max { (counts[$0] ?? 0) < (counts[$1] ?? 0) }
    }

    private static func failureBody(_ failures: [FailedUpload]) -> String {
        var lines: [String] = UploadFailureCause.allCases.compactMap { cause in
            let count = failures.filter { $0.cause == cause }.count
            return count == 0 ? nil : causeText(cause, count: count)
        }
        let names = failures.map(\.name)
        var listed = names.prefix(listedNames).joined(separator: ", ")
        if names.count > listedNames {
            listed += " " + L10n.ShareUpload.notificationMoreNames(names.count - listedNames)
        }
        lines.append(listed)
        return lines.joined(separator: "\n")
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

/// Tells the user how a background batch went, once for the whole batch.
struct UploadNotifier: Sendable {
    var batchFinished: @Sendable (BatchOutcome) -> Void

    static let live = UploadNotifier { outcome in
        let notification = UploadNotification(outcome: outcome)
        let content = UNMutableNotificationContent()
        content.title = notification.title
        content.subtitle = notification.subtitle
        content.body = notification.body
        content.userInfo = notification.userInfo
        content.threadIdentifier = notification.accountID
        registerCategories()
        content.categoryIdentifier = notification.hasFailures
            ? UploadNotificationIdentifier.failedCategory
            : UploadNotificationIdentifier.doneCategory
        // One notification per batch: a retry's result replaces the earlier one.
        let request = UNNotificationRequest(identifier: notification.batchID, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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

    static func registerCategories() {
        UNUserNotificationCenter.current().setNotificationCategories(Set(categories()))
    }

    /// Said when Retry could not start anything, so the user is never left with silence.
    static func postRetryFailed() {
        let content = UNMutableNotificationContent()
        content.title = L10n.ShareUpload.retryFailedTitle
        content.body = L10n.ShareUpload.retryFailedBody
        let request = UNNotificationRequest(
            identifier: UploadNotificationIdentifier.retryFailureNotification, content: content, trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
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

    public static func notifyRetryFailed() {
        UploadNotifier.postRetryFailed()
    }

    /// Makes the app the notification center's delegate (banners while it is frontmost, the Retry
    /// button) and registers the failure category. Call once at launch, before the
    /// app finishes launching, so a notification action that starts the app is delivered.
    public static func install(retry: @escaping @Sendable (_ batchID: String) async -> Void) {
        let handler = UploadNotificationHandler(retry: retry)
        UploadNotificationHandler.retain(handler)
        UNUserNotificationCenter.current().delegate = handler
        UploadNotifier.registerCategories()
    }
}
