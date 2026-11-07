import Foundation
import ShareUploads

/// The app's side of uploads started from the Share Extension: when the system wakes the app for
/// one of their sessions, the uploader finishes the batch (cleanup, the "done" notification).
public enum BackgroundUploadEvents {
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
}
