import CoreModels
import FilesClient
import Foundation
import NetworkClient

/// A Mac download the user placed in Finder: the item and where it goes. It runs in the app
/// wide download queue, so it keeps going when the folder it started from closes, can be
/// cancelled, and shows in the toolbar activity. iOS never makes one.
public struct DownloadSaveRequest: Equatable, Sendable {
    public enum Target: Equatable, Sendable {
        /// The save panel's exact choice; the panel already confirmed replacing anything there.
        case replacing(URL)
        /// A folder picked for several items; each lands under a name nothing there uses yet.
        case into(URL)
    }

    public let item: FileItem
    public let target: Target

    public init(item: FileItem, target: Target) {
        self.item = item
        self.target = target
    }
}

#if os(macOS)
    extension MacDownloadSaving {
        /// Where `item` lands for `target`. A server name is untrusted, so only its last
        /// component is used inside a picked folder.
        static func destination(for item: FileItem, target: DownloadSaveRequest.Target) -> URL {
            switch target {
            case let .replacing(url):
                url
            case let .into(folder):
                uniqueDestination(in: folder, fileName: SafeFileName.component(item.name))
            }
        }

        /// Saves a file, or a whole folder as a real folder tree (no server side zip), and
        /// returns where it landed. Each file streams straight to disk, never through the preview
        /// cache, so a large save neither doubles its disk use nor evicts previews. A folder is
        /// built in a scratch folder and only replaces the destination once every file is down,
        /// so a failed or cancelled save never costs the folder already there.
        static func save(
            _ request: DownloadSaveRequest,
            serverURL: URL,
            filesClient: FilesClient,
            onProgress: @escaping @Sendable (TransferProgress) -> Void
        ) async throws -> URL {
            let item = request.item
            let destination = destination(for: item, target: request.target)
            guard item.isDirectory else {
                let temporary = try await filesClient.downloadItem(serverURL, item, onProgress)
                defer { try? FileManager.default.removeItem(at: temporary) }
                try Task.checkCancellation()
                try local { try move(temporary, to: destination) }
                return destination
            }
            // Strict: a subfolder that can't be listed fails the save instead of leaving it out.
            let files = try await OfflineDownloadsFeature.enumerate(
                roots: [item], serverURL: serverURL, filesClient: filesClient, skipsUnreadableFolders: false
            )
            let totalBytes = files.reduce(Int64(0)) { $0 + max($1.size, 0) }
            let expectedBytes = totalBytes > 0 ? totalBytes : nil
            let fileManager = FileManager.default
            let staging = fileManager.temporaryDirectory
                .appendingPathComponent("\(NetworkClient.downloadTemporaryFilePrefix)\(UUID().uuidString)", isDirectory: true)
            defer { try? fileManager.removeItem(at: staging) }
            try local { try fileManager.createDirectory(at: staging, withIntermediateDirectories: true) }
            let rootPrefix = item.id + "/"
            var completedBytes: Int64 = 0
            for file in files {
                try Task.checkCancellation()
                let relativePath = file.id.hasPrefix(rootPrefix) ? String(file.id.dropFirst(rootPrefix.count)) : file.name
                // Server names are untrusted: never let one escape the chosen folder.
                guard let target = SafeDestination.within(staging, relativePath) else { continue }
                try local { try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true) }
                let base = completedBytes
                let temporary = try await filesClient.downloadItem(serverURL, file) { update in
                    onProgress(TransferProgress(receivedBytes: base + update.receivedBytes, expectedBytes: expectedBytes))
                }
                defer { try? fileManager.removeItem(at: temporary) }
                try local { try move(temporary, to: target) }
                completedBytes += max(file.size, 0)
                onProgress(TransferProgress(receivedBytes: completedBytes, expectedBytes: expectedBytes))
            }
            try Task.checkCancellation()
            try local { try move(staging, to: destination) }
            return destination
        }

        /// A disk failure (full, no permission) reads as a local problem, the way the iOS
        /// Downloads tab reports one, never as a network error.
        private static func local(_ work: () throws -> Void) throws {
            do {
                try work()
            } catch {
                throw FilesClientError.decoding(error.localizedDescription)
            }
        }
    }
#endif
