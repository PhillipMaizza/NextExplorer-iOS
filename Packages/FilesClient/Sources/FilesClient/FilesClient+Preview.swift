import CoreModels
import Foundation

extension FilesClient {
    public static let previewValue = FilesClient(
        browse: { _, path in
            BrowseResult(
                items: FileItem.previewItems,
                access: FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true),
                path: path
            )
        },
        search: { _, _, _, _ in [] },
        favorites: { _ in Favorite.previewFavorites },
        volumes: { _ in Volume.previewVolumes },
        fetchPreferences: { _ in UserPreferences() },
        updatePreference: { _, _, _ in }
    )
}

extension FileItem {
    static let previewItems: [FileItem] = [
        FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory"),
        FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory"),
        FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 2_400_000, kind: "jpg", supportsThumbnail: true),
        FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 1_024, kind: "txt")
    ]
}

extension Favorite {
    static let previewFavorites: [Favorite] = [
        Favorite(id: "1", path: "Documents", label: "Documents", icon: "folder", color: nil, position: 0, createdAt: Date(), updatedAt: Date())
    ]
}

extension Volume {
    static let previewVolumes: [Volume] = [
        Volume(name: "media", path: "media"),
        Volume(name: "home", path: "home")
    ]
}
