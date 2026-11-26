import CoreModels

struct FileItemActions: Equatable {
    var canDownload = false
    var canKeepOffline = false
    var canExport = false
    var canRename = false
    var canEditText = false
    var canEditPermissions = false
    var canCopy = false
    var canDuplicate = false
    var canMove = false
    var canCompress = false
    var canExtract = false
    var canShare = false
    var canDelete = false

    var hasOrganizeActions: Bool {
        canRename || canDuplicate || canMove || canCopy || canCompress || canExtract
    }
}

extension BrowseFeature.State {
    func actions(for item: FileItem) -> FileItemActions {
        actions(for: [item])
    }

    func actions(for picked: [FileItem]) -> FileItemActions {
        guard let first = picked.first, let access, picked.allSatisfy({ self.access(for: $0) != nil }) else {
            return FileItemActions()
        }
        let isOnServer = !shouldShowDeviceContent
        let isListed = picked.allSatisfy { items[id: $0.id] != nil }
        let isSoleRootLocation = directoryPath.isEmpty && items.count <= 1
        let isSingle = picked.count == 1
        return FileItemActions(
            canDownload: access.canDownload,
            canKeepOffline: access.canDownload && isOnServer,
            canExport: access.canDownload,
            canRename: isSingle && access.canWrite,
            canEditText: isSingle && access.canWrite,
            canEditPermissions: isSingle && access.canWrite && isOnServer,
            canCopy: isOnServer && !isSoleRootLocation,
            canDuplicate: isOnServer && isListed && !directoryPath.isEmpty && access.canReceive(picked),
            canMove: access.canMove && !isSoleRootLocation,
            canCompress: isSingle && access.canCompress,
            canExtract: isSingle && canExtract(first) && access.canExtract,
            canShare: access.canShare && isOnServer,
            canDelete: access.canDelete
        )
    }
}
