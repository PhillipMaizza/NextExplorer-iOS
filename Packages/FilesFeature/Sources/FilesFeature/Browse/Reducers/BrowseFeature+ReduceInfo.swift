import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import FolderPickerFeature
import Foundation
import Localization
import NetworkClient
import ShareUploads
import SwiftUI

extension BrowseFeature {
    /// The info and permissions sheets, the file preview and the text editor.
    func reduceInfo(_ state: inout State, _ action: Action) -> Effect<Action> {
        switch action {
        case let .infoTapped(item):
            return loadInfo(&state, item: item)

        case let .permissionsTapped(item):
            guard state.actions(for: item).canEditPermissions else { return .none }
            state.permissions = PermissionsFeature.State(serverURL: state.serverURL, item: item)
            return .none

        case .permissions:
            return .none

        case .infoDismissed:
            return closeInfo(&state)

        case let .infoMetadataResponse(.success(metadata)):
            state.infoPhase = .loaded
            state.infoMetadata = metadata
            return .none

        case let .infoMetadataResponse(.failure(error)):
            state.infoPhase = .failed(error.userMessage)
            return .none

        case let .infoUsageResponse(.success(usage)):
            // Kept only when the server actually reported disk figures: a denied path
            // answers all zeros, which the "Server disk" section shouldn't show.
            state.infoUsage = usage.isMeaningful ? usage : nil
            return .none

        case .infoUsageResponse(.failure):
            return .none

        case .previewDismissed:
            state.newlyCreatedFileID = nil
            state.previewItem = nil
            state.isPreviewOutsideListing = false
            state.previewFileURL = nil
            state.previewPhase = .idle
            state.textContent = nil
            state.textPhase = .idle
            state.textSaveError = nil
            state.textSaveConflict = nil
            state.isPreviewEditing = false
            return .merge(.cancel(id: state.cancelID(.preview)), .cancel(id: state.cancelID(.googleDocsPointer)))

        case let .previewEditTapped(item):
            // The gallery swiped to this file, so it becomes the preview; a fresh read so the
            // edit starts from what the server holds now.
            state.previewItem = item
            state.isPreviewEditing = true
            state.previewFileURL = nil
            state.previewPhase = .idle
            return loadTextContent(&state, item: item)

        case .previewEditorClosed:
            // Back to the gallery on the same file. The text stays: the gallery page shows it
            // without asking again, including what a save just wrote.
            state.isPreviewEditing = false
            state.textSaveError = nil
            state.textSaveConflict = nil
            return .none

        case let .previewFileResponse(.success(fileURL)):
            state.previewPhase = .loaded
            state.previewFileURL = fileURL
            return .none

        case let .previewFileResponse(.failure(error)):
            state.previewPhase = .failed(error.userMessage)
            return .none

        case let .textContentResponse(.success(content)):
            state.textPhase = .loaded
            state.textContent = content
            return .none

        case let .textContentResponse(.failure(error)):
            state.textPhase = .failed(error.userMessage)
            return .none

        case let .openInBrowserTapped(item):
            guard item.isHTML,
                  let url = FilesClient.rawFileURL(serverURL: state.serverURL, item: item) else { return .none }
            return .run { [openURL] _ in await openURL(url) }

        case let .googleDocsPointerResponse(item, result):
            switch result {
            case let .success(url):
                return .run { [openURL] _ in await openURL(url) }
            case .failure:
                // Couldn't read the stub or it had no usable link: fall back to showing
                // it in the text viewer rather than leaving the tap dead.
                state.previewItem = item
                return loadTextContent(&state, item: item)
            }

        case .textContentRetryTapped:
            guard let item = state.previewItem else { return .none }
            return loadTextContent(&state, item: item)

        case let .textSaveTapped(newContent):
            guard let item = state.previewItem, state.actions(for: item).canEditText else { return .none }
            return confirmTextSave(&state, newContent: newContent)

        case let .textSaveResponse(path, .success(savedContent)):
            let isStillOpen = path == state.previewItem?.id
            state.savingTexts[path] = nil
            if isStillOpen {
                state.textContent = savedContent
            }
            return .none

        case let .textSaveResponse(path, .failure(error)):
            let isStillOpen = path == state.previewItem?.id
            let pendingText = state.savingTexts.removeValue(forKey: path)
            if isStillOpen, error == .changedOnServer {
                state.textSaveConflict = pendingText.map { State.TextSaveConflict(pendingText: $0) }
                state.textSaveError = error.userMessage
            } else if isStillOpen {
                state.textSaveError = error.userMessage
            } else {
                state.fileActionErrorMessage = error.userMessage
            }
            return .none

        case .textSaveOverwriteTapped:
            guard let content = state.textSaveConflict?.pendingText else { return .none }
            state.textSaveConflict = nil
            state.textSaveError = nil
            return confirmTextSave(&state, newContent: content)

        case .textSaveReloadTapped:
            guard let item = state.previewItem else { return .none }
            return loadTextContent(&state, item: item)

        case .textSaveConflictDismissed:
            state.textSaveConflict?.isAlertPresented = false
            state.textSaveError = nil
            return .none

        default:
            return .none
        }
    }
}
