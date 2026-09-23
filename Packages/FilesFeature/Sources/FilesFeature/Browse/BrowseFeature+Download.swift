#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    import Foundation
    import Localization

    /// A Mac saves where the user says (save panel), as real files and folder trees, instead of
    /// going through the app wide download queue the iOS Downloads tab uses.
    extension BrowseFeature {
        func startDownload(_ state: inout State, item: FileItem) -> Effect<Action> {
            guard !state.isPerformingFileAction else { return .none }
            state.isPerformingFileAction = true
            state.fileActionProgressMessage = nil
            let serverURL = state.serverURL
            let filesClient = filesClient
            let saveLocationPicker = saveLocationPicker
            return .run { send in
                guard let destination = await saveLocationPicker.chooseFile(item.name) else {
                    await send(.downloadCancelled)
                    return
                }
                await send(.downloadProgressUpdated(L10n.Browse.progressDownloading))
                try await send(.downloadResponse(apiResult {
                    try await Self.saveLocally(item, to: destination, serverURL: serverURL, filesClient: filesClient, send: send)
                    return destination
                }))
            }
        }

        /// Sequential and best effort: one item's failure doesn't stop the rest of the batch.
        func startBulkDownload(_ state: inout State, targets: [FileItem]) -> Effect<Action> {
            guard !state.isBulkActionInFlight, !targets.isEmpty else { return .none }
            state.isBulkActionInFlight = true
            state.fileActionProgressMessage = nil
            let serverURL = state.serverURL
            let filesClient = filesClient
            let saveLocationPicker = saveLocationPicker
            return .run { send in
                guard let folder = await saveLocationPicker.chooseFolder() else {
                    await send(.downloadCancelled)
                    return
                }
                await send(.bulkDownloadFolderChosen(folder))
                var savedCount = 0
                for (index, item) in targets.enumerated() {
                    await send(.downloadProgressUpdated(L10n.Browse.progressDownloadingIndexed(index + 1, targets.count)))
                    do {
                        let destination = MacDownloadSaving.uniqueDestination(in: folder, fileName: item.name)
                        try await Self.saveLocally(item, to: destination, serverURL: serverURL, filesClient: filesClient, send: nil)
                        savedCount += 1
                    } catch {
                        continue
                    }
                }
                await send(.bulkDownloadResponse(savedCount: savedCount, total: targets.count))
            }
        }

        /// Saves a file, or a whole folder as a real folder tree (no server side zip), at
        /// `destination`. Folder progress reports "N of M" through `send` when given.
        static func saveLocally(
            _ item: FileItem,
            to destination: URL,
            serverURL: URL,
            filesClient: FilesClient,
            send: Send<Action>?
        ) async throws {
            guard item.isDirectory else {
                let cachedURL = try await filesClient.downloadRawFile(serverURL, item)
                try MacDownloadSaving.copy(cachedURL, to: destination)
                return
            }
            let files = try await OfflineDownloadsFeature.enumerate(roots: [item], serverURL: serverURL, filesClient: filesClient)
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            let rootPrefix = item.id + "/"
            for (index, file) in files.enumerated() {
                try Task.checkCancellation()
                await send?(.downloadProgressUpdated(L10n.Browse.progressDownloadingIndexed(index + 1, files.count)))
                let relativePath = file.id.hasPrefix(rootPrefix) ? String(file.id.dropFirst(rootPrefix.count)) : file.name
                // Server names are untrusted: never let one escape the chosen folder.
                guard let target = SafeDestination.within(destination, relativePath) else { continue }
                try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                let cachedURL = try await filesClient.downloadRawFile(serverURL, file)
                try MacDownloadSaving.copy(cachedURL, to: target)
            }
        }

        /// The folder a success toast names: the chosen folder itself, or the one holding a file.
        func savedDownloadFolderName(_ url: URL) -> String {
            url.hasDirectoryPath ? url.lastPathComponent : url.deletingLastPathComponent().lastPathComponent
        }
    }
#endif
