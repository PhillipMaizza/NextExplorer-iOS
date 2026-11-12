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

    // The completion handler forms, not the async ones: Swift resumes an async delegate method on a
    // cooperative thread and calls UIKit's completion handler there, and UIKit asserts the main
    // thread (tapping an upload notification crashed the app). Each handler is called on main.

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        willPresent _: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        MainThreadCompletion { completionHandler(Self.foregroundOptions) }.call()
    }

    func userNotificationCenter(
        _: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let completion = MainThreadCompletion(completionHandler)
        switch Self.decision(actionIdentifier: response.actionIdentifier, userInfo: response.notification.request.content.userInfo) {
        case let .retry(batchID):
            let retry = retry
            Task {
                await retry(batchID)
                completion.call()
            }
        case .ignore:
            completion.call()
        }
    }
}

/// A system completion handler that must run on the main thread, called there from any thread.
struct MainThreadCompletion: @unchecked Sendable {
    private let body: () -> Void

    init(_ body: @escaping () -> Void) {
        self.body = body
    }

    func call() {
        if Thread.isMainThread {
            body()
        } else {
            DispatchQueue.main.async(execute: body)
        }
    }
}
