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
        },
        thumbnailURL: { _, _ in nil },
        previewFile: { _, item in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Previews-Preview", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(item.name)
            try? Data().write(to: fileURL)
            return fileURL
        },
        fetchTextContent: { _, _ in "" },
        saveTextContent: { _, _, _ in },
        extractZip: { _, item in
            FileItem(name: item.name.replacingOccurrences(of: ".zip", with: ""), path: item.path, dateModified: Date(), size: 0, kind: "directory")
        },
        downloadRawFile: { _, item in
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Downloads-Preview", isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let fileURL = directory.appendingPathComponent(item.name)
            try? Data().write(to: fileURL)
            return fileURL
        },
        compressItem: { _, item in
            FileItem(name: "\(item.name).zip", path: item.path, dateModified: Date(), size: 0, kind: "zip")
        },
        createShareLink: { _, request in
            let token = "PREVIEW1234"
            let share = Share(
                id: UUID().uuidString,
                shareToken: token,
                ownerId: "preview-user",
                sourcePath: request.sourcePath,
                isDirectory: false,
                accessMode: request.accessMode,
                sharingType: request.target,
                hasPassword: request.password?.isEmpty == false,
                expiresAt: request.expiresAt,
                label: request.label,
                createdAt: Date(),
                updatedAt: Date()
            )
            return CreatedShare(
                share: share,
                shareUrl: URL(string: "https://cloud.example.com/share/\(token)")!,
                directFileUrl: URL(string: "https://cloud.example.com/api/share/\(token)/file")!
            )
        },
        mySharedLinks: { _ in Share.previewSharedByMe },
        sharedWithMeLinks: { _ in Share.previewSharedWithMe },
        deleteShareLink: { _, _ in }
    )
}

extension Share {
    static let previewSharedByMe: [Share] = [
        Share(
            id: "s1", shareToken: "UrkLIGIHMF", ownerId: "preview-user",
            sourcePath: "Documents/Bills/Electricity", isDirectory: true,
            accessMode: .readonly, sharingType: .anyone, hasPassword: false,
            expiresAt: nil, label: "Electricity", downloadCount: 3,
            lastAccessedAt: Date(), createdAt: Date(), updatedAt: Date()
        ),
        Share(
            id: "s2", shareToken: "9fKq2Lm0xP", ownerId: "preview-user",
            sourcePath: "Photos/2024/passport.pdf", isDirectory: false,
            accessMode: .readonly, sharingType: .users, hasPassword: true,
            expiresAt: Date().addingTimeInterval(86_400 * 7), label: nil,
            downloadCount: 0, lastAccessedAt: nil, createdAt: Date(), updatedAt: Date()
        )
    ]

    static let previewSharedWithMe: [Share] = [
        Share(
            id: "s3", shareToken: "abc123XYZ0", ownerId: "someone-else",
            sourceName: "Team Roadmap", isDirectory: true,
            accessMode: .readwrite, sharingType: .users, hasPassword: false,
            expiresAt: nil, label: "Team Roadmap", downloadCount: 0,
            lastAccessedAt: nil, createdAt: Date(), updatedAt: Date()
        )
    ]
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
