#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import Foundation

    /// A Mac saves where the user says (save panel), as real files and folder trees. Once a place
    /// is chosen the save goes to the app wide download queue, so it survives this folder closing,
    /// can be cancelled, and never holds up the folder's other file actions. Drops and picks
    /// upload the same direct way.
    extension BrowseFeature {
        func startDownload(_: inout State, item: FileItem) -> Effect<Action> {
            let saveLocationPicker = saveLocationPicker
            return .run { send in
                guard let destination = await saveLocationPicker.chooseFile(item.name) else { return }
                await send(.delegate(.saveRequested([DownloadSaveRequest(item: item, target: .replacing(destination))])))
            }
        }

        /// A drop or pick names its folder already, so it uploads straight away, no review sheet.
        func stageDirectUpload(_ urls: [URL], destination: String) -> Effect<Action> {
            let uploadStaging = uploadStaging
            return .run { send in
                var staged: [PickedFile] = []
                for await file in uploadStaging.stageDocuments(urls) {
                    staged.append(file)
                }
                await send(.directUploadStaged(staged, destination: destination, requested: urls.count))
            }
        }

        func startBulkDownload(_: inout State, targets: [FileItem]) -> Effect<Action> {
            guard !targets.isEmpty else { return .none }
            let saveLocationPicker = saveLocationPicker
            return .run { send in
                guard let folder = await saveLocationPicker.chooseFolder() else { return }
                await send(.delegate(.saveRequested(targets.map { DownloadSaveRequest(item: $0, target: .into(folder)) })))
            }
        }
    }
#endif
