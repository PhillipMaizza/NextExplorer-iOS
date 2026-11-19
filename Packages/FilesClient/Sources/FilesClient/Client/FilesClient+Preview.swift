import CoreModels
import Foundation
import NetworkClient

public extension FilesClient {
    static let previewValue = FilesClient(
        browse: { _, path in
            BrowseResult(
                items: FileItem.previewItems,
                access: FileAccess(
                    canRead: true,
                    canWrite: true,
                    canUpload: true,
                    canDelete: true,
                    canShare: true,
                    canDownload: true
                ),
                path: path
            )
        },
        prefetchDirectory: { _, _ in },
        search: { _, _, _, _ in [] },
        favorites: { _ in Favorite.previewFavorites },
        addFavorite: { _, path in
            Favorite(
                id: UUID().uuidString,
                path: path,
                label: nil,
                icon: "star",
                color: nil,
                position: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        },
        removeFavorite: { _, _ in },
        updateFavorite: { _, id, label, icon, color in
            Favorite(
                id: id,
                path: "Documents",
                label: label,
                icon: icon,
                color: color,
                position: 0,
                createdAt: Date(),
                updatedAt: Date()
            )
        },
        reorderFavorites: { _, orderedIDs in
            orderedIDs.enumerated().map { index, id in
                Favorite(
                    id: id,
                    path: id,
                    label: id,
                    icon: "StarIcon",
                    color: nil,
                    position: index,
                    createdAt: Date(),
                    updatedAt: Date()
                )
            }
        },
        volumes: { _ in Volume.previewVolumes },
        fetchPreferences: { _ in UserPreferences() },
        updatePreference: { _, _, _ in },
        fetchBranding: { _ in Branding(appName: "Rivendell Cloud", appLogoUrl: "/static/logos/custom-logo.png") },
        updateBranding: { _, appName, appLogoUrl in Branding(appName: appName, appLogoUrl: appLogoUrl) },
        uploadServerLogo: { _, _ in "/static/logos/custom-logo.png" },
        renameItem: { _, item, newName in
            FileItem(
                name: newName,
                path: item.path,
                dateModified: item.dateModified,
                size: item.size,
                kind: item.kind,
                supportsThumbnail: item.supportsThumbnail
            )
        },
        createFolder: { _, path, name in
            FileItem(
                name: name.isEmpty ? "Untitled Folder" : name,
                path: path,
                dateModified: Date(),
                size: 0,
                kind: "directory"
            )
        },
        createFile: { _, path, name in
            FileItem(
                name: name.isEmpty ? "Untitled.txt" : name,
                path: path,
                dateModified: Date(),
                size: 0,
                kind: (name as NSString).pathExtension.lowercased()
            )
        },
        deleteImpact: { _, _ in DeleteImpact(shareCount: 0) },
        deleteItems: { _, _, _, _ in DeleteOutcome() },
        transferItems: { _, items, destination, _, _ in previewTransfer(items, destination) },
        recentDestinations: { _ in ["Documents/Projects", "Media/Photos"] },
        folderSizes: { _, paths in
            Dictionary(uniqueKeysWithValues: paths.map { ($0, FolderSize(sizeBytes: 48_000_000, indexed: true)) })
        },
        refreshFolderSize: { _, _ in FolderSize(sizeBytes: 48_000_000, indexed: true) },
        fetchMetadata: { _, path in
            FileMetadata(
                path: path,
                name: (path as NSString).lastPathComponent,
                kind: "directory",
                size: 4_096,
                dateModified: Date(),
                dateCreated: Date(),
                directory: FileMetadata.DirectorySummary(
                    totalSize: 10_485_760,
                    fileCount: 42,
                    dirCount: 3,
                    truncated: false
                )
            )
        },
        fetchUsage: { _, path in
            path == "home"
                ? StorageUsage(path: path, size: 188_000_000_000, free: 12_000_000_000, total: 200_000_000_000)
                : StorageUsage(path: path, size: 42_000_000_000, free: 58_000_000_000, total: 100_000_000_000)
        },
        fetchCapabilities: { _ in
            [
                ServerCapability(name: "ffmpeg", isAvailable: true, version: "7.1", installPackage: "ffmpeg"),
                ServerCapability(name: "ripgrep", isAvailable: false, installPackage: "ripgrep"),
                ServerCapability(name: "rsync", isAvailable: false, isUsed: false, installPackage: "rsync"),
                ServerCapability(
                    name: "7-Zip", isAvailable: true, version: "24.08", installPackage: "7zip", missingFormats: ["rar"]
                ),
            ]
        },
        fetchPermissions: { _, path in
            FilePermissions(
                path: path,
                mode: 0o100_644,
                owner: "phillip",
                group: "staff",
                uid: 501,
                gid: 20,
                isDirectory: false
            )
        },
        changePermissions: { _, _, _, _ in },
        changeOwnership: { _, _, _, _ in },
        fetchVersions: { _, _ in
            let hour: TimeInterval = 3600
            return FileVersionHistory(
                isEnabled: true,
                versions: [
                    FileVersion(
                        id: "v2",
                        size: 18_400,
                        modifiedAt: Date().addingTimeInterval(-hour * 3),
                        capturedAt: Date().addingTimeInterval(-hour * 2),
                        author: .init(label: "phillip")
                    ),
                    FileVersion(
                        id: "v1",
                        size: 16_100,
                        modifiedAt: Date().addingTimeInterval(-hour * 50),
                        capturedAt: Date().addingTimeInterval(-hour * 49),
                        author: .init(label: "phillip"),
                        label: "Before edits",
                        isPinned: true
                    ),
                ],
                totalBytes: 34_500,
                rights: .init(canSee: true, canDownload: true, canRestore: true, canRemove: true)
            )
        },
        restoreVersion: { _, _, _ in },
        versionText: { _, _, _ in
            FileVersionText(name: "notes.txt", size: 12, modifiedAt: Date(), content: "Hello, world")
        },
        downloadVersion: { _, _, _, _ in },
        copyVersion: { _, path, _, _ in path },
        replaceWithVersion: { _, _, _, _ in },
        updateVersion: { _, _, versionID, label, pinned in
            FileVersion(
                id: versionID,
                size: 0,
                modifiedAt: Date(),
                capturedAt: Date(),
                label: label,
                isPinned: pinned ?? false
            )
        },
        deleteVersions: { _, _, _, _ in },
        thumbnailURL: { _, _ in nil },
        previewFile: { _, item in
            emptyStandIn(named: item.name, in: "Previews-Preview")
        },
        previewFileLowPriority: { _, item in
            emptyStandIn(named: item.name, in: "Previews-Preview")
        },
        fetchTextContent: { _, _ in "" },
        saveTextContent: { _, _, _ in },
        extractZip: { _, item in
            FileItem(
                name: item.name.replacingOccurrences(of: ".zip", with: ""),
                path: item.path,
                dateModified: Date(),
                size: 0,
                kind: "directory"
            )
        },
        downloadRawFile: { _, item in
            emptyStandIn(named: item.name, in: "Downloads-Preview")
        },
        downloadRawFileLowPriority: { _, item in
            emptyStandIn(named: item.name, in: "Downloads-Preview")
        },
        offlineDownloadFile: { _, item, onProgress in
            let fileURL = emptyStandIn(named: item.name, in: "Offline-Preview")
            onProgress(1)
            return fileURL
        },
        downloadItem: { _, _, onProgress in
            let fileURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try? Data().write(to: fileURL)
            onProgress(TransferProgress(receivedBytes: 1, expectedBytes: 1))
            return fileURL
        },
        flushDownloadConnections: {},
        uploadFile: { _, _, _, _, onProgress in onProgress(1) },
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
        updateShareLink: { _, shareID, request in
            let base = Share.previewSharedByMe.first { $0.id == shareID } ?? Share.previewSharedByMe[0]
            return base.applying(request, at: Date())
        },
        deleteShareLink: { _, _ in },
        shareableUsers: { _ in Share.previewShareableUsers },
        resolveShareLink: { _, token in
            ShareInfo(shareToken: token, label: "Q3 Report", isDirectory: true, sharingType: .anyone)
        },
        changeOwnPassword: { _, _, _ in },
        addOwnPassword: { _, _ in },
        fetchAuthMethods: { _ in [SignInMethod(
            id: "preview-password",
            type: SignInMethod.localPasswordType,
            provider: "Password"
        )] },
        fetchAuthStatus: { _ in AuthStatus(localEnabled: true, oidcEnabled: false) },
        fetchTwoFactorStatus: { _ in TwoFactorStatus(isEnabled: false) },
        beginTwoFactorSetup: { _ in
            TwoFactorSetup(
                secret: "JBSWY3DPEHPK3PXP",
                uri: "otpauth://totp/NextExplorer:preview?secret=JBSWY3DPEHPK3PXP&issuer=NextExplorer"
            )
        },
        confirmTwoFactorSetup: { _, _ in ["AAAAA-BBBBB", "CCCCC-DDDDD"] },
        replaceRecoveryCodes: { _, _ in ["EEEEE-FFFFF", "GGGGG-HHHHH"] },
        disableTwoFactor: { _, _ in },
        fetchAPITokens: { _ in [] },
        createAPIToken: { _, name, scope, _, _ in
            IssuedAPIToken(
                token: APIToken(id: "preview", name: name, scope: scope, createdAt: "2026-11-10T07:00:00.000Z"),
                secret: "nx_preview_0123456789abcdef"
            )
        },
        renameAPIToken: { _, id, name in APIToken(
            id: id,
            name: name,
            scope: .read,
            createdAt: "2026-11-10T07:00:00.000Z"
        ) },
        revokeAPIToken: { _, _ in },
        serverFeatures: { _ in ServerFeatures(isUserVolumesEnabled: true, isVolumeUsageEnabled: true) },
        fetchSystemSettings: { _ in
            SystemSettings(
                thumbnails: ThumbnailSettings(),
                accessRules: [
                    AccessRule(id: "r1", path: "Documents/Reports", isRecursive: true, permission: .readOnly),
                    AccessRule(id: "r2", path: "Private", isRecursive: false, permission: .hidden),
                ]
            )
        },
        updateThumbnailSettings: { _, settings in settings },
        fetchActivity: { _, _, _ in ActivityPage(isEnabled: true) },
        clearActivity: { _ in },
        fetchVersionedFiles: { _, _, _, _ in VersionedFilesPage() },
        fetchVersionedFile: { _, _ in VersionedFileDetail() },
        deleteVersionsOfFile: { _, _, _ in VersionsDeletion() },
        fetchTrashZones: { _ in [] },
        verifyTrash: { _ in [] },
        runTrashMaintenance: { _ in },
        fetchTrash: { _ in TrashListing(isEnabled: true, retentionDays: 30, items: []) },
        fetchTrashEntries: { _, itemID, path in
            TrashFolderListing(item: TrashItem(id: itemID, name: itemID, isDirectory: true), path: path, entries: [])
        },
        fetchTrashText: { _, itemID, _ in TrashText(name: itemID, content: "") },
        restoreTrash: { _, _, _, _, _ in TrashActionResult(items: []) },
        purgeTrash: { _, _, _ in TrashActionResult(items: []) },
        emptyTrash: { _ in TrashEmptySummary(purged: 0) },
        updateSystemSettings: { _, _ in SystemSettings() },
        updateAccessRules: { _, rules in rules },
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
        resetUserSecurity: { _, _, _ in },
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
                    AdminDirectory(name: "backups", path: base + "/backups"),
                ]
            )
        }
    )
}

public extension User {
    static let previewManagedUsers: [User] = [
        User(
            id: "u1", username: "admin", email: "admin@example.com", displayName: "Site Admin",
            roles: ["admin"], emailVerified: true, createdAt: Date(timeIntervalSinceNow: -86_400 * 90),
            updatedAt: Date(), authMethods: [AuthMethod(method: "local_password")]
        ),
        User(
            id: "u2", username: "jamie", email: "jamie@example.com", displayName: "Jamie Rivera",
            roles: [], emailVerified: true, createdAt: Date(timeIntervalSinceNow: -86_400 * 30),
            updatedAt: Date(), authMethods: [
                AuthMethod(method: "local_password"),
                AuthMethod(method: "oidc", provider: "Authentik"),
            ]
        ),
        User(
            id: "u3", username: "sam", email: "sam@example.com", displayName: "Sam Okafor",
            roles: [], emailVerified: false, createdAt: Date(timeIntervalSinceNow: -86_400 * 5),
            updatedAt: Date(), authMethods: [AuthMethod(method: "oidc", provider: "Google")]
        ),
    ]
}

public extension UserVolume {
    static func previewVolumes(userID: String) -> [UserVolume] {
        [
            UserVolume(
                id: "v1",
                userId: userID,
                label: "Projects",
                path: "/srv/volumes/projects",
                accessMode: .readwrite,
                createdAt: Date(),
                updatedAt: Date()
            ),
            UserVolume(
                id: "v2",
                userId: userID,
                label: "Archive",
                path: "/srv/volumes/archive",
                accessMode: .readonly,
                createdAt: Date(),
                updatedAt: Date()
            ),
        ]
    }
}

public extension Share {
    /// Mock Shared tab: folders and files, public links and people shares, two shares on one
    /// item, read and write, passwords, countdowns, expired links and an unresolved recipient.
    static var previewSharedByMe: [Share] {
        let now = Date()
        func make(
            _ id: String,
            _ path: String,
            folder: Bool = false,
            users: [String]? = nil,
            readWrite: Bool = false,
            password: Bool = false,
            days: Double? = nil,
            ageDays: Double = 0,
            label: String? = nil,
            downloads: Int? = nil,
            openedHoursAgo: Double? = nil
        ) -> Share {
            Share(
                id: id, shareToken: "tok\(id)", ownerId: "preview-user",
                sourcePath: path, sourceSpace: "personal", isDirectory: folder,
                accessMode: readWrite ? .readwrite : .readonly,
                sharingType: users == nil ? .anyone : .users, hasPassword: password,
                expiresAt: days.map { now.addingTimeInterval($0 * 86_400) }, label: label,
                downloadCount: downloads ?? id.count * 3,
                lastAccessedAt: openedHoursAgo.map { now.addingTimeInterval(-$0 * 3600) },
                permittedUserIds: users,
                createdAt: now.addingTimeInterval(-ageDays * 86_400), updatedAt: now
            )
        }
        return [
            make("s1", "Documents/Bills/Electricity", folder: true, ageDays: 1, downloads: 3, openedHoursAgo: 0.5),
            make(
                "s5",
                "Work/Team Roadmap",
                folder: true,
                users: ["u4", "u5", "u6", "u2", "u3"],
                readWrite: true,
                ageDays: 2,
                label: "Q1 planning",
                downloads: 27,
                openedHoursAgo: 0.2
            ),
            make(
                "s6",
                "Work/Team Roadmap",
                folder: true,
                password: true,
                days: 12,
                ageDays: 3,
                label: "Board preview",
                downloads: 0
            ),
            make(
                "s7",
                "Photos/2026/Vacation Photos",
                folder: true,
                days: 2.5,
                ageDays: 4,
                label: "Family trip",
                downloads: 14,
                openedHoursAgo: 2
            ),
            make("s16", "Photos/2026/Vacation Photos", folder: true, users: ["u2", "u7"], ageDays: 3.5, downloads: 2),
            make("s8", "Finance/Budget 2027.xlsx", readWrite: true, password: true, ageDays: 5, openedHoursAgo: 30),
            make(
                "s9",
                "Legal/Contracts/Contract draft.pdf",
                users: ["u6"],
                days: 1.5,
                ageDays: 6,
                label: "For signature"
            ),
            make(
                "s14",
                "Clients/Northwind Traders International/Proposals and Contracts/2027/Quarterly financial statements and board presentation final v3.pdf",
                users: ["u8", "u2", "u4", "u5", "u6", "u7"],
                readWrite: true,
                password: true,
                days: 4.5,
                ageDays: 6,
                label: "Board pack for the quarterly review with the whole leadership team"
            ),
            make(
                "s15",
                "Clients/Northwind Traders International/Proposals and Contracts/2027/Quarterly financial statements and board presentation final v3.pdf",
                password: true,
                days: -1,
                ageDays: 7
            ),
            make("s2", "Photos/2024/passport.pdf", users: ["u2", "u3"], password: true, days: 6.5, ageDays: 7),
            make("s10", "Work/Meeting notes.md", users: ["u7", "u99"], ageDays: 8, label: "Weekly sync"),
            make("s11", "Design/Brand/Keynote deck.key", users: ["u4"], days: 30, ageDays: 9),
            make("s12", "Invoice Oct.pdf", ageDays: 10, downloads: 1_284, openedHoursAgo: 120),
            make("s13", "Design/Brand/Logo final.png", days: -2, ageDays: 11, downloads: 41, openedHoursAgo: 460),
            make("s4", "Old/invoice.pdf", days: -1, ageDays: 12),
            make(
                "s17",
                "Finance/Rent receipts",
                folder: true,
                users: ["u4"],
                readWrite: true,
                ageDays: 9,
                label: "Landlord",
                downloads: 5,
                openedHoursAgo: 300
            ),
            make(
                "s18",
                "Finance/Rent receipts",
                folder: true,
                password: true,
                days: 0.3,
                ageDays: 8.5,
                label: "Accountant",
                downloads: 2,
                openedHoursAgo: 5
            ),
            make(
                "s19",
                "Finance/Rent receipts",
                folder: true,
                days: -4,
                ageDays: 20,
                label: "Tax 2025",
                downloads: 11,
                openedHoursAgo: 900
            ),
            make(
                "s20",
                "Archive/Old drafts",
                folder: true,
                days: -10,
                ageDays: 30,
                label: "Review round 1",
                downloads: 8
            ),
            make("s21", "Archive/Old drafts", folder: true, users: ["u3", "u5"], days: -5, ageDays: 25),
            make(
                "s22",
                "Company/Handbook.pdf",
                users: ["u2", "u3", "u4", "u5", "u6", "u7", "u8", "u9", "u10", "u11", "u12", "u13", "u98", "u99"],
                ageDays: 14,
                label: "All staff",
                downloads: 312,
                openedHoursAgo: 1
            ),
            make("s23", "Projects/Secret plan.key", users: ["u97"], days: 20, ageDays: 13.5),
            make(
                "s24",
                "Uploads/Drop box",
                folder: true,
                readWrite: true,
                password: true,
                days: 45,
                ageDays: 13,
                label: "Client uploads",
                downloads: 0
            ),
        ]
    }

    static var previewSharedWithMe: [Share] {
        let now = Date()
        func make(
            _ id: String,
            _ name: String,
            owner: String,
            folder: Bool = false,
            readWrite: Bool = false,
            password: Bool = false,
            days: Double? = nil,
            ageDays: Double = 0,
            label: String? = nil
        ) -> Share {
            Share(
                id: id, shareToken: "tok\(id)", ownerId: owner, sourceName: name, isDirectory: folder,
                accessMode: readWrite ? .readwrite : .readonly, sharingType: .users, hasPassword: password,
                expiresAt: days.map { now.addingTimeInterval($0 * 86_400) }, label: label, downloadCount: 0,
                lastAccessedAt: nil, createdAt: now.addingTimeInterval(-ageDays * 86_400), updatedAt: now
            )
        }
        return [
            make("s3", "Team Roadmap", owner: "u4", folder: true, readWrite: true, ageDays: 1, label: "Q1 planning"),
            make("w2", "Q3 Report.pdf", owner: "u5", days: 0.5, ageDays: 2),
            make("w3", "Recipes", owner: "u7", folder: true, ageDays: 3),
            make(
                "w4",
                "Floor plan.png",
                owner: "u4",
                password: true,
                days: 5.5,
                ageDays: 4,
                label: "Numbers for review"
            ),
            make("w5", "Mixtape.mp3", owner: "someone-else", ageDays: 5),
            make("w6", "Holiday plan.docx", owner: "u5", readWrite: true, days: -3, ageDays: 6),
            make(
                "w7",
                "Architecture review notes for the platform migration program and rollout plan.docx",
                owner: "u8",
                readWrite: true,
                days: 2.5,
                ageDays: 7
            ),
            make("w8", "Sprint board", owner: "u5", folder: true, readWrite: true, days: 0.2, ageDays: 8),
            make("w9", "Wedding Photos", owner: "u6", folder: true, password: true, days: 40, ageDays: 9),
            make("w10", "Tax return 2025.pdf", owner: "u2", days: -12, ageDays: 20, label: "For review"),
        ]
    }

    static let previewShareableUsers: [User] = [
        User(id: "u2", username: "jamie", email: "jamie@example.com", displayName: "Jamie Rivera"),
        User(id: "u3", username: "sam", email: "sam@example.com", displayName: "Sam Okafor"),
        User(id: "u4", username: "anna", email: "anna@example.com", displayName: "Anna Moreau"),
        User(id: "u5", username: "jonas", email: "jonas@example.com", displayName: "Jonas Keller"),
        User(id: "u6", username: "lea", email: "lea@example.com", displayName: "Lea Sato"),
        User(id: "u7", username: "mia", email: "mia@example.com", displayName: "Mia Rossi"),
        User(
            id: "u8",
            username: "max",
            email: "max@example.com",
            displayName: "Maximilianus Bartholomew von Hohenberg"
        ),
        User(id: "u9", username: "noah", email: "noah@example.com", displayName: "Noah Fischer"),
        User(id: "u10", username: "emma", email: "emma@example.com", displayName: "Emma Laurent"),
        User(id: "u11", username: "liam", email: "liam@example.com", displayName: "Liam Walsh"),
        User(id: "u12", username: "sofia", email: "sofia@example.com", displayName: "Sofia Marino"),
        User(id: "u13", username: "kenji", email: "kenji@example.com", displayName: "Kenji Tanaka"),
    ]
}

extension FileItem {
    static let previewItems: [FileItem] = [
        FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory"),
        FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory"),
        FileItem(
            name: "vacation.jpg",
            path: "",
            dateModified: Date(),
            size: 2_400_000,
            kind: "jpg",
            supportsThumbnail: true
        ),
        FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 1_024, kind: "txt"),
    ]
}

extension Favorite {
    static let previewFavorites: [Favorite] = [
        Favorite(
            id: "1",
            path: "Documents",
            label: "Documents",
            icon: "folder",
            color: nil,
            position: 0,
            createdAt: Date(),
            updatedAt: Date()
        ),
    ]
}

extension Volume {
    static let previewVolumes: [Volume] = [
        Volume(name: "media", path: "media"),
        Volume(name: "home", path: "home"),
    ]
}

private func previewTransfer(_ items: [FileItem], _ destination: String) -> TransferResult {
    TransferResult(
        destination: destination,
        items: items.map { TransferResult.Entry(from: $0.id, to: "\(destination)/\($0.name)") }
    )
}

/// An empty file named `name` in the temporary folder `folder`, standing in for a download.
private func emptyStandIn(named name: String, in folder: String) -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(folder, isDirectory: true)
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let fileURL = directory.appendingPathComponent(name)
    try? Data().write(to: fileURL)
    return fileURL
}

public extension Share {
    /// This share as the server returns it after `PUT /api/shares/:id`, for the mock services.
    func applying(_ request: UpdateShareRequest, at date: Date) -> Share {
        let hasPassword: Bool = switch request.password {
        case .keep: self.hasPassword
        case .remove: false
        case .set: true
        }
        return Share(
            id: id, shareToken: shareToken, ownerId: ownerId,
            sourcePath: sourcePath, sourceSpace: sourceSpace, sourceName: sourceName, isDirectory: isDirectory,
            accessMode: request.accessMode, sharingType: request.target, hasPassword: hasPassword,
            expiresAt: request.expiresAt, label: request.label,
            downloadCount: downloadCount, lastAccessedAt: lastAccessedAt,
            permittedUserIds: request.target == .users ? request.userIds : nil,
            createdAt: createdAt, updatedAt: date
        )
    }
}
