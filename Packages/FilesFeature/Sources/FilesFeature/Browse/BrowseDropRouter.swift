import CoreModels
import Foundation

/// Turns a drop on a folder row, a grid cell or the folder background into the reducer actions
/// the Mac path already sends, so both platforms share one move and upload flow.
enum BrowseDropRouter {
    static func actions(
        for plan: BrowseDropPlan,
        folder: FileItem?,
        directoryPath: String,
        canMove: Bool,
        canUpload: Bool
    ) -> [BrowseFeature.Action] {
        var actions: [BrowseFeature.Action] = []
        if let folder {
            guard folder.isDirectory else { return [] }
            if canMove, !plan.listedIDs.isEmpty {
                actions.append(.itemsDroppedOnFolder(ids: plan.listedIDs, folder: folder))
            }
            if canMove, !plan.foreignItems.isEmpty {
                actions.append(.itemsDroppedFromOtherWindow(plan.foreignItems, destination: folder.id))
            }
            if canUpload, !plan.fileURLs.isEmpty {
                actions.append(.filesDroppedOnFolder(plan.fileURLs, folder: folder))
            }
        } else {
            if canMove, !directoryPath.isEmpty, !plan.foreignItems.isEmpty {
                actions.append(.itemsDroppedFromOtherWindow(plan.foreignItems, destination: directoryPath))
            }
            if canUpload, !plan.fileURLs.isEmpty {
                actions.append(.beginUpload(.documents(plan.fileURLs)))
            }
        }
        return actions
    }

    /// The dropped files the actions take over (they upload them, so they own deleting the copies).
    static func fileURLs(in actions: [BrowseFeature.Action]) -> [URL] {
        actions.flatMap { action -> [URL] in
            switch action {
            case let .filesDroppedOnFolder(urls, _), let .beginUpload(.documents(urls)):
                urls
            default:
                []
            }
        }
    }
}

/// Whether a drag hovering over a folder would be taken, so the folder only outlines itself for a
/// drop that does something. `draggedRows` are the rows of this window being dragged, empty for a
/// drag the window did not start (files from another app, rows from another window).
enum BrowseDropAcceptance {
    static func canAccept(
        destination: String,
        isFolder: Bool,
        draggedRows: [FileItem],
        canMove: Bool,
        canUpload: Bool
    ) -> Bool {
        guard isFolder else { return false }
        let canMoveHere = canMove && !destination.isEmpty
        if draggedRows.isEmpty {
            return canUpload || canMoveHere
        }
        return canMoveHere && draggedRows.contains { BrowseDropPlan.canMove($0, into: destination) }
    }
}
