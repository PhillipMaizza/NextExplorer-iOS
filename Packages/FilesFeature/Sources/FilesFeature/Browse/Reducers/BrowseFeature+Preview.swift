import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

extension BrowseFeature {
    /// `settle` holds the requests back a moment, for an inspector following the selection: arrow
    /// keys skipping past rows then never ask the server for each one (a folder's size is a scan).
    func closeInfo(_ state: inout State) -> Effect<Action> {
        state.infoItem = nil
        state.infoMetadata = nil
        state.infoUsage = nil
        state.infoPhase = .idle
        state.isInfoShowingSelection = false
        return .cancel(id: CancelID.info)
    }

    func showSelectionInfo(_ state: inout State) -> Effect<Action> {
        let effect = closeInfo(&state)
        state.isInfoShowingSelection = true
        return effect
    }

    func settleSelectionInfo(_ state: inout State) -> Effect<Action> {
        guard state.isInfoShowingSelection else { return .none }
        let selected = state.selectedItems
        guard selected.count < 2 else { return .none }
        guard let item = selected.first ?? state.folderItem(now: date.now) else { return closeInfo(&state) }
        return loadInfo(&state, item: item)
    }

    func loadInfo(_ state: inout State, item: FileItem, settle: Duration? = nil) -> Effect<Action> {
        state.isInfoShowingSelection = false
        state.infoItem = item
        state.infoMetadata = nil
        state.infoUsage = nil
        state.infoPhase = .loading
        let serverURL = state.serverURL
        let filesClient = filesClient
        let clock = clock
        let path = item.id
        let metadata = Effect<Action>.run { send in
            if let settle {
                try await clock.sleep(for: settle)
            }
            try await send(.infoMetadataResponse(apiResult { try await filesClient.fetchMetadata(serverURL, path) }))
        }
        guard item.isDirectory else { return metadata.cancellable(id: CancelID.info, cancelInFlight: true) }
        return .merge(metadata, .run { send in
            if let settle {
                try await clock.sleep(for: settle)
            }
            try await send(.infoUsageResponse(apiResult { try await filesClient.fetchUsage(serverURL, path) }))
        })
        .cancellable(id: CancelID.info, cancelInFlight: true)
    }

    /// Only reached for non streamable items: `rowTapped` already set `state.previewItem`
    /// and skipped this for video/audio, which play live instead of downloading.
    func loadPreview(_ state: inout State, item: FileItem) -> Effect<Action> {
        state.previewFileURL = nil
        state.previewPhase = .loading
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .run { send in
            try await send(.previewFileResponse(apiResult { try await filesClient.previewDocument(serverURL, item) }))
        }
        .cancellable(id: CancelID.preview, cancelInFlight: true)
    }

    func loadTextContent(_ state: inout State, item: FileItem) -> Effect<Action> {
        state.textContent = nil
        state.textSaveError = nil
        state.textSaveConflict = nil
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
        guard let item = state.previewItem, state.savingTexts[item.id] == nil else { return .none }
        if state.textSaveConflict != nil {
            state.textSaveConflict = State.TextSaveConflict(pendingText: newContent)
            return .none
        }
        state.savingTexts[item.id] = newContent
        state.textSaveError = nil
        let serverURL = state.serverURL
        let filesClient = filesClient
        let path = item.id
        // Never cancelled: once the PUT is sent the server may apply it, so dropping the answer would
        // leave the save state unresolved. Closing or switching the preview only stops showing it.
        return .run { send in
            try await send(.textSaveResponse(path: path, result: apiResult {
                try await filesClient.saveTextContent(serverURL, path, newContent)
                return newContent
            }))
        }
    }
}

extension BrowseFeature.State {
    /// The cover shows the text editor instead of the gallery: a file New File just made, a Google
    /// Drive stub whose link could not be read, or a text file the gallery's Edit handed over.
    var shouldShowTextEditor: Bool {
        guard let item = previewItem else { return false }
        return isPreviewEditing || newlyCreatedFileID == item.id || item.isGoogleDocsPointer
    }

    /// Whether the open preview is the gallery, which deletes in place and stays open on the
    /// neighbour. iPhone and iPad page through every file; the Mac steps with the arrow keys and
    /// pages only its images.
    var isPreviewInGallery: Bool {
        guard let item = previewItem, !shouldShowTextEditor else { return false }
        #if os(iOS)
            return true
        #else
            return PreviewKind(item) == .image
        #endif
    }

    /// Whether the cover has what it needs to present: the gallery opens at once, but the file
    /// tapped as a document or text waits for its first fetch so the cover zooms in on content.
    var isPreviewContentReady: Bool {
        guard let item = previewItem else { return false }
        if isPreviewEditing {
            return true
        }
        switch PreviewKind(item) {
        case .unsupported, .media, .archive, .image:
            return true
        case .document:
            return previewFileURL != nil || previewErrorMessage != nil
        case .text:
            return textContent != nil || textEditorErrorMessage != nil
        }
    }

    /// The files the gallery swipes through, in list order: every file shown except Google Drive
    /// stubs, which open their linked document instead. A file opened on its own (Favorites, the
    /// Offline tab) has no listing loaded here, and a search hit may sit in another folder, so both
    /// page alone. Once a listing is loaded it is the truth: a deleted file leaves it, so the
    /// gallery moves on or closes.
    func galleryItems(startingAt item: FileItem) -> [FileItem] {
        guard phase != .idle, !isPreviewOutsideListing else { return [item] }
        return Array(displayedItems.filter { !$0.isDirectory && !$0.isGoogleDocsPointer })
    }
}
