import Dependencies
import DependenciesMacros
import Foundation
import NetworkClient

/// The app's scratch files in `tmp`: archive entries extracted for preview, files staged for
/// upload, and download bodies a caller never moved (a crash mid transfer). Each owner cleans up
/// after itself, but a kill or a crash leaves them behind, and they hold one account's file
/// contents. Purged at every session boundary with the cache stores, so nothing survives into
/// the next sign in. The shared HTTP cache goes too: the app's sessions no longer write to it,
/// but an install from before that change may still hold responses there.
@DependencyClient
public struct SessionScratchStore: Sendable {
    public var purge: @Sendable () -> Void
}

public enum SessionScratchLocation {
    public static let archiveBrowser = "ArchiveBrowser"
    public static let pendingUploads = "PendingUploads"
}

public extension SessionScratchStore {
    static func live(temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> SessionScratchStore {
        SessionScratchStore(purge: {
            let fileManager = FileManager.default
            for name in [SessionScratchLocation.archiveBrowser, SessionScratchLocation.pendingUploads] {
                try? fileManager.removeItem(at: temporaryDirectory.appendingPathComponent(name, isDirectory: true))
            }
            let entries = (try? fileManager.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
            for entry in entries where entry.lastPathComponent.hasPrefix(NetworkClient.downloadTemporaryFilePrefix) {
                try? fileManager.removeItem(at: entry)
            }
            URLCache.shared.removeAllCachedResponses()
        })
    }
}

extension SessionScratchStore: DependencyKey {
    public static let liveValue: SessionScratchStore = .live()
    public static let testValue = SessionScratchStore(purge: {})
    public static let previewValue = SessionScratchStore(purge: {})
}

public extension DependencyValues {
    var sessionScratchStore: SessionScratchStore {
        get { self[SessionScratchStore.self] }
        set { self[SessionScratchStore.self] = newValue }
    }
}
