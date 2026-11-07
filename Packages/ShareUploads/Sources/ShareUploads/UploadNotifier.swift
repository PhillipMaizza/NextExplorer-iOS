import Foundation
import Localization
import UserNotifications

/// Tells the user how a background batch went, once for the whole batch.
struct UploadNotifier: Sendable {
    var batchFinished: @Sendable (BatchOutcome) -> Void

    static let live = UploadNotifier { outcome in
        let content = UNMutableNotificationContent()
        let folder = (outcome.destination as NSString).lastPathComponent
        if outcome.failedNames.isEmpty {
            content.title = L10n.ShareUpload.notificationDoneTitle
            content.body = L10n.ShareUpload.notificationDoneBody(outcome.uploaded, folder)
        } else {
            content.title = L10n.ShareUpload.notificationFailedTitle
            content.body = L10n.ShareUpload.notificationFailedBody(outcome.failedNames.count, outcome.uploaded + outcome.failedNames.count)
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    /// Quiet (provisional) permission: the result lands in Notification Center without asking
    /// the user anything first.
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .provisional])
    }
}

public enum UploadNotifications {
    public static func requestPermission() async {
        await UploadNotifier.requestPermission()
    }
}
