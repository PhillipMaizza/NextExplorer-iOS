import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

extension BrowseFeature {
    func loadInfo(_ state: inout State, item: FileItem) -> Effect<Action> {
        state.infoItem = item
        state.infoMetadata = nil
        state.infoUsage = nil
        state.infoPhase = .loading
        let serverURL = state.serverURL
        let filesClient = filesClient
        let path = item.id
        let metadata = Effect<Action>.run { send in
            try await send(.infoMetadataResponse(apiResult { try await filesClient.fetchMetadata(serverURL, path) }))
        }
        guard item.isDirectory else { return metadata.cancellable(id: CancelID.info, cancelInFlight: true) }
        return .merge(metadata, .run { send in
            try await send(.infoUsageResponse(apiResult { try await filesClient.fetchUsage(serverURL, path) }))
        })
        .cancellable(id: CancelID.info, cancelInFlight: true)
    }

    /// Only reached for non-streamable items — `rowTapped` already set `state.previewItem`
    /// and skipped this for video/audio, which play live instead of downloading.
    func loadPreview(_ state: inout State, item: FileItem) -> Effect<Action> {
        state.previewFileURL = nil
        state.previewPhase = .loading
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.previewFileResponse(apiResult {
                // Word docs aren't in `PREVIEWABLE_EXTENSIONS` — `GET /api/preview` 415s them,
                // so they come down via the unrestricted download endpoint instead.
                item.isOfficeDocument
                    ? try await filesClient.downloadRawFile(serverURL, item)
                    : try await filesClient.previewFile(serverURL, item)
            }))
        }
        .cancellable(id: CancelID.preview, cancelInFlight: true)
    }

    func loadTextContent(_ state: inout State, item: FileItem) -> Effect<Action> {
        state.textContent = nil
        state.textSaveError = nil
        state.textPhase = .loading
        let serverURL = state.serverURL
        let filesClient = filesClient
        let path = item.id
        return .run { send in
            try await send(.textContentResponse(apiResult { try await filesClient.fetchTextContent(serverURL, path) }))
        }
        .cancellable(id: CancelID.preview, cancelInFlight: true)
    }

    /// Fetches a Google Drive stub file, reads the link out of its JSON, and hands it to the
    /// system to open (the Google app or the browser). No preview state is touched unless the
    /// fetch fails, in which case `googleDocsPointerResponse` falls back to the text viewer.
    func openGoogleDocsPointer(serverURL: URL, item: FileItem) -> Effect<Action> {
        let filesClient = filesClient
        let path = item.id
        return .run { send in
            try await send(.googleDocsPointerResponse(item: item, apiResult {
                let contents = try await filesClient.fetchTextContent(serverURL, path)
                guard let url = GoogleDocsPointer.targetURL(fromContents: contents) else {
                    throw FilesClientError.decoding("Google Drive stub has no link")
                }
                return url
            }))
        }
        .cancellable(id: CancelID.googleDocsPointer, cancelInFlight: true)
    }

    func confirmTextSave(_ state: inout State, newContent: String) -> Effect<Action> {
        guard !state.isSavingTextContent, let item = state.previewItem else { return .none }
        state.isSavingTextContent = true
        state.textSaveError = nil
        let serverURL = state.serverURL
        let filesClient = filesClient
        let path = item.id
        return .run { send in
            try await send(.textSaveResponse(apiResult {
                try await filesClient.saveTextContent(serverURL, path, newContent)
                return newContent
            }))
        }
    }
}
