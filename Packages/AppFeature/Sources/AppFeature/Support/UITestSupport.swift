#if DEBUG
    import AuthClient
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import FilesFeature
    import Foundation
    import NetworkClient
    import SwiftUI
    #if os(iOS)
        import UIKit
    #elseif os(macOS)
        import AppKit
    #endif

    /// Wires a fully mocked, backend free dependency graph for XCUITest runs. The app target calls
    /// `AppFeature.prepareUITestDependencies` from its `init` before the root store is built, so the
    /// store lazily resolves against these prepared values instead of the live network clients.
    ///
    /// Everything is driven from the launch environment the test harness sets, so a single app binary
    /// covers every scenario:
    ///
    /// * `UITEST_MOCK=1`            enables the whole path (nothing below runs without it).
    /// * `UITEST_AUTH`             `loggedOut` (default) / `loggedIn` / `expired`.
    /// * `UITEST_SCENARIO`        `normal` (default) / `empty` / `error`.
    /// * `UITEST_OFFLINE_LAUNCH=1`  the server cannot be reached at all (`me` included), and the launch
    ///                                 finds what an earlier session kept: the root listing and `notes.txt`
    ///                                 pinned with its copy, as after closing the app at home and opening
    ///                                 it on a plane.
    /// * `UITEST_SEARCH_OFFLINE=1`  the search finds no server (`offline`), while browsing still works,
    ///                                 so a test can pin files first and then search without a connection.
    /// * `UITEST_DISABLE_ANIMATIONS=1` turns off UIKit animations and every SwiftUI animation
    ///                                 (`disablesAnimationsUnderUITest`), so no transition flakes a tap
    ///                                 or keeps XCUITest waiting for the app to idle.
    /// * `UITEST_ANIM_SPEED=<n>`      runs every CoreAnimation (UIKit + SwiftUI) at n× so transitions
    ///                                 still play but collapse in duration.
    /// * `UITEST_ORIENTATION=landscape`  rotates the window to landscape after launch. The iPhone Duo
    ///                                 simulator ignores `XCUIDevice` rotation; only foldables (and
    ///                                 media viewers) allow landscape, so elsewhere it is a no op.
    public enum UITestSupport {
        public static let mockFlag = UITestEnvironment.mockKey
        public static let authKey = UITestLaunchKey.auth.rawValue
        public static let scenarioKey = UITestLaunchKey.scenario.rawValue
        public static let disableAnimationsFlag = UITestEnvironment.disableAnimationsKey
        public static let animationSpeedKey = UITestLaunchKey.animationSpeed.rawValue
        public static let orientationKey = UITestLaunchKey.orientation.rawValue
        public static let legacyDownloadsKey = UITestLaunchKey.legacyDownloads.rawValue
        public static let searchOfflineKey = UITestLaunchKey.searchOffline.rawValue
        public static let offlineLaunchKey = UITestLaunchKey.offlineLaunch.rawValue
        /// The file the offline launch finds pinned.
        static let pinnedFileName = UITestFixture.File.notes.name
        public static let legacyDownloadName = "legacy-report.pdf"

        /// Whether this launch runs under XCUITest with animations off.
        public static let shouldDisableAnimations: Bool = {
            let environment = ProcessInfo.processInfo.environment
            return environment[mockFlag] == UITestLaunchKey.on && environment[disableAnimationsFlag] == UITestLaunchKey
                .on
        }()

        /// Drops a transaction's animation when the launch asks for no animations. Nonisolated: SwiftUI
        /// calls it from whichever thread renders.
        nonisolated static func stripAnimations(_ transaction: inout Transaction) {
            guard shouldDisableAnimations else { return }
            transaction.animation = nil
            #if os(iOS)
                transaction.disablesAnimations = true
            #endif
        }

        /// A download folder holding one file an earlier version saved, so the tests can prove such files
        /// still list, open and delete. Held in memory: the sandbox folders stay untouched.
        static func legacyDownloadStore() -> LegacyDownloadStore {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(legacyDownloadName)
            FileManager.default.createFile(atPath: url.path, contents: Data("legacy".utf8))
            let downloads = LockIsolated([
                LocalDownload(
                    url: url,
                    fileName: legacyDownloadName,
                    size: 6,
                    modifiedDate: Date(timeIntervalSince1970: 1_700_000_000)
                ),
            ])
            return LegacyDownloadStore(
                save: { _, _, _ in throw CocoaError(.fileWriteUnknown) },
                list: { _ in downloads.value },
                delete: { url in downloads.withValue { $0.removeAll { $0.url == url } } },
                rename: { url, _ in url }
            )
        }

        /// No server to reach, and what an earlier session of the signed in account kept on the device.
        static func startOffline(_ dependencies: inout DependencyValues) {
            dependencies.authClient.me = { _ in throw AuthClientError.network("UITest offline launch") }
            dependencies.filesClient.browse = { _, _ in throw FilesClientError.offline }
            dependencies.filesClient.search = { _, _, _, _ in throw FilesClientError.offline }
            dependencies.filesClient.favorites = { _ in throw FilesClientError.offline }
            dependencies.filesClient.serverFeatures = { _ in throw FilesClientError.offline }

            let accountID = credentials().accountID
            dependencies.directoryCacheStore.bound(to: accountID).write(
                serverURL: serverURL,
                path: "",
                result: BrowseResult(items: rootItems, access: fullAccess, path: ""),
                etag: nil,
                fetchedAt: Date(timeIntervalSince1970: 1_700_000_000)
            )
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(pinnedFileName)
            FileManager.default.createFile(atPath: copy.path, contents: Data("Kept for the flight".utf8))
            let pinned = rootItems.first { $0.name == pinnedFileName }
            let offline = OfflineFileStore.inMemory(
                localURLs: [pinnedFileName: copy],
                copyMetadata: pinned.map {
                    [pinnedFileName: OfflineCopyMetadata(dateModified: $0.dateModified, size: $0.size)]
                } ?? [:]
            )
            offline.setPinnedRoots([OfflinePinnedRoot(path: pinnedFileName, isDirectory: false)])
            dependencies.offlineFileStore = offline
        }

        /// How long the hinge needs to unlock rotation on a foldable before landscape is requested.
        private static let orientationDelay: TimeInterval = 1

        /// Scales every window's layer time so both UIKit and SwiftUI animations finish near
        /// instantly, while their completion handlers and transition code still run. A no op unless
        /// `UITEST_MOCK=1` and a positive `UITEST_ANIM_SPEED` are set. Safe to call more than once.
        public static func applyAnimationSpeedIfNeeded(
            from environment: [String: String] = ProcessInfo.processInfo.environment
        ) {
            guard environment[mockFlag] == UITestLaunchKey.on,
                  let raw = environment[animationSpeedKey],
                  let speed = Float(raw), speed > 0 else { return }
            // Called from the app's `onAppear` (via `DispatchQueue.main.async`) and the UI test
            // setup, both on the main thread; assert that so the main actor only UIKit access is
            // legal from this nonisolated helper.
            MainActor.assumeIsolated {
                // The waits between animation steps follow the same speed as the animations.
                DSMotion.speed = Double(speed)
                #if os(iOS)
                    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                        for window in scene.windows {
                            window.layer.speed = speed
                        }
                    }
                #elseif os(macOS)
                    for window in NSApp.windows {
                        window.contentView?.layer?.speed = speed
                    }
                #endif
            }
        }

        /// Called with `applyAnimationSpeedIfNeeded`; waits a moment so the hinge has already
        /// unlocked rotation on a foldable.
        public static func applyOrientationIfNeeded(
            from environment: [String: String] = ProcessInfo.processInfo.environment
        ) {
            #if os(iOS)
                guard environment[mockFlag] == UITestLaunchKey.on,
                      environment[orientationKey] == UITestLaunchKey.landscape else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + orientationDelay) {
                    MainActor.assumeIsolated {
                        ActiveWindowScene.current?
                            .requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight)) { _ in }
                    }
                }
            #endif
        }

        public static let serverURL = URL(string: "https://\(UITestFixture.Host.primary.rawValue)")!
        /// What `slowOperations` reports before it waits, and how long it waits (a cancel ends it sooner).
        static let heldProgress = 0.4
        static let heldSeconds = 600
        static let uploadSteps = 8
        static let uploadStepDelay: Duration = .milliseconds(150)
        /// Signing in as this name answers "the password is right, now send a code", so a UI test
        /// can drive the second factor page.
        static let secondFactorIdentifier = UITestFixture.Credential.secondFactorUser.rawValue
        /// Signing in as this name is refused as wrong credentials, so a UI test can drive the
        /// failure path.
        static let rejectedIdentifier = UITestFixture.Credential.rejectedUser.rawValue
        /// The authenticator code the mocked `loginTOTP` accepts.
        static let validCode = UITestFixture.Credential.validCode.rawValue
        /// The recovery code the mocked `loginTOTP` accepts.
        static let validRecoveryCode = UITestFixture.Credential.recoveryCode.rawValue
        public static let user = User(
            id: UITestFixture.SignedInAccount.id.rawValue,
            username: UITestFixture.SignedInAccount.username.rawValue,
            email: UITestFixture.SignedInAccount.email.rawValue,
            roles: ["admin"]
        )

        enum Auth: String {
            case loggedOut
            case loggedIn
            case expired
        }

        enum Scenario: String {
            case normal
            case empty
            case error
            /// Browse answers 401, tripping the mid session expiry path back to login.
            case sessionExpired
            /// Like `normal`, but the folder holds one file of every kind the gallery pages
            /// through, and text files read back `galleryNotesText`.
            case gallery
            /// Like `normal`, but a delete, copy or move reports 40 percent and then waits until it is cancelled, so
            /// the
            /// progress bar and its Cancel button stay on screen.
            case slowOperations
        }

        static func credentials(
            serverURL: URL = UITestSupport.serverURL,
            username: String = "phillip"
        ) -> SessionCredentials {
            SessionCredentials(
                serverBaseURL: serverURL,
                authMode: .local,
                cookieName: "connect.sid",
                cookieValue: "uitest-cookie",
                cookieDomain: serverURL.host ?? UITestFixture.Host.primary.rawValue,
                cookiePath: "/",
                isCookieSecure: true,
                expiresAt: nil,
                username: username
            )
        }

        static func authClient(_ auth: Auth, expiry: MockSessionExpiry = MockSessionExpiry()) -> AuthClient {
            var client = AuthClient.previewValue
            // A stateful account set so the multiserver switcher behaves for real in UI tests:
            // adding a server appends a row, switching/removing update the active account.
            let sessions = MockSessionStore(seed: auth == .loggedOut ? [] : [credentials()])
            client.me = { _ in
                if expiry.isRejected {
                    throw AuthClientError.sessionExpired
                }
                return user
            }
            client.login = { serverURL, identifier, _ in
                if identifier == secondFactorIdentifier {
                    throw AuthClientError.secondFactorRequired
                }
                if identifier == rejectedIdentifier {
                    throw AuthClientError.invalidCredentials
                }
                sessions.upsert(credentials(serverURL: serverURL, username: identifier))
                return user
            }
            client.loginTOTP = { serverURL, code in
                guard code == validCode || code == validRecoveryCode else {
                    throw AuthClientError.invalidCode
                }
                sessions.upsert(credentials(serverURL: serverURL, username: secondFactorIdentifier))
                return user
            }
            client.loginOIDC = { serverURL, _ in
                sessions.upsert(credentials(serverURL: serverURL, username: user.username))
                return user
            }
            client.fetchStatus = { _ in AuthStatus(localEnabled: true, oidcEnabled: true) }
            client.listSessions = { sessions.all() }
            client.listSessionsOrThrow = { sessions.all() }
            client.activeAccountID = { sessions.activeID() }
            client.switchAccount = { id in sessions.setActive(id) }
            client.removeAccount = { id in sessions.remove(id) }
            client.clearActiveSession = { sessions.clearActive() }
            client.clearAllSessions = { sessions.clearAll() }
            client.lockSessions = { shouldLock in sessions.lock(where: shouldLock) }
            client.setRequireSignIn = { id, requireSignIn in sessions.setRequireSignIn(requireSignIn, id: id) }
            switch auth {
            case .loggedOut:
                client.restoreSession = { nil }
            case .loggedIn:
                client.restoreSession = { sessions.active() }
            case .expired:
                client.restoreSession = { sessions.active() }
                client.me = { _ in throw AuthClientError.sessionExpired }
            }
            return client
        }

        static func filesClient(_ scenario: Scenario, expiry: MockSessionExpiry = MockSessionExpiry()) -> FilesClient {
            var client = FilesClient.previewValue
            switch scenario {
            case .normal, .gallery, .slowOperations:
                installAccountMocks(into: &client)
                installShareMocks(into: &client)
                installFavoriteMocks(into: &client, now: Date())
                installAdminMocks(into: &client, now: Date())
                // An in memory file tree so writes (create, rename, delete, move, copy, compress) land
                // in the folder they name and show in the next listing, as on the server.
                // The root and its folders hold the fixture (the gallery only its root, whose one folder
                // is where a move lands); deeper folders start empty.
                let store = scenario == .gallery
                    ? MockFileTree(seed: ["": galleryItems])
                    : MockFileTree(seed: MockBrowseTree.seed(now: Date()), trash: MockBrowseTree.trash(now: Date()))
                if scenario == .gallery {
                    installGalleryFiles(into: &client)
                }
                client.browse = { _, path in
                    BrowseResult(items: store.list(path), access: MockBrowseTree.access(for: path), path: path)
                }
                client.createFolder = { _, path, name in
                    // A sentinel name lets a test exercise the failure path (sheet stays open).
                    if name == UITestFixture.failingFolderName {
                        throw FilesClientError.network(injectedFailure)
                    }
                    return store.createFolder(in: path, named: name)
                }
                client.renameItem = { _, item, newName in store.rename(item, to: newName) }
                client.uploadFile = { _, fileURL, fileName, destination, onProgress in
                    for step in 1 ... uploadSteps {
                        try await Task.sleep(for: uploadStepDelay)
                        onProgress(Double(step) / Double(uploadSteps))
                    }
                    let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? .zero
                    store.addFile(named: fileName, size: Int64(size), in: destination)
                }
                client.deleteItems = { _, items, permanent, onProgress in
                    guard scenario == .slowOperations else { return store.delete(items, permanent: permanent) }
                    onProgress?(heldProgress)
                    try await Task.sleep(for: .seconds(heldSeconds))
                    return store.delete(items, permanent: permanent)
                }
                client.deleteImpact = { _, items in
                    DeleteImpact(shareCount: 0, trash: DeleteImpact.TrashPlan(
                        isEnabled: true,
                        retentionDays: trashRetentionDays,
                        items: items.map { DeleteImpact.Disposition(path: $0.id, isTrashBound: true) }
                    ))
                }
                // A server with its trash on: deletes land there and can be restored or purged.
                client.serverFeatures = { _ in
                    ServerFeatures(
                        isUserVolumesEnabled: true,
                        isVolumeUsageEnabled: true,
                        trash: TrashAvailability(isEnabled: true, retentionDays: trashRetentionDays)
                    )
                }
                client.fetchTrash = { _ in store.trashListing() }
                client.fetchTrashEntries = { _, itemID, path in
                    guard let listing = store.trashEntries(itemID, path: path) else {
                        throw FilesClientError.server(statusCode: HTTPStatus.notFound.rawValue)
                    }
                    return listing
                }
                client.fetchTrashText = { _, itemID, path in
                    guard let text = store.trashText(itemID, path: path) else {
                        throw FilesClientError.server(statusCode: HTTPStatus.notFound.rawValue)
                    }
                    return text
                }
                client.restoreTrash = { _, target, _, _, _ in
                    switch target {
                    case let .items(ids): store.restore(ids)
                    case let .entries(itemID, paths): store.restoreEntries(itemID, paths: paths)
                    }
                }
                client.purgeTrash = { _, ids, _ in store.purge(ids) }
                client.emptyTrash = { _ in store.emptyTrash() }
                client.transferItems = { _, items, destination, operation, onProgress in
                    guard scenario == .slowOperations else {
                        return store.transfer(items, to: destination, operation: operation)
                    }
                    onProgress?(heldProgress)
                    try await Task.sleep(for: .seconds(heldSeconds))
                    return store.transfer(items, to: destination, operation: operation)
                }
                client.compressItem = { _, item in store.compress(item) }
                // Sizes and counts come from the tree; a per file "download" completes at once, so the
                // offline flow runs without a backend or disk writes.
                client.fetchUsage = { _, path in
                    StorageUsage(
                        path: path,
                        size: store.metadata(at: path).directory?.totalSize ?? 0,
                        free: 0,
                        total: 0
                    )
                }
                client.fetchMetadata = { _, path in store.metadata(at: path) }
                client.offlineDownloadFile = { _, item, onProgress in
                    onProgress(1)
                    return URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(item.name)
                }
                // Searches the tree itself. The search fixtures match any phrase, so a test asserts
                // fixed names whichever debounced keystroke the search fired on.
                client.search = { _, scopePath, query, _ in
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return [] }
                    return store.search(
                        trimmed,
                        under: scopePath,
                        contentMatches: Set(UITestFixture.File.searchFixtures.map(\.name))
                    )
                }
            case .empty:
                empty([.browse, .search, .favorites, .shares], in: &client)
            case .error:
                fail([.browse, .search], in: &client)
            case .sessionExpired:
                client.browse = { _, _ in
                    expiry.reject()
                    throw FilesClientError.sessionExpired
                }
            }
            return client
        }

        /// The message every injected network failure carries.
        static let injectedFailure = "UITest injected failure"
        /// How long the mocked trash keeps an item.
        static let trashRetentionDays = 30

        static let fullAccess = FileAccess(
            canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true
        )

        /// The root listing a launch without a server shows from its cache.
        static var rootItems: [FileItem] {
            MockBrowseTree.seed(now: Date())[""] ?? []
        }
    }

    /// Flips once the server "rejects" the session, so the auth client's `me` check agrees with a 401
    /// that a request already answered. Launch validation passes first, as it does in the field.
    final class MockSessionExpiry: @unchecked Sendable {
        private let lock = NSLock()
        private var rejected = false

        var isRejected: Bool {
            lock.lock(); defer { lock.unlock() }
            return rejected
        }

        func reject() {
            lock.lock(); defer { lock.unlock() }
            rejected = true
        }
    }

    /// A tiny mutable multiaccount set backing the mocked auth client, so the multiserver
    /// switcher (add / switch / remove) works end to end in UI tests. One instance per launch.
    final class MockSessionStore: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: StoredSessions

        init(seed: [SessionCredentials]) {
            var s = StoredSessions()
            for credential in seed {
                s.upsert(credential)
            }
            stored = s
        }

        private func locked<T>(_ body: () -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body()
        }

        func all() -> [SessionCredentials] {
            locked { stored.sessions }
        }

        func active() -> SessionCredentials? {
            locked { stored.active }
        }

        func activeID() -> String? {
            locked { stored.activeID }
        }

        func upsert(_ credential: SessionCredentials) {
            locked { stored.upsert(credential) }
        }

        func setActive(_ id: String) -> SessionCredentials? {
            locked {
                guard stored.session(id: id) != nil else { return nil }
                stored.activeID = id
                return stored.active
            }
        }

        func remove(_ id: String) -> SessionCredentials? {
            locked { stored.remove(id: id); return stored.active }
        }

        func clearActive() -> SessionCredentials? {
            locked {
                guard let active = stored.active else { return nil }
                stored.remove(id: active.accountID)
                return stored.active
            }
        }

        func clearAll() {
            locked { stored = StoredSessions() }
        }

        func lock(where shouldLock: (SessionCredentials) -> Bool) -> [SessionCredentials] {
            locked { stored.lock(where: shouldLock) }
        }

        func setRequireSignIn(_ requireSignIn: RequireSignIn?, id: String) {
            locked { stored.setRequireSignIn(requireSignIn, id: id) }
        }
    }

    public extension AppFeature {
        /// Idempotent: safe to call once at launch. A no op unless `UITEST_MOCK=1` is set.
        static func prepareUITestDependencies(from environment: [String: String] = ProcessInfo.processInfo.environment)
        {
            guard environment[UITestSupport.mockFlag] == UITestLaunchKey.on else { return }

            // Wipe persisted defaults so @AppStorage state (view mode, thumbnail size, ...) can't
            // leak between launches and make the suite order dependent: every test starts from the
            // shipped defaults.
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }

            if environment[UITestSupport.disableAnimationsFlag] == UITestLaunchKey.on {
                #if os(iOS)
                    MainActor.assumeIsolated {
                        UIView.setAnimationsEnabled(false)
                    }
                #endif
            }

            let auth = UITestSupport.Auth(rawValue: environment[UITestSupport.authKey] ?? "") ?? .loggedOut
            let scenario = UITestSupport.Scenario(rawValue: environment[UITestSupport.scenarioKey] ?? "") ?? .normal

            let expiry = MockSessionExpiry()
            prepareDependencies {
                $0.authClient = UITestSupport.authClient(auth, expiry: expiry)
                $0.filesClient = UITestSupport.filesClient(scenario, expiry: expiry)
                UITestSupport.empty(
                    UITestArea.parse(environment[UITestLaunchKey.emptyAreas.rawValue]),
                    in: &$0.filesClient
                )
                UITestSupport.fail(
                    UITestArea.parse(environment[UITestLaunchKey.failingAreas.rawValue]),
                    in: &$0.filesClient
                )
                if environment[UITestSupport.searchOfflineKey] == UITestLaunchKey.on {
                    $0.filesClient.search = { _, _, _, _ in throw FilesClientError.offline }
                }
                $0.directoryCacheStore = .inMemory()
                $0.jsonCacheStore = .inMemory()
                $0.previewCacheStore = .testValue
                $0.thumbnailCache = .testValue
                $0.offlineFileStore = .inMemory()
                if environment[UITestSupport.legacyDownloadsKey] == UITestLaunchKey.on {
                    $0.localDownloadStore = UITestSupport.legacyDownloadStore()
                }
                if environment[UITestSupport.offlineLaunchKey] == UITestLaunchKey.on {
                    UITestSupport.startOffline(&$0)
                }
            }
        }
    }

    public extension View {
        /// Under XCUITest with animations off, no SwiftUI animation runs, explicit `withAnimation`
        /// included: every transaction through the root view loses its animation.
        ///
        /// SwiftUI reads transactions off the main thread too (a lazy grid places its cells on the
        /// async renderer), so the closure is a nonisolated function: a closure written here would be
        /// main actor isolated, and its isolation check stops the app on that thread.
        func disablesAnimationsUnderUITest() -> some View {
            transaction(UITestSupport.stripAnimations)
        }
    }
#endif
