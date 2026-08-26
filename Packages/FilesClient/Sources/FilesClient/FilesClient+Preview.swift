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
        addFavorite: { _, path in
            Favorite(id: UUID().uuidString, path: path, label: nil, icon: "star", color: nil, position: 0, createdAt: Date(), updatedAt: Date())
        },
        removeFavorite: { _, _ in },
        volumes: { _ in Volume.previewVolumes },
        fetchPreferences: { _ in UserPreferences() },
        updatePreference: { _, _, _ in },
        renameItem: { _, item, newName in
            FileItem(name: newName, path: item.path, dateModified: item.dateModified, size: item.size, kind: item.kind, supportsThumbnail: item.supportsThumbnail)
        },
        deleteItems: { _, _ in },
        fetchMetadata: { _, path in
            FileMetadata(
                path: path,
                name: (path as NSString).lastPathComponent,
                kind: "directory",
                size: 4_096,
                dateModified: Date(),
                dateCreated: Date(),
                directory: FileMetadata.DirectorySummary(totalSize: 10_485_760, fileCount: 42, dirCount: 3, truncated: false)
            )
        }
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
