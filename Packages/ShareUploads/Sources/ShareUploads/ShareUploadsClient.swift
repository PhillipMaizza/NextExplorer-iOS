import Dependencies
import DependenciesMacros
import Foundation

/// The app's handle on uploads started from the Share Extension.
@DependencyClient
public struct ShareUploadsClient: Sendable {
    /// Stops and deletes every pending batch of an account not in `accountIDs`.
    public var cancel: @Sendable (_ keepingAccounts: Set<String>) -> Void
}

extension ShareUploadsClient: DependencyKey {
    public static let liveValue = ShareUploadsClient(
        cancel: { BackgroundUploader.shared.cancel(keepingAccounts: $0) }
    )

    public static let testValue = ShareUploadsClient(cancel: { _ in })
}

public extension DependencyValues {
    var shareUploads: ShareUploadsClient {
        get { self[ShareUploadsClient.self] }
        set { self[ShareUploadsClient.self] = newValue }
    }
}
