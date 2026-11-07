import CoreModels
import Dependencies
import DependenciesMacros
import Foundation
import ShareUploads

/// The items another app shared, as the extension received them. The extension's view controller
/// supplies the live value around its `NSItemProvider`s.
@DependencyClient
public struct SharedItemsClient: Sendable {
    public var count: @Sendable () -> Int = { 0 }
    /// Stages every item for `credentials`' server and hands them to the background uploader,
    /// reporting each one prepared. Returns how many went out.
    public var upload: @Sendable (
        _ credentials: SessionCredentials,
        _ destination: String,
        _ onPrepared: @Sendable @escaping (Int) -> Void
    ) async throws -> Int
}

extension SharedItemsClient: TestDependencyKey {
    public static let testValue = SharedItemsClient()
}

public extension SharedItemsClient {
    /// Uploads `providers` through `BackgroundUploader.shared`. An item with no file (a link) is
    /// skipped; any that can't be read stops the batch before anything is sent.
    static func live(providers: [NSItemProvider]) -> SharedItemsClient {
        let box = ProviderBox(providers: providers)
        return SharedItemsClient(
            count: { box.providers.count },
            upload: { credentials, destination, onPrepared in
                // Quiet permission for the "upload finished" notification, asked before anything goes out.
                await UploadNotifications.requestPermission()
                let uploader = BackgroundUploader.shared
                var batch = try uploader.makeBatch(credentials: credentials, destination: destination)
                do {
                    for provider in box.providers {
                        try Task.checkCancellation()
                        if let staged = try await SharedItemLoader.stage(provider, in: batch) {
                            batch.add(staged)
                            onPrepared(batch.count)
                        }
                    }
                    guard batch.count > 0 else {
                        uploader.discard(batch)
                        return 0
                    }
                    try uploader.start(batch)
                    return batch.count
                } catch {
                    uploader.discard(batch)
                    throw error
                }
            }
        )
    }
}

/// `NSItemProvider` is thread safe for loading but not marked `Sendable`.
private final class ProviderBox: @unchecked Sendable {
    let providers: [NSItemProvider]

    init(providers: [NSItemProvider]) {
        self.providers = providers
    }
}

public extension DependencyValues {
    var sharedItems: SharedItemsClient {
        get { self[SharedItemsClient.self] }
        set { self[SharedItemsClient.self] = newValue }
    }
}
