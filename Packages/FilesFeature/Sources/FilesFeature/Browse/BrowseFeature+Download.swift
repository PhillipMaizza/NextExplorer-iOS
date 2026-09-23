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
        #if os(macOS)
            // A Mac saves where the user says, asked before any bytes move.
            state.fileActionProgressMessage = nil
            let saveLocationPicker = saveLocationPicker
            return .run { send in
                guard let destination = await saveLocationPicker.chooseFile(item.name) else {
                    await send(.downloadCancelled)
                    return
                }
                await send(.downloadProgressUpdated(L10n.Browse.progressDownloading))
                try await send(.downloadResponse(apiResult {
                    try await Self.saveLocally(item, to: destination, serverURL: serverURL, filesClient: filesClient, send: send)
                    return DownloadResult(destinationURL: destination, location: location)
                }))
            }
        #else
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
        #endif
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
        #if os(macOS)
            state.fileActionProgressMessage = nil
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
                await send(.bulkDownloadResponse(savedCount: savedCount, total: targets.count, location: location))
            }
        #else
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
        #endif
    }

    #if os(macOS)
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
    #endif

    /// The place a download's success toast names: the chosen folder on macOS, the app's own
    /// download location on iOS.
    func downloadDestinationTitle(_ state: State, location: DownloadLocation) -> String {
        #if os(macOS)
            if let url = state.lastSavedDownloadURL {
                return url.hasDirectoryPath ? url.lastPathComponent : url.deletingLastPathComponent().lastPathComponent
            }
        #endif
        return location.title
    }
}
