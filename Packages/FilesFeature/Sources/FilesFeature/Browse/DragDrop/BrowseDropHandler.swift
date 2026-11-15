import ComposableArchitecture
import CoreModels
import Foundation

/// What a drop on a folder row, a grid cell or the folder background comes to: the reducer actions
/// to send, and the staged file copies no action takes over, which are deleted at once.
enum BrowseDropHandler {
    struct Resolution: Equatable {
        var actions: [BrowseFeature.Action]
        var discardedFiles: [URL]
    }

    static func resolve(
        drops: [BrowseDrop],
        folder: FileItem?,
        listed: [FileItem.ID],
        directoryPath: String,
        receiver: DragOrigin,
        canMove: Bool,
        canUpload: Bool
    ) -> Resolution {
        let plan = BrowseDropPlan(
            drops: drops,
            listed: listed,
            destination: folder?.id ?? directoryPath,
            receiver: receiver
        )
        let actions = BrowseDropRouter.actions(
            for: plan,
            folder: folder,
            directoryPath: directoryPath,
            canMove: canMove,
            canUpload: canUpload
        )
        let taken = Set(BrowseDropRouter.fileURLs(in: actions))
        return Resolution(actions: actions, discardedFiles: plan.fileURLs.filter { !taken.contains($0) })
    }

    /// Deletes the staged copies of a drop that was refused, so none outlives it.
    static func discard(
        _ urls: [URL],
        temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) {
        for url in urls {
            DroppedFileStaging.discardCopy(at: url, temporaryDirectory: temporaryDirectory)
        }
    }

    /// The same deletion for a reducer that refuses a drop, off the main actor.
    static func discardStagedFiles(_ urls: [URL]) -> Effect<BrowseFeature.Action> {
        .run { _ in discard(urls) }
    }
}
