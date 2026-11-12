import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import TestUtils
import Testing

@MainActor
struct PermissionsFeatureTests {
    private typealias Store = TestStoreOf<PermissionsFeature>

    struct ChmodCall: Equatable, Sendable {
        let path: String
        let mode: String
        let isRecursive: Bool
    }

    struct ChownCall: Equatable, Sendable {
        let path: String
        let owner: String?
        let group: String?
    }

    private let serverURL = SettingsTestSupport.serverURL
    private let chmodCalls = LockIsolated<[ChmodCall]>([])
    private let chownCalls = LockIsolated<[ChownCall]>([])

    private func file(_ name: String = "report.pdf", path: String = "Documents", kind: String = "pdf") -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: 10, kind: kind)
    }

    /// `stat` mode 33261 = `0o100755`: a regular file with `rwxr-xr-x`.
    private nonisolated func permissions(
        path: String = "Documents/report.pdf",
        mode: Int = 0o100_755,
        owner: String = "phillip",
        group: String = "staff",
        isDirectory: Bool = false
    ) -> FilePermissions {
        FilePermissions(path: path, mode: mode, owner: owner, group: group, uid: 501, gid: 20, isDirectory: isDirectory)
    }

    private func loadedState(_ perms: FilePermissions, item: FileItem? = nil) -> PermissionsFeature.State {
        var state = PermissionsFeature.State(serverURL: serverURL, item: item ?? file())
        state.phase = .loaded
        state.permissions = perms
        state.grid = perms.grid
        state.ownerDraft = perms.owner
        state.groupDraft = perms.group
        return state
    }

    private func makeStore(
        _ state: PermissionsFeature.State,
        fetch: @escaping @Sendable () async throws -> FilePermissions = { throw FilesClientError.offline },
        chmod: @escaping @Sendable () async throws -> Void = { throw FilesClientError.offline },
        chown: @escaping @Sendable () async throws -> Void = { throw FilesClientError.offline }
    ) -> Store {
        let chmodCalls = chmodCalls
        let chownCalls = chownCalls
        return TestStore(initialState: state) {
            PermissionsFeature()
        } withDependencies: {
            $0.filesClient.fetchPermissions = { _, _ in try await fetch() }
            $0.filesClient.changePermissions = { _, path, mode, isRecursive in
                chmodCalls.withValue { $0.append(ChmodCall(path: path, mode: mode, isRecursive: isRecursive)) }
                try await chmod()
            }
            $0.filesClient.changeOwnership = { _, path, owner, group in
                chownCalls.withValue { $0.append(ChownCall(path: path, owner: owner, group: group)) }
                try await chown()
            }
        }
    }

    // MARK: Loading

    @Test
    func onAppearLoadsPermissionsAndSeedsTheGridAndDrafts() async {
        let perms = permissions()
        let store = makeStore(PermissionsFeature.State(serverURL: serverURL, item: file()), fetch: { perms })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.permissionsResponse.success) {
            $0.phase = .loaded
            $0.permissions = perms
            $0.grid = [.owner: [.read, .write, .execute], .group: [.read, .execute], .others: [.read, .execute]]
            $0.ownerDraft = "phillip"
            $0.groupDraft = "staff"
        }
        #expect(store.state.octalString == "755")
        #expect(!store.state.isModeDirty)
        #expect(!store.state.isOwnershipDirty)
    }

    @Test
    func aLoadFailureSurfacesAReadableMessage() async {
        let store = makeStore(
            PermissionsFeature.State(serverURL: serverURL, item: file()),
            fetch: { throw FilesClientError.sessionExpired }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.permissionsResponse.failure) { $0.phase = .failed(L10n.Error.sessionExpired) }
    }

    // MARK: Mode

    @Test
    func togglingABitMakesTheModeDirtyAndTogglingItBackCleansIt() async {
        let store = makeStore(loadedState(permissions()))

        // Dropping the group execute bit turns r-x into r--, so 755 becomes 745.
        await store.send(.toggle(.group, .execute)) { $0.grid[.group] = [.read] }
        #expect(store.state.octalString == "745")
        #expect(store.state.isModeDirty)

        await store.send(.toggle(.group, .execute)) { $0.grid[.group] = [.read, .execute] }
        #expect(store.state.octalString == "755")
        #expect(!store.state.isModeDirty)
    }

    private func stateShowingAnError() -> PermissionsFeature.State {
        var state = loadedState(permissions())
        state.actionError = "old"
        return state
    }

    @Test
    func togglingABitClearsAShownError() async {
        let store = makeStore(stateShowingAnError())

        await store.send(.toggle(.others, .write)) {
            $0.grid[.others] = [.read, .write, .execute]
            $0.actionError = nil
        }
    }

    @Test
    func editingTheOwnerDraftClearsAShownError() async {
        let store = makeStore(stateShowingAnError())

        await store.send(.ownerDraftChanged("root")) {
            $0.ownerDraft = "root"
            $0.actionError = nil
        }
    }

    @Test
    func editingTheGroupDraftClearsAShownError() async {
        let store = makeStore(stateShowingAnError())

        await store.send(.groupDraftChanged("wheel")) {
            $0.groupDraft = "wheel"
            $0.actionError = nil
        }
    }

    @Test
    func theRecursiveSwitchIsRemembered() async {
        let store = makeStore(loadedState(permissions()))

        await store.send(.recursiveChanged(true)) { $0.recursive = true }
        await store.send(.recursiveChanged(false)) { $0.recursive = false }
    }

    @Test
    func applyModeOnAFolderSendsTheOctalStringAndRecursiveFlagThenReloadsWhatStuck() async {
        let before = permissions(path: "Projects", mode: 0o40_755, isDirectory: true)
        let stuck = permissions(path: "Projects", mode: 0o40_754, isDirectory: true)
        var state = loadedState(before, item: file("Projects", path: "", kind: "directory"))
        state.recursive = true
        let store = makeStore(state, fetch: { stuck }, chmod: {})

        await store.send(.toggle(.others, .write)) { $0.grid[.others] = [.read, .write, .execute] }
        await store.send(.applyModeTapped) { $0.isSavingMode = true }
        await store.receive(\.modeResponse.success) { $0.isSavingMode = false }
        await store.receive(\.onAppear) { $0.phase = .loading }
        await store.receive(\.permissionsResponse.success) {
            $0.phase = .loaded
            $0.permissions = stuck
            $0.grid = [.owner: [.read, .write, .execute], .group: [.read, .execute], .others: [.read]]
            $0.recursive = false
        }

        #expect(chmodCalls.value == [ChmodCall(path: "Projects", mode: "757", isRecursive: true)])
        #expect(!store.state.isModeDirty)
    }

    @Test
    func applyModeOnAFileNeverSendsTheRecursiveFlag() async {
        var state = loadedState(permissions())
        state.recursive = true
        let store = makeStore(state, fetch: { permissions(mode: 0o100_644) }, chmod: {})

        await store.send(.toggle(.owner, .execute)) { $0.grid[.owner] = [.read, .write] }
        await store.send(.toggle(.group, .execute)) { $0.grid[.group] = [.read] }
        await store.send(.toggle(.others, .execute)) { $0.grid[.others] = [.read] }
        await store.send(.applyModeTapped) { $0.isSavingMode = true }
        await store.receive(\.modeResponse.success) { $0.isSavingMode = false }
        await store.receive(\.onAppear) { $0.phase = .loading }
        await store.receive(\.permissionsResponse.success) {
            $0.phase = .loaded
            $0.permissions = permissions(mode: 0o100_644)
            $0.grid = [.owner: [.read, .write], .group: [.read], .others: [.read]]
            $0.recursive = false
        }

        #expect(chmodCalls.value == [ChmodCall(path: "Documents/report.pdf", mode: "644", isRecursive: false)])
    }

    @Test
    func applyModeDoesNothingWhenTheGridIsUnchanged() async {
        let store = makeStore(loadedState(permissions()), chmod: {})

        await store.send(.applyModeTapped)
        #expect(chmodCalls.value.isEmpty)
    }

    @Test
    func applyModeIsIgnoredWhileASaveIsRunning() async {
        var state = loadedState(permissions())
        state.grid[.owner] = [.read]
        state.isSavingMode = true
        let store = makeStore(state, chmod: {})

        await store.send(.applyModeTapped)
        #expect(chmodCalls.value.isEmpty)
    }

    @Test
    func aFailedChmodSurfacesTheMessageAndKeepsTheEditedGrid() async {
        let store = makeStore(loadedState(permissions()), chmod: { throw FilesClientError.server(statusCode: 403) })

        await store.send(.toggle(.owner, .write)) { $0.grid[.owner] = [.read, .execute] }
        await store.send(.applyModeTapped) { $0.isSavingMode = true }
        await store.receive(\.modeResponse.failure) {
            $0.isSavingMode = false
            $0.actionError = L10n.Error.server(403)
        }
        #expect(store.state.grid[.owner] == [.read, .execute])
        #expect(chmodCalls.value == [ChmodCall(path: "Documents/report.pdf", mode: "555", isRecursive: false)])
    }

    // MARK: Ownership

    struct OwnershipCase: Sendable {
        let owner: String
        let group: String
        let sentOwner: String?
        let sentGroup: String?
    }

    @Test(
        "Ownership sends only the fields that changed, trimmed",
        arguments: [
            OwnershipCase(owner: "root", group: "staff", sentOwner: "root", sentGroup: nil),
            OwnershipCase(owner: "phillip", group: "wheel", sentOwner: nil, sentGroup: "wheel"),
            OwnershipCase(owner: "root", group: "wheel", sentOwner: "root", sentGroup: "wheel"),
            OwnershipCase(owner: "  root  ", group: "staff", sentOwner: "root", sentGroup: nil),
            OwnershipCase(owner: "", group: "wheel", sentOwner: nil, sentGroup: "wheel"),
        ]
    )
    func applyOwnershipSendsOnlyTheChangedFields(_ testCase: OwnershipCase) async {
        var state = loadedState(permissions())
        state.ownerDraft = testCase.owner
        state.groupDraft = testCase.group
        let store = makeStore(state, fetch: { permissions() }, chown: {})

        await store.send(.applyOwnershipTapped) { $0.isSavingOwnership = true }
        await store.receive(\.ownershipResponse.success) { $0.isSavingOwnership = false }
        await store.receive(\.onAppear) { $0.phase = .loading }
        await store.receive(\.permissionsResponse.success) {
            $0.phase = .loaded
            $0.ownerDraft = "phillip"
            $0.groupDraft = "staff"
        }

        #expect(chownCalls.value == [ChownCall(path: "Documents/report.pdf", owner: testCase.sentOwner, group: testCase.sentGroup)])
    }

    @Test(
        "Ownership does nothing when no draft differs from the file",
        arguments: [("phillip", "staff"), ("  phillip ", "staff"), ("", ""), ("   ", "staff")]
    )
    func applyOwnershipIsANoOpWhenNeitherDraftChanged(owner: String, group: String) async {
        var state = loadedState(permissions())
        state.ownerDraft = owner
        state.groupDraft = group
        let store = makeStore(state, chown: {})

        await store.send(.applyOwnershipTapped)
        #expect(chownCalls.value.isEmpty)
    }

    @Test
    func aDeniedChownSurfacesTheServerMessage() async {
        let message = "Permission denied. Changing ownership typically requires root/admin privileges."
        var state = loadedState(permissions())
        state.ownerDraft = "root"
        let store = makeStore(state, chown: { throw FilesClientError.serverMessage(statusCode: 403, message: message) })

        await store.send(.applyOwnershipTapped) { $0.isSavingOwnership = true }
        await store.receive(\.ownershipResponse.failure) {
            $0.isSavingOwnership = false
            $0.actionError = message
        }
        #expect(store.state.ownerDraft == "root")
    }
}
