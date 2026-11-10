import CoreModels
import Dependencies
import Foundation
import NetworkClient

public extension FilesClient {
    static func live(
        networkClient: NetworkClient,
        directoryCacheStore: DirectoryCacheStore = .liveValue,
        textEditorETags: TextEditorETagStore = TextEditorETagStore(),
        now: @escaping @Sendable () -> Date = { Date() },
        activeScope: @escaping @Sendable () -> String = { CacheAccountScope.current }
    ) -> FilesClient {
        let service = FilesService(networkClient: networkClient, textEditorETags: textEditorETags, activeScope: activeScope)

        @Sendable func resolveBrowse(serverURL: URL, path: String, isLowPriority: Bool) async throws -> BrowseResult {
            // Pinned at request start so a late response lands in the account that asked for it,
            // even if the active account switched while it was in flight.
            let directoryCacheStore = directoryCacheStore.bound(to: activeScope())
            do {
                return try await resolveDirectory(
                    serverURL: serverURL, path: path, isLowPriority: isLowPriority, cache: directoryCacheStore
                )
            } catch FilesClientError.server(statusCode: 404) where path.isEmpty {
                // USER_VOLUMES refuses a non admin the root itself; the volumes list is the root then.
                let result = try await service.volumeRoot(serverURL: serverURL)
                directoryCacheStore.write(serverURL: serverURL, path: path, result: result, etag: nil, fetchedAt: now())
                return result
            }
        }

        @Sendable func resolveDirectory(
            serverURL: URL, path: String, isLowPriority: Bool, cache directoryCacheStore: DirectoryCacheStore
        ) async throws -> BrowseResult {
            let cached = directoryCacheStore.read(serverURL: serverURL, path: path)
            let outcome = try await service.browse(
                serverURL: serverURL, path: path, ifNoneMatch: cached?.etag, isLowPriority: isLowPriority
            )
            switch outcome {
            case let .modified(result, etag):
                directoryCacheStore.write(
                    serverURL: serverURL, path: path, result: result, etag: etag, fetchedAt: now()
                )
                return result
            case .notModified:
                guard let cached else {
                    // A 304 with no cached copy: the entry was evicted or cleared between the
                    // read and the response. Re fetch unconditionally.
                    let retry = try await service.browse(
                        serverURL: serverURL, path: path, ifNoneMatch: nil, isLowPriority: isLowPriority
                    )
                    guard case let .modified(result, retryETag) = retry else {
                        throw FilesClientError.decoding("Unexpected 304 for an unconditional browse request.")
                    }
                    directoryCacheStore.write(
                        serverURL: serverURL, path: path, result: result, etag: retryETag, fetchedAt: now()
                    )
                    return result
                }
                // A 304 confirms the copy we conditioned on is current. Only refresh its
                // freshness stamp, and only if the stored etag still matches ours, so a stale
                // prefetch response can't overwrite a newer listing a concurrent browse wrote.
                directoryCacheStore.touch(
                    serverURL: serverURL, path: path, expectedETag: cached.etag, fetchedAt: now()
                )
                return BrowseResult(items: cached.items, access: cached.access, path: cached.path)
            }
        }

        return FilesClient(
            browse: { serverURL, path in
                try await resolveBrowse(serverURL: serverURL, path: path, isLowPriority: false)
            },
            prefetchDirectory: { serverURL, path in
                _ = try? await resolveBrowse(serverURL: serverURL, path: path, isLowPriority: true)
            },
            search: { serverURL, path, query, limit in
                try await service.search(serverURL: serverURL, path: path, query: query, limit: limit)
            },
            favorites: { serverURL in
                try await service.favorites(serverURL: serverURL)
            },
            addFavorite: { serverURL, path in
                try await service.addFavorite(serverURL: serverURL, path: path)
            },
            removeFavorite: { serverURL, path in
                try await service.removeFavorite(serverURL: serverURL, path: path)
            },
            updateFavorite: { serverURL, id, label, icon, color in
                try await service.updateFavorite(serverURL: serverURL, id: id, label: label, icon: icon, color: color)
            },
            reorderFavorites: { serverURL, orderedIDs in
                try await service.reorderFavorites(serverURL: serverURL, orderedIDs: orderedIDs)
            },
            volumes: { serverURL in
                try await service.volumes(serverURL: serverURL)
            },
            fetchPreferences: { serverURL in
                try await service.fetchPreferences(serverURL: serverURL)
            },
            updatePreference: { serverURL, key, value in
                try await service.updatePreference(serverURL: serverURL, key: key, value: value)
            },
            fetchBranding: { serverURL in
                try await service.fetchBranding(serverURL: serverURL)
            },
            updateBranding: { serverURL, appName, appLogoUrl in
                try await service.updateBranding(serverURL: serverURL, appName: appName, appLogoUrl: appLogoUrl)
            },
            uploadServerLogo: { serverURL, jpegData in
                try await service.uploadServerLogo(serverURL: serverURL, jpegData: jpegData)
            },
            renameItem: { serverURL, item, newName in
                try await service.renameItem(serverURL: serverURL, item: item, newName: newName)
            },
            createFolder: { serverURL, path, name in
                try await service.createFolder(serverURL: serverURL, path: path, name: name)
            },
            createFile: { serverURL, path, name in
                try await service.createFile(serverURL: serverURL, path: path, name: name)
            },
            deleteImpact: { serverURL, items in
                try await service.deleteImpact(serverURL: serverURL, items: items)
            },
            deleteItems: { serverURL, items in
                try await service.deleteItems(serverURL: serverURL, items: items)
            },
            transferItems: { serverURL, items, destination, operation in
                try await service.transferItems(
                    serverURL: serverURL, items: items, destination: destination, operation: operation
                )
            },
            fetchMetadata: { serverURL, path in
                try await service.fetchMetadata(serverURL: serverURL, path: path)
            },
            fetchUsage: { serverURL, path in
                try await service.fetchUsage(serverURL: serverURL, path: path)
            },
            fetchPermissions: { serverURL, path in
                try await service.fetchPermissions(serverURL: serverURL, path: path)
            },
            changePermissions: { serverURL, path, mode, recursive in
                try await service.changePermissions(serverURL: serverURL, path: path, mode: mode, recursive: recursive)
            },
            changeOwnership: { serverURL, path, owner, group in
                try await service.changeOwnership(serverURL: serverURL, path: path, owner: owner, group: group)
            },
            fetchVersions: { serverURL, path in
                try await service.fetchVersions(serverURL: serverURL, path: path)
            },
            restoreVersion: { serverURL, path, versionID in
                try await service.restoreVersion(serverURL: serverURL, path: path, versionID: versionID)
            },
            downloadVersion: { serverURL, path, versionID, destination in
                try await service.downloadVersion(serverURL: serverURL, path: path, versionID: versionID, to: destination)
            },
            copyVersion: { serverURL, path, versionID, destination in
                try await service.copyVersion(serverURL: serverURL, path: path, versionID: versionID, destination: destination)
            },
            updateVersion: { serverURL, path, versionID, label, pinned in
                try await service.updateVersion(serverURL: serverURL, path: path, versionID: versionID, label: label, pinned: pinned)
            },
            deleteVersions: { serverURL, path, ids, all in
                try await service.deleteVersions(serverURL: serverURL, path: path, ids: ids, all: all)
            },
            thumbnailURL: { serverURL, path in
                try await service.thumbnailURL(serverURL: serverURL, path: path)
            },
            previewFile: { serverURL, item in
                try await service.previewFile(serverURL: serverURL, item: item)
            },
            previewFileLowPriority: { serverURL, item in
                try await service.previewFileLowPriority(serverURL: serverURL, item: item)
            },
            fetchTextContent: { serverURL, path in
                try await service.fetchTextContent(serverURL: serverURL, path: path)
            },
            saveTextContent: { serverURL, path, content in
                try await service.saveTextContent(serverURL: serverURL, path: path, content: content)
            },
            extractZip: { serverURL, item in
                try await service.extractZip(serverURL: serverURL, item: item)
            },
            downloadRawFile: { serverURL, item in
                try await service.downloadRawFile(serverURL: serverURL, item: item)
            },
            offlineDownloadFile: { serverURL, item, onProgress in
                try await service.offlineDownloadFile(
                    serverURL: serverURL, item: item, onProgress: onProgress
                )
            },
            downloadItem: { serverURL, item, onProgress in
                try await service.downloadItem(serverURL: serverURL, item: item, onProgress: onProgress)
            },
            flushDownloadConnections: { await networkClient.flushDownloadConnections() },
            uploadFile: { serverURL, fileURL, fileName, destination, onProgress in
                try await service.uploadFile(
                    serverURL: serverURL, fileURL: fileURL, fileName: fileName,
                    destination: destination, onProgress: onProgress
                )
            },
            compressItem: { serverURL, item in
                try await service.compressItem(serverURL: serverURL, item: item)
            },
            createShareLink: { serverURL, request in
                try await service.createShareLink(serverURL: serverURL, request: request)
            },
            mySharedLinks: { serverURL in
                try await service.shareLinks(serverURL: serverURL, sharedWithMe: false)
            },
            sharedWithMeLinks: { serverURL in
                try await service.shareLinks(serverURL: serverURL, sharedWithMe: true)
            },
            updateShareLink: { serverURL, shareID, request in
                try await service.updateShareLink(serverURL: serverURL, shareID: shareID, request: request)
            },
            deleteShareLink: { serverURL, shareID in
                try await service.deleteShareLink(serverURL: serverURL, shareID: shareID)
            },
            shareableUsers: { serverURL in
                try await service.shareableUsers(serverURL: serverURL)
            },
            resolveShareLink: { serverURL, token in
                try await service.resolveShareLink(serverURL: serverURL, token: token)
            },
            changeOwnPassword: { serverURL, currentPassword, newPassword in
                try await service.changeOwnPassword(
                    serverURL: serverURL, currentPassword: currentPassword, newPassword: newPassword
                )
            },
            addOwnPassword: { serverURL, password in
                try await service.addOwnPassword(serverURL: serverURL, password: password)
            },
            fetchAuthMethods: { serverURL in
                try await service.authMethods(serverURL: serverURL)
            },
            fetchTwoFactorStatus: { serverURL in
                try await service.twoFactorStatus(serverURL: serverURL)
            },
            beginTwoFactorSetup: { serverURL in
                try await service.beginTwoFactorSetup(serverURL: serverURL)
            },
            confirmTwoFactorSetup: { serverURL, code in
                try await service.confirmTwoFactorSetup(serverURL: serverURL, code: code)
            },
            replaceRecoveryCodes: { serverURL, password in
                try await service.replaceRecoveryCodes(serverURL: serverURL, password: password)
            },
            disableTwoFactor: { serverURL, password in
                try await service.disableTwoFactor(serverURL: serverURL, password: password)
            },
            fetchAPITokens: { serverURL in
                try await service.apiTokens(serverURL: serverURL)
            },
            createAPIToken: { serverURL, name, scope, expiresInDays, password in
                try await service.createAPIToken(serverURL: serverURL, name: name, scope: scope, expiresInDays: expiresInDays, password: password)
            },
            renameAPIToken: { serverURL, id, name in
                try await service.renameAPIToken(serverURL: serverURL, id: id, name: name)
            },
            revokeAPIToken: { serverURL, id in
                try await service.revokeAPIToken(serverURL: serverURL, id: id)
            },
            serverFeatures: { serverURL in
                try await service.serverFeatures(serverURL: serverURL)
            },
            fetchSystemSettings: { serverURL in
                try await service.fetchSystemSettings(serverURL: serverURL)
            },
            updateThumbnailSettings: { serverURL, settings in
                try await service.updateThumbnailSettings(serverURL: serverURL, settings: settings)
            },
            updateAccessRules: { serverURL, rules in
                try await service.updateAccessRules(serverURL: serverURL, rules: rules)
            },
            listUsers: { serverURL in
                try await service.listUsers(serverURL: serverURL)
            },
            createUser: { serverURL, request in
                try await service.createUser(serverURL: serverURL, request: request)
            },
            updateUser: { serverURL, userID, request in
                try await service.updateUser(serverURL: serverURL, userID: userID, request: request)
            },
            setUserPassword: { serverURL, userID, newPassword in
                try await service.setUserPassword(serverURL: serverURL, userID: userID, newPassword: newPassword)
            },
            deleteUser: { serverURL, userID in
                try await service.deleteUser(serverURL: serverURL, userID: userID)
            },
            userVolumes: { serverURL, userID in
                try await service.userVolumes(serverURL: serverURL, userID: userID)
            },
            addUserVolume: { serverURL, userID, request in
                try await service.addUserVolume(serverURL: serverURL, userID: userID, request: request)
            },
            updateUserVolume: { serverURL, userID, volumeID, label, accessMode in
                try await service.updateUserVolume(
                    serverURL: serverURL, userID: userID, volumeID: volumeID, label: label, accessMode: accessMode
                )
            },
            removeUserVolume: { serverURL, userID, volumeID in
                try await service.removeUserVolume(serverURL: serverURL, userID: userID, volumeID: volumeID)
            },
            browseAdminDirectories: { serverURL, path in
                try await service.browseAdminDirectories(serverURL: serverURL, path: path)
            }
        )
    }
}

extension FilesClient: DependencyKey {
    public static var liveValue: FilesClient {
        @Dependency(\.networkClient) var networkClient
        @Dependency(\.directoryCacheStore) var directoryCacheStore
        @Dependency(\.textEditorETagStore) var textEditorETags
        return .live(networkClient: networkClient, directoryCacheStore: directoryCacheStore, textEditorETags: textEditorETags)
    }
}

public extension DependencyValues {
    var filesClient: FilesClient {
        get { self[FilesClient.self] }
        set { self[FilesClient.self] = newValue }
    }
}
