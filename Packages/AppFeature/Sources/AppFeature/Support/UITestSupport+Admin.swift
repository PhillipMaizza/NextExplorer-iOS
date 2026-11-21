#if DEBUG
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    import Foundation
    import NetworkClient

    extension UITestSupport {
        private typealias Person = UITestFixture.ManagedUser
        private typealias Fixture = UITestFixture

        private enum Age {
            static let hour: TimeInterval = 3600
            static let day: TimeInterval = 86400
        }

        /// What an admin manages, kept in memory for one app launch so each change shows in the next
        /// listing: people (one locked, one with two factor, one single sign on only), their volumes,
        /// the activity log, files with a version history and the access rules.
        static func installAdminMocks(into client: inout FilesClient, now: Date) {
            installUserMocks(into: &client, now: now)
            installActivityMocks(into: &client, now: now)
            installVersionedFileMocks(into: &client, now: now)
            installServerSettingsMocks(into: &client)
        }

        private static func managedUser(_ person: Person, now: Date) -> User {
            let password = AuthMethod(method: Fixture.SignInMethod.password.rawValue)
            let base = (id: person.id, username: person.username, email: person.email, name: person.displayName)
            switch person {
            case .jamie:
                return User(
                    id: base.id,
                    username: base.username,
                    email: base.email,
                    displayName: base.name,
                    isEmailVerified: true,
                    createdAt: now.addingTimeInterval(-30 * Age.day),
                    updatedAt: now,
                    authMethods: [
                        password,
                        AuthMethod(
                            method: Fixture.SignInMethod.oidc.rawValue,
                            provider: Fixture.IdentityProvider.authentik.rawValue
                        ),
                    ]
                )
            case .sam:
                return User(
                    id: base.id,
                    username: base.username,
                    email: base.email,
                    displayName: base.name,
                    createdAt: now.addingTimeInterval(-5 * Age.day),
                    updatedAt: now,
                    authMethods: [AuthMethod(
                        method: Fixture.SignInMethod.oidc.rawValue,
                        provider: Fixture.IdentityProvider.google.rawValue
                    )]
                )
            case .riley:
                return User(
                    id: base.id,
                    username: base.username,
                    email: base.email,
                    displayName: base.name,
                    isEmailVerified: true,
                    createdAt: now.addingTimeInterval(-60 * Age.day),
                    updatedAt: now,
                    authMethods: [password],
                    lockedUntil: now.addingTimeInterval(Age.hour)
                )
            case .morgan:
                return User(
                    id: base.id,
                    username: base.username,
                    email: base.email,
                    displayName: base.name,
                    roles: [UserRole.admin],
                    isEmailVerified: true,
                    createdAt: now.addingTimeInterval(-120 * Age.day),
                    updatedAt: now,
                    authMethods: [password],
                    isTwoFactorEnabled: true
                )
            }
        }

        private static func installUserMocks(into client: inout FilesClient, now: Date) {
            let users = LockIsolated([UITestSupport.user] + Person.allCases.map { managedUser($0, now: now) })
            let nextUser = LockIsolated(1)
            let volumes = LockIsolated([String: [UserVolume]]())
            let nextVolume = LockIsolated(1)
            let notFound = FilesClientError.server(statusCode: HTTPStatus.notFound.rawValue)

            @Sendable func seededVolumes(_ userID: String) -> [UserVolume] {
                Fixture.ManagedVolume.allCases.map { volume in
                    UserVolume(
                        id: "\(userID)-\(volume)",
                        userId: userID,
                        label: volume.rawValue,
                        path: volume.path,
                        accessMode: volume == .archive ? .readonly : .readwrite,
                        createdAt: now,
                        updatedAt: now
                    )
                }
            }

            client.listUsers = { _ in users.value }
            client.createUser = { _, request in
                let id = nextUser.withValue { next in
                    defer { next += 1 }
                    return "user-added-\(next)"
                }
                let user = User(
                    id: id,
                    username: request.username ?? request.email.components(separatedBy: "@").first ?? request.email,
                    email: request.email,
                    displayName: request.displayName,
                    roles: request.isAdmin ? [UserRole.admin] : [],
                    createdAt: now,
                    updatedAt: now,
                    authMethods: [AuthMethod(method: Fixture.SignInMethod.password.rawValue)]
                )
                users.withValue { $0.append(user) }
                return user
            }
            client.updateUser = { _, userID, request in
                try users.withValue { list in
                    guard let index = list.firstIndex(where: { $0.id == userID }) else { throw notFound }
                    let old = list[index]
                    list[index] = User(
                        id: old.id,
                        username: request.username ?? old.username,
                        email: request.email ?? old.email,
                        displayName: request.displayName ?? old.displayName,
                        roles: request.roles ?? old.roles,
                        isEmailVerified: old.isEmailVerified,
                        createdAt: old.createdAt,
                        updatedAt: now,
                        authMethods: old.authMethods,
                        lockedUntil: old.lockedUntil,
                        isTwoFactorEnabled: old.isTwoFactorEnabled
                    )
                    return list[index]
                }
            }
            client.setUserPassword = { _, userID, _ in
                guard users.value.contains(where: { $0.id == userID }) else { throw notFound }
            }
            client.deleteUser = { _, userID in
                users.withValue { $0.removeAll { $0.id == userID } }
                volumes.withValue { $0[userID] = nil }
            }
            client.resetUserSecurity = { _, userID, reset in
                try users.withValue { list in
                    guard let index = list.firstIndex(where: { $0.id == userID }) else { throw notFound }
                    let old = list[index]
                    list[index] = User(
                        id: old.id,
                        username: old.username,
                        email: old.email,
                        displayName: old.displayName,
                        roles: old.roles,
                        isEmailVerified: old.isEmailVerified,
                        createdAt: old.createdAt,
                        updatedAt: now,
                        authMethods: old.authMethods,
                        lockedUntil: reset == .lock ? nil : old.lockedUntil,
                        isTwoFactorEnabled: reset == .twoFactor ? false : old.isTwoFactorEnabled
                    )
                }
            }
            client.userVolumes = { _, userID in
                volumes.withValue { $0[userID, default: seededVolumes(userID)] }
            }
            client.addUserVolume = { _, userID, request in
                let id = nextVolume.withValue { next in
                    defer { next += 1 }
                    return "volume-added-\(next)"
                }
                let volume = UserVolume(
                    id: id,
                    userId: userID,
                    label: request.label,
                    path: request.path,
                    accessMode: request.accessMode,
                    createdAt: now,
                    updatedAt: now
                )
                volumes.withValue { all in
                    let current = all[userID] ?? seededVolumes(userID)
                    all[userID] = current + [volume]
                }
                return volume
            }
            client.updateUserVolume = { _, userID, volumeID, label, accessMode in
                try volumes.withValue { all in
                    var list = all[userID] ?? seededVolumes(userID)
                    guard let index = list.firstIndex(where: { $0.id == volumeID }) else { throw notFound }
                    let old = list[index]
                    list[index] = UserVolume(
                        id: old.id,
                        userId: userID,
                        label: label ?? old.label,
                        path: old.path,
                        accessMode: accessMode,
                        createdAt: old.createdAt,
                        updatedAt: now
                    )
                    all[userID] = list
                    return list[index]
                }
            }
            client.removeUserVolume = { _, userID, volumeID in
                volumes.withValue { all in
                    let current = all[userID] ?? seededVolumes(userID)
                    all[userID] = current.filter { $0.id != volumeID }
                }
            }
        }

        private static func installActivityMocks(into client: inout FilesClient, now: Date) {
            typealias Action = Fixture.ActivityAction
            let actors = [Person.jamie, .sam, .riley, .morgan]
            let seed = Action.allCases.enumerated().flatMap { index, action in
                [ActivityOutcome.ok, .refused].map { outcome in
                    let person = actors[index % actors.count]
                    let age = Double(index * 2 + (outcome == .ok ? 0 : 1)) * Age.hour
                    return ActivityEvent(
                        id: "activity-\(action)-\(outcome.rawValue)",
                        at: ServerTimestamp.string(from: now.addingTimeInterval(-age)),
                        action: action.rawValue,
                        outcome: outcome,
                        actor: person.username,
                        target: Fixture.File.allCases[index % Fixture.File.allCases.count].name
                    )
                }
            }
            let events = LockIsolated(seed)
            client.fetchActivity = { _, filter, _ in
                let query = filter.query.trimmingCharacters(in: .whitespaces).lowercased()
                let shown = events.value.filter { event in
                    (filter.action.map { $0 == event.action } ?? true)
                        && (filter.outcome.map { $0 == event.outcome } ?? true)
                        && (query.isEmpty || [event.actor, event.target]
                            .compactMap { $0?.lowercased() }
                            .contains { $0.contains(query) })
                }
                return ActivityPage(events: shown, isEnabled: true, actions: Action.allCases.map(\.rawValue))
            }
            client.clearActivity = { _ in events.setValue([]) }
        }

        private static func installVersionedFileMocks(into client: inout FilesClient, now: Date) {
            typealias Versioned = Fixture.VersionedFile
            let versionSize: Int64 = 24 * 1024
            @Sendable func history(_ file: Versioned) -> [FileVersion] {
                (0 ..< file.versionCount).map { step in
                    let captured = now.addingTimeInterval(-Double(step + 1) * Age.day)
                    return FileVersion(
                        id: "\(file)-v\(step)",
                        size: versionSize,
                        modifiedAt: captured,
                        capturedAt: captured,
                        author: FileVersion.Author(label: Person.allCases[step % Person.allCases.count].displayName),
                        label: step == 0 && file == .notes ? Fixture.VersionLabel.approved.rawValue : nil,
                        isPinned: step == 0 && file == .notes
                    )
                }
            }
            let histories =
                LockIsolated(Dictionary(uniqueKeysWithValues: Versioned.allCases.map { ("\($0)", history($0)) }))

            @Sendable func page() -> VersionedFilesPage {
                let all = histories.value
                let files = Versioned.allCases.compactMap { file -> VersionedFile? in
                    guard let versions = all["\(file)"], !versions.isEmpty else { return nil }
                    return VersionedFile(
                        id: "\(file)",
                        name: file.file.name,
                        state: file == .roadmap ? .trashed : .live,
                        versions: versions.count,
                        bytes: Int(versionSize) * versions.count,
                        newest: versions.first.map { ServerTimestamp.string(from: $0.capturedAt) }
                    )
                }
                return VersionedFilesPage(
                    files: files,
                    total: files.count,
                    totalBytes: files.reduce(0) { $0 + $1.bytes },
                    totalVersions: files.reduce(0) { $0 + $1.versions }
                )
            }
            client.fetchVersionedFiles = { _, _, _, _ in page() }
            client.fetchVersionedFile = { _, id in
                let versions = histories.value[id] ?? []
                return VersionedFileDetail(versions: versions, totalBytes: versionSize * Int64(versions.count))
            }
            client.deleteVersionsOfFile = { _, id, ids in
                histories.withValue { all in
                    let before = all[id]?.count ?? 0
                    all[id] = ids.map { chosen in all[id]?.filter { !chosen.contains($0.id) } ?? [] } ?? []
                    let remaining = all[id]?.count ?? 0
                    return VersionsDeletion(deleted: before - remaining, remaining: remaining)
                }
            }
        }

        /// The server settings an admin reads and saves: the activity log on, and the access rules.
        /// A save keeps its sections, so the page shows what was saved.
        private static func installServerSettingsMocks(into client: inout FilesClient) {
            typealias Rule = Fixture.AccessRulePath
            let rules = Rule.allCases.map { rule in
                AccessRule(id: rule.id, path: rule.rawValue, isRecursive: rule.isRecursive, permission: rule.permission)
            }
            let base = client.fetchSystemSettings
            let saved = LockIsolated<SystemSettings?>(nil)
            @Sendable func current(_ serverURL: URL) async throws -> SystemSettings {
                if let settings = saved.value {
                    return settings
                }
                var settings = try await base(serverURL)
                settings.accessRules = rules
                settings.activity = ActivitySettings(isEnabled: true)
                let kept = settings
                saved.setValue(kept)
                return settings
            }
            client.fetchSystemSettings = { serverURL in try await current(serverURL) }
            client.updateSystemSettings = { serverURL, patch in
                var settings = try await current(serverURL)
                settings.uploads = patch.uploads ?? settings.uploads
                settings.activity = patch.activity ?? settings.activity
                settings.trash = patch.trash ?? settings.trash
                settings.versions = patch.versions ?? settings.versions
                let kept = settings
                saved.setValue(kept)
                return settings
            }
            client.updateAccessRules = { serverURL, updated in
                var settings = try await current(serverURL)
                settings.accessRules = updated
                let kept = settings
                saved.setValue(kept)
                return updated
            }
        }
    }
#endif
