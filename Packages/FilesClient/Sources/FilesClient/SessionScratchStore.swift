import Dependencies
import DependenciesMacros
import Foundation
import NetworkClient

/// The app's scratch files in `tmp`: archive entries extracted for preview, rendered HTML and
/// Markdown previews, files staged for upload, upload envelopes, and download bodies a caller never
/// moved (a crash mid transfer). Each owner cleans up after itself, but a kill or a crash leaves
/// them behind, and they hold one account's file contents. Purged at every session boundary with
/// the cache stores, so nothing survives into the next sign in. The shared HTTP cache goes too:
/// the app's sessions keep none, but an install from before that may still hold responses there.
@DependencyClient
public struct SessionScratchStore: Sendable {
    public enum Scope: Equatable, Sendable {
        /// Sign out and session expiry: every upload is torn down with the session.
        case everything
        /// A fresh sign in: the new session is already mounting, so it may be staging and uploading
        /// files shared into the app while signed out, or streaming its first thumbnails to
        /// temporary download files. Those stay; the sign out before it emptied them anyway.
        case keepingActiveTransfers
    }

    public var purge: @Sendable (_ scope: Scope) -> Void
}

public enum SessionScratchLocation {
    public static let archiveBrowser = "ArchiveBrowser"
    public static let htmlPreview = "HTMLPreview"
    public static let pendingUploads = "PendingUploads"
    public static let uploadEnvelopePrefix = "upload-"
}

public extension SessionScratchStore {
    static func live(temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> SessionScratchStore {
        SessionScratchStore(purge: { scope in
            let fileManager = FileManager.default
            var folders = [SessionScratchLocation.archiveBrowser, SessionScratchLocation.htmlPreview]
            if scope == .everything {
                folders.append(SessionScratchLocation.pendingUploads)
            }
            for name in folders {
                try? fileManager.removeItem(at: temporaryDirectory.appendingPathComponent(name, isDirectory: true))
            }
            // Upload envelopes and download bodies may belong to the session that is starting.
            let prefixes = scope == .everything
                ? [SessionScratchLocation.uploadEnvelopePrefix, NetworkClient.downloadTemporaryFilePrefix]
                : []
            let entries = (try? fileManager.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil)) ?? []
            for entry in entries where prefixes.contains(where: entry.lastPathComponent.hasPrefix) {
                try? fileManager.removeItem(at: entry)
            }
            URLCache.shared.removeAllCachedResponses()
        })
    }
}

extension SessionScratchStore: DependencyKey {
    public static let liveValue: SessionScratchStore = .live()
    public static let testValue = SessionScratchStore(purge: { _ in })
    public static let previewValue = SessionScratchStore(purge: { _ in })
}

public extension DependencyValues {
    var sessionScratchStore: SessionScratchStore {
        get { self[SessionScratchStore.self] }
        set { self[SessionScratchStore.self] = newValue }
    }
}
