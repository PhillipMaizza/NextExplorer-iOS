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
}
