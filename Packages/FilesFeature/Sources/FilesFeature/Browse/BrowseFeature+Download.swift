import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization

extension BrowseFeature {
    /// Folders have no dedicated "zip and stream" endpoint, so they're compressed server-side
    /// first (the same `compressItem` the context menu's own "Compress" action uses — this
    /// leaves the resulting `.zip` sitting alongside the folder on the server, same side
    /// effect "Compress" already has) and the resulting archive is downloaded like any file.
    func startDownload(_ state: inout State, item: FileItem, location: DownloadLocation, removeArchiveAfterDownload: Bool) -> Effect<Action> {
        guard !state.isPerformingFileAction else { return .none }
        state.isPerformingFileAction = true
        state.fileActionProgressMessage = item.isDirectory ? L10n.Browse.progressCompressing : L10n.Browse.progressDownloading
        let serverURL = state.serverURL
        let filesClient = filesClient
        let localDownloadStore = localDownloadStore
        let downloadScope = state.downloadScope
        return .run { send in
            try await send(.downloadResponse(apiResult {
                var compressedArchive: FileItem?
                let fileToDownload: FileItem
                if item.isDirectory {
                    let archive = try await filesClient.compressItem(serverURL, item)
                    compressedArchive = archive
                    fileToDownload = archive
                    await send(.downloadProgressUpdated(L10n.Browse.progressDownloading))
                } else {
                    fileToDownload = item
                }
                let cachedURL = try await filesClient.downloadRawFile(serverURL, fileToDownload)
                let destinationURL = try localDownloadStore.save(cachedURL, fileToDownload.name, location, downloadScope)
                // Best-effort, and after the fact — the download already succeeded, so a
                // cleanup failure here shouldn't surface as an error to the user.
                if removeArchiveAfterDownload, let compressedArchive {
                    try? await filesClient.deleteItems(serverURL, [compressedArchive])
                }
                return DownloadResult(destinationURL: destinationURL, location: location)
            }))
        }
    }

    /// Sequential, not concurrent: reuses the same compress-then-download chain
    /// `startDownload` uses for a single folder, one selected item at a time, so the
    /// progress toast can report "N of M" as it goes. Best-effort — one item's failure
    /// doesn't stop the rest of the batch.
    func startBulkDownload(_ state: inout State, location: DownloadLocation, removeArchiveAfterDownload: Bool) -> Effect<Action> {
        guard !state.isBulkActionInFlight else { return .none }
        let targets = state.selectedItemIDs.compactMap { state.items[id: $0] }
        guard !targets.isEmpty else { return .none }
        state.isBulkActionInFlight = true
        state.fileActionProgressMessage = L10n.Browse.progressDownloadingIndexed(1, targets.count)
        let serverURL = state.serverURL
        let filesClient = filesClient
        let localDownloadStore = localDownloadStore
        let downloadScope = state.downloadScope
        return .run { send in
            var savedCount = 0
            for (index, item) in targets.enumerated() {
                if index > 0 {
                    await send(.downloadProgressUpdated(L10n.Browse.progressDownloadingIndexed(index + 1, targets.count)))
                }
                do {
                    var compressedArchive: FileItem?
                    let fileToDownload: FileItem
                    if item.isDirectory {
                        let archive = try await filesClient.compressItem(serverURL, item)
                        compressedArchive = archive
                        fileToDownload = archive
                    } else {
                        fileToDownload = item
                    }
                    let cachedURL = try await filesClient.downloadRawFile(serverURL, fileToDownload)
                    _ = try localDownloadStore.save(cachedURL, fileToDownload.name, location, downloadScope)
                    if removeArchiveAfterDownload, let compressedArchive {
                        try? await filesClient.deleteItems(serverURL, [compressedArchive])
                    }
                    savedCount += 1
                } catch {
                    continue
                }
            }
            await send(.bulkDownloadResponse(savedCount: savedCount, total: targets.count, location: location))
        }
    }
}
