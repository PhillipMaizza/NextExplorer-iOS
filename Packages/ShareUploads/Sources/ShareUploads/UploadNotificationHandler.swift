import Foundation
import UserNotifications

/// The notification center's delegate for upload results.
final class UploadNotificationHandler: NSObject, UNUserNotificationCenterDelegate, Sendable {
    enum Decision: Equatable {
        case retry(batchID: String)
        case ignore
    }

    private static let retained = NSLock()
    private nonisolated(unsafe) static var instance: UploadNotificationHandler?

    private let retry: @Sendable (String) async -> Void

    init(retry: @escaping @Sendable (String) async -> Void) {
        self.retry = retry
    }

    /// The center keeps its delegate weakly.
    static func retain(_ handler: UploadNotificationHandler) {
        retained.withLock { instance = handler }
    }

    /// While the app is frontmost (always on a Mac) the system would show nothing by default.
    static let foregroundOptions: UNNotificationPresentationOptions = [.banner, .list]

    /// A tap only opens the app and keeps the failed files for a later retry; the Retry button
    /// sends them again. A dismissal does nothing: the failed files stay until their retention ends.
    static func decision(actionIdentifier: String, userInfo: [AnyHashable: Any]) -> Decision {
        guard let batchID = userInfo[UploadNotificationKey.batchID] as? String else { return .ignore }
        switch actionIdentifier {
        case UploadNotificationIdentifier.retryAction:
            return .retry(batchID: batchID)
        default:
            return .ignore
        }
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter, willPresent _: UNNotification
    ) async -> UNNotificationPresentationOptions {
        Self.foregroundOptions
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter, didReceive response: UNNotificationResponse
    ) async {
        switch Self.decision(actionIdentifier: response.actionIdentifier, userInfo: response.notification.request.content.userInfo) {
        case let .retry(batchID):
            await retry(batchID)
        case .ignore:
            break
        }
    }
}
