#if DEBUG
    import AuthClient
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    import FilesFeature
    import Foundation
    import UIKit

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
    /// * `UITEST_DISABLE_ANIMATIONS=1` freezes UIKit animations so flood/focus transitions can't flake a tap.
    /// * `UITEST_ANIM_SPEED=<n>`      runs every CoreAnimation (UIKit + SwiftUI) at n× so transitions
    ///                                 still play but collapse in duration.
    public enum UITestSupport {
        public static let mockFlag = "UITEST_MOCK"
        public static let authKey = "UITEST_AUTH"
        public static let scenarioKey = "UITEST_SCENARIO"
        public static let disableAnimationsFlag = "UITEST_DISABLE_ANIMATIONS"
        public static let animationSpeedKey = "UITEST_ANIM_SPEED"

        /// Scales every window's layer time so both UIKit and SwiftUI animations finish near
        /// instantly, while their completion handlers and transition code still run. A no op unless
        /// `UITEST_MOCK=1` and a positive `UITEST_ANIM_SPEED` are set. Safe to call more than once.
        public static func applyAnimationSpeedIfNeeded(from environment: [String: String] = ProcessInfo.processInfo.environment) {
            guard environment[mockFlag] == "1",
                  let raw = environment[animationSpeedKey],
                  let speed = Float(raw), speed > 0 else { return }
            // Called from the app's `onAppear` (via `DispatchQueue.main.async`) and the UI test
            // setup, both on the main thread; assert that so the main actor only UIKit access is
            // legal from this nonisolated helper.
            MainActor.assumeIsolated {
                for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
                    for window in scene.windows {
                        window.layer.speed = speed
                    }
                }
            }
        }

        public static let serverURL = URL(string: "https://nextexplorer.example.com")!
        /// First hit the mocked search returns for any non empty query. Kept stable so a UI test
        /// asserts a fixed name. Mirrored by `Fixture.searchHit` in the test target.
        static let searchHitName = "Quarterly Report.txt"
        /// An image hit the mocked search returns alongside the document hits, so a filter chip test
        /// can assert selecting Images hides the documents. Mirrored by `Fixture.imageSearchHit`.
        static let imageSearchHitName = "Beach.jpg"
        /// A folder name the mocked `createFolder` rejects, so a UI test can drive the failure path
        /// (the new folder sheet stays open on error). Mirrored by `Fixture.failingFolderName`.
        static let failingFolderName = "__uitest_fail__"
        public static let user = User(id: "uitest-user", username: "phillip", email: "phillip@example.com", roles: ["admin"])

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
        }

        static func credentials(serverURL: URL = UITestSupport.serverURL, username: String = "phillip") -> SessionCredentials {
            SessionCredentials(
                serverBaseURL: serverURL,
                authMode: .local,
                cookieName: "connect.sid",
                cookieValue: "uitest-cookie",
                cookieDomain: serverURL.host ?? "nextexplorer.example.com",
                cookiePath: "/",
                cookieIsSecure: true,
                expiresAt: nil,
                username: username
            )
        }

        static func authClient(_ auth: Auth) -> AuthClient {
            var client = AuthClient.previewValue
            // A stateful account set so the multi-server switcher behaves for real in UI tests:
            // adding a server appends a row, switching/removing update the active account.
            let sessions = MockSessionStore(seed: auth == .loggedOut ? [] : [credentials()])
            client.me = { _ in user }
            client.login = { serverURL, identifier, _ in
                sessions.upsert(credentials(serverURL: serverURL, username: identifier))
                return user
            }
            client.loginOIDC = { serverURL in
                sessions.upsert(credentials(serverURL: serverURL, username: user.username))
                return user
            }
            client.fetchStatus = { _ in AuthStatus(localEnabled: true, oidcEnabled: true) }
            client.listSessions = { sessions.all() }
            client.activeAccountID = { sessions.activeID() }
            client.switchAccount = { id in sessions.setActive(id) }
            client.removeAccount = { id in sessions.remove(id) }
            client.clearActiveSession = { sessions.clearActive() }
            client.clearAllSessions = { sessions.clearAll() }
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

        static func filesClient(_ scenario: Scenario) -> FilesClient {
            var client = FilesClient.previewValue
            switch scenario {
            case .normal:
                // A mutable in memory directory so writes (create folder, rename, delete, compress)
                // are reflected by the next browse, letting a UI test assert the listing changed.
                let store = MockFileStore(items: rootItems)
                client.browse = { _, path in
                    BrowseResult(items: store.current(), access: fullAccess, path: path)
                }
                client.createFolder = { _, _, name in
                    // A sentinel name lets a test exercise the failure path (sheet stays open).
                    if name == failingFolderName {
                        throw FilesClientError.network("UITest injected failure")
                    }
                    return store.addFolder(named: name)
                }
                client.renameItem = { _, item, newName in store.rename(item, to: newName) }
                client.deleteItems = { _, items in store.delete(items) }
                client.compressItem = { _, item in store.compress(item) }
                // Offline: a folder's estimate and a per file "download" that completes instantly, so
                // the offline picker + download flow is exercisable without a backend or disk writes.
                client.fetchUsage = { _, path in StorageUsage(path: path, size: 12_000_000, free: 0, total: 0) }
                client.offlineDownloadFile = { _, item in
                    URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(item.name)
                }
                // previewValue returns no search hits; give the search path deterministic results
                // derived from the query so a UI test can assert on them.
                // Stable result names (not echoed from the query) so a UI test asserting on them
                // is immune to which debounced keystroke the search actually fired on.
                client.search = { _, _, query, _ in
                    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return [] }
                    return [
                        SearchResultItem(name: searchHitName, path: "Documents/\(searchHitName)", kind: "txt", matchLine: trimmed, matchLineNumber: 1),
                        SearchResultItem(name: "Meeting Notes.md", path: "Documents/Meeting Notes.md", kind: "md"),
                        // A mixed type hit so a filter chip test can prove it narrows the results.
                        SearchResultItem(name: imageSearchHitName, path: "Documents/\(imageSearchHitName)", kind: "jpg"),
                    ]
                }
            case .empty:
                client.browse = { _, path in
                    BrowseResult(items: [], access: fullAccess, path: path)
                }
                client.favorites = { _ in [] }
                client.mySharedLinks = { _ in [] }
                client.sharedWithMeLinks = { _ in [] }
                client.search = { _, _, _, _ in [] }
            case .error:
                client.browse = { _, _ in throw FilesClientError.network("UITest injected failure") }
                client.search = { _, _, _, _ in throw FilesClientError.network("UITest injected failure") }
            case .sessionExpired:
                client.browse = { _, _ in throw FilesClientError.sessionExpired }
            }
            return client
        }

        private static let fullAccess = FileAccess(
            canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true
        )

        /// The root directory the stateful `.normal` store starts from. Mirrors
        /// `FilesClient.FileItem.previewItems` (internal to FilesClient) and the `Fixture` names in
        /// the test target, so a rename here touches those two sites.
        static let rootItems: [FileItem] = [
            FileItem(name: "Photos", path: "", dateModified: Date(), size: 0, kind: "directory"),
            FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory"),
            FileItem(name: "vacation.jpg", path: "", dateModified: Date(), size: 2_400_000, kind: "jpg", supportsThumbnail: true),
            FileItem(name: "notes.txt", path: "", dateModified: Date(), size: 1_024, kind: "txt"),
        ]
    }

    /// A tiny mutable directory backing the `.normal` files client, so a mutation a UI test drives
    /// (create folder, rename, delete, compress) shows up on the next browse. One instance lives per
    /// app launch; the lock keeps it safe across the client's `@Sendable` async closures.
    final class MockFileStore: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [FileItem]

        init(items: [FileItem]) {
            self.items = items
        }

        private func locked<T>(_ body: () -> T) -> T {
            lock.lock(); defer { lock.unlock() }
            return body()
        }

        func current() -> [FileItem] {
            locked { items }
        }

        func addFolder(named name: String) -> FileItem {
            let folder = FileItem(name: name.isEmpty ? "Untitled Folder" : name, path: "", dateModified: Date(), size: 0, kind: "directory")
            locked { items.append(folder) }
            return folder
        }

        func rename(_ item: FileItem, to newName: String) -> FileItem {
            let renamed = FileItem(name: newName, path: item.path, dateModified: item.dateModified, size: item.size, kind: item.kind, supportsThumbnail: item.supportsThumbnail)
            locked {
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index] = renamed
                }
            }
            return renamed
        }

        func delete(_ toDelete: [FileItem]) {
            let ids = Set(toDelete.map(\.id))
            locked { items.removeAll { ids.contains($0.id) } }
        }

        func compress(_ item: FileItem) -> FileItem {
            let archive = FileItem(name: "\(item.name).zip", path: item.path, dateModified: Date(), size: 0, kind: "zip")
            locked { items.append(archive) }
            return archive
        }
    }

    /// A tiny mutable multi-account set backing the mocked auth client, so the multi-server
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
    }

    public extension AppFeature {
        /// Idempotent: safe to call once at launch. A no op unless `UITEST_MOCK=1` is set.
        static func prepareUITestDependencies(from environment: [String: String] = ProcessInfo.processInfo.environment) {
            guard environment[UITestSupport.mockFlag] == "1" else { return }

            // Wipe persisted defaults so @AppStorage state (view mode, thumbnail size, ...) can't
            // leak between launches and make the suite order dependent: every test starts from the
            // shipped defaults.
            if let bundleID = Bundle.main.bundleIdentifier {
                UserDefaults.standard.removePersistentDomain(forName: bundleID)
            }

            if environment[UITestSupport.disableAnimationsFlag] == "1" {
                MainActor.assumeIsolated {
                    UIView.setAnimationsEnabled(false)
                }
            }

            let auth = UITestSupport.Auth(rawValue: environment[UITestSupport.authKey] ?? "") ?? .loggedOut
            let scenario = UITestSupport.Scenario(rawValue: environment[UITestSupport.scenarioKey] ?? "") ?? .normal

            prepareDependencies {
                $0.authClient = UITestSupport.authClient(auth)
                $0.filesClient = UITestSupport.filesClient(scenario)
                $0.directoryCacheStore = .inMemory()
                $0.jsonCacheStore = .inMemory()
                $0.previewCacheStore = .testValue
                $0.thumbnailCache = .testValue
                $0.offlineFileStore = .inMemory()
            }
        }
    }
#endif
