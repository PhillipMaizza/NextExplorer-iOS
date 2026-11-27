#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import Foundation

    private enum ArchiveDownload {
        static let fileExtension = "zip"
        static let fallbackName = "download"
    }

    /// A Mac saves where the user says (save panel), as real files and folder trees. Once a place
    /// is chosen the save goes to the app wide download queue, so it survives this folder closing,
    /// can be cancelled, and never holds up the folder's other file actions. Drops and picks
    /// upload the same direct way.
    extension BrowseFeature {
        func startDownload(_: inout State, item: FileItem) -> Effect<Action> {
            let saveLocationPicker = saveLocationPicker
            return .run { send in
                guard let destination = await saveLocationPicker.chooseFile(item.name) else { return }
                await send(.delegate(.saveRequested([DownloadSaveRequest(
                    item: item,
                    target: .replacing(destination)
                )])))
            }
        }

        func startArchiveDownload(_ state: inout State, targets: [FileItem]) -> Effect<Action> {
            guard let basePath = targets.first?.path else { return .none }
            let base = SafeFileName.component(state.title, fallback: ArchiveDownload.fallbackName)
            let archive = FileItem(
                name: "\(base).\(ArchiveDownload.fileExtension)",
                path: basePath,
                dateModified: date.now,
                size: 0,
                kind: ArchiveDownload.fileExtension
            )
            let saveLocationPicker = saveLocationPicker
            return .run { send in
                guard let destination = await saveLocationPicker.chooseFile(archive.name) else { return }
                await send(.delegate(.saveRequested([DownloadSaveRequest(
                    item: archive,
                    target: .replacing(destination),
                    archiveOf: targets
                )])))
            }
        }

        func startBulkDownload(_: inout State, targets: [FileItem]) -> Effect<Action> {
            guard !targets.isEmpty else { return .none }
            let saveLocationPicker = saveLocationPicker
            return .run { send in
                guard let folder = await saveLocationPicker.chooseFolder() else { return }
                await send(.delegate(.saveRequested(targets
                        .map { DownloadSaveRequest(item: $0, target: .into(folder)) })))
            }
        }
    }
#endif
