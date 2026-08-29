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
        fetchBranding: { _ in Branding(appName: "Rivendell Cloud", appLogoUrl: "/static/logos/custom-logo.png") },
        updateBranding: { _, appName, appLogoUrl in Branding(appName: appName, appLogoUrl: appLogoUrl) },
        uploadServerLogo: { _, _ in "/static/logos/custom-logo.png" },
        renameItem: { _, item, newName in
            FileItem(name: newName, path: item.path, dateModified: item.dateModified, size: item.size, kind: item.kind, supportsThumbnail: item.supportsThumbnail)
        },
        createFolder: { _, path, name in
            FileItem(name: name.isEmpty ? "Untitled Folder" : name, path: path, dateModified: Date(), size: 0, kind: "directory")
        },
        deleteImpact: { _, _ in DeleteImpact(shareCount: 0) },
        deleteItems: { _, _ in },
        transferItems: { _, items, destination, _ in
            TransferResult(
                destination: destination,
                items: items.map { TransferResult.Entry(from: $0.id, to: "\(destination)/\($0.name)") }
            )
        },
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
        uploadFile: { _, _, fileName, destination, onProgress in
            onProgress(1)
            return FileItem(name: fileName, path: destination, dateModified: Date(), size: 0, kind: (fileName as NSString).pathExtension.lowercased())
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
        deleteShareLink: { _, _ in },
        shareableUsers: { _ in
            [
                User(id: "u2", username: "jamie", email: "jamie@example.com", displayName: "Jamie Rivera"),
                User(id: "u3", username: "sam", email: "sam@example.com", displayName: "Sam Okafor")
            ]
        },
        changeOwnPassword: { _, _, _ in },
        serverFeatures: { _ in ServerFeatures(isUserVolumesEnabled: true) },
        listUsers: { _ in User.previewManagedUsers },
        createUser: { _, request in
            User(
                id: UUID().uuidString,
                username: request.username ?? request.email.components(separatedBy: "@").first ?? request.email,
                email: request.email,
                displayName: request.displayName,
                roles: request.isAdmin ? ["admin"] : [],
                createdAt: Date(),
                updatedAt: Date(),
                authMethods: [AuthMethod(method: "local_password")]
            )
        },
        updateUser: { _, userID, request in
            let base = User.previewManagedUsers.first { $0.id == userID } ?? User.previewManagedUsers[0]
            return User(
                id: base.id,
                username: request.username ?? base.username,
                email: request.email ?? base.email,
                displayName: request.displayName ?? base.displayName,
                roles: request.roles ?? base.roles,
                emailVerified: base.emailVerified,
                createdAt: base.createdAt,
                updatedAt: Date(),
                authMethods: base.authMethods
            )
        },
        setUserPassword: { _, _, _ in },
        deleteUser: { _, _ in },
        userVolumes: { _, userID in UserVolume.previewVolumes(userID: userID) },
        addUserVolume: { _, userID, request in
            UserVolume(
                id: UUID().uuidString,
                userId: userID,
                label: request.label,
                path: request.path,
                accessMode: request.accessMode,
                createdAt: Date(),
                updatedAt: Date()
            )
        },
        updateUserVolume: { _, userID, volumeID, label, accessMode in
            UserVolume(
                id: volumeID,
                userId: userID,
                label: label ?? "Volume",
                path: "/srv/volumes/\(label ?? "volume")",
                accessMode: accessMode,
                createdAt: Date(),
                updatedAt: Date()
            )
        },
        removeUserVolume: { _, _, _ in },
        browseAdminDirectories: { _, path in
            let base = path ?? "/srv/volumes"
            return AdminDirectoryListing(
                current: base,
                parent: base == "/srv/volumes" ? nil : "/srv/volumes",
                directories: [
                    AdminDirectory(name: "projects", path: base + "/projects"),
                    AdminDirectory(name: "media", path: base + "/media"),
                    AdminDirectory(name: "backups", path: base + "/backups")
                ]
            )
        }
    )
}

extension User {
    public static let previewManagedUsers: [User] = [
        User(
            id: "u1", username: "admin", email: "admin@example.com", displayName: "Site Admin",
            roles: ["admin"], emailVerified: true, createdAt: Date(timeIntervalSinceNow: -86_400 * 90),
            updatedAt: Date(), authMethods: [AuthMethod(method: "local_password")]
        ),
        User(
            id: "u2", username: "jamie", email: "jamie@example.com", displayName: "Jamie Rivera",
            roles: [], emailVerified: true, createdAt: Date(timeIntervalSinceNow: -86_400 * 30),
            updatedAt: Date(), authMethods: [AuthMethod(method: "local_password"), AuthMethod(method: "oidc", provider: "Authentik")]
        ),
        User(
            id: "u3", username: "sam", email: "sam@example.com", displayName: "Sam Okafor",
            roles: [], emailVerified: false, createdAt: Date(timeIntervalSinceNow: -86_400 * 5),
            updatedAt: Date(), authMethods: [AuthMethod(method: "oidc", provider: "Google")]
        )
    ]
}

extension UserVolume {
    public static func previewVolumes(userID: String) -> [UserVolume] {
        [
            UserVolume(id: "v1", userId: userID, label: "Projects", path: "/srv/volumes/projects", accessMode: .readwrite, createdAt: Date(), updatedAt: Date()),
            UserVolume(id: "v2", userId: userID, label: "Archive", path: "/srv/volumes/archive", accessMode: .readonly, createdAt: Date(), updatedAt: Date())
        ]
    }
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
            downloadCount: 0, lastAccessedAt: nil,
            permittedUserIds: ["u2", "u3"], createdAt: Date(), updatedAt: Date()
        ),
        Share(
            id: "s4", shareToken: "eXp1r3dTok", ownerId: "preview-user",
            sourcePath: "Old/invoice.pdf", isDirectory: false,
            accessMode: .readonly, sharingType: .anyone, hasPassword: false,
            expiresAt: Date().addingTimeInterval(-86_400), label: "invoice.pdf",
            downloadCount: 12, lastAccessedAt: nil, createdAt: Date(), updatedAt: Date()
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
