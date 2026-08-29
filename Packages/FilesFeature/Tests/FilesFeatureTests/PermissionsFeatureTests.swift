import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct PermissionsFeatureTests {
    private let serverURL = URL(string: "https://cloud.example.com")!

    private func file(_ name: String = "report.pdf", path: String = "Documents", kind: String = "pdf") -> FileItem {
        FileItem(name: name, path: path, dateModified: Date(), size: 10, kind: kind)
    }

    /// `stat` mode 33261 = `0o100755` — a regular file with `rwxr-xr-x`.
    private func permissions(
        path: String = "Documents/report.pdf",
        mode: Int = 0o100_755,
        owner: String = "phillip",
        group: String = "staff",
        isDirectory: Bool = false
    ) -> FilePermissions {
        FilePermissions(path: path, mode: mode, owner: owner, group: group, uid: 501, gid: 20, isDirectory: isDirectory)
    }

    @Test
    func onAppearLoadsPermissionsAndSeedsTheGridAndDrafts() async {
        let perms = permissions()
        let store = TestStore(
            initialState: PermissionsFeature.State(serverURL: serverURL, item: file())
        ) {
            PermissionsFeature()
        } withDependencies: {
            $0.filesClient.fetchPermissions = { _, _ in perms }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.permissionsResponse.success) {
            $0.isLoading = false
            $0.permissions = perms
            $0.grid = perms.grid
            $0.ownerDraft = "phillip"
            $0.groupDraft = "staff"
        }
        #expect(store.state.octalString == "755")
        #expect(!store.state.isModeDirty)
    }

    @Test
    func togglingABitMakesTheModeDirtyAndUpdatesTheOctalString() async {
        var state = PermissionsFeature.State(serverURL: serverURL, item: file())
        let perms = permissions()
        state.permissions = perms
        state.grid = perms.grid
        let store = TestStore(initialState: state) { PermissionsFeature() }

        // Drop the group execute bit: r-x -> r-- makes 755 -> 745.
        await store.send(.toggle(.group, .execute)) {
            $0.grid[.group] = [.read]
        }
        #expect(store.state.octalString == "745")
        #expect(store.state.isModeDirty)
    }

    @Test
    func applyModeSendsTheOctalStringAndRecursiveFlagThenReloads() async {
        let recorded = LockIsolated<(String, Bool)?>(nil)
        var state = PermissionsFeature.State(serverURL: serverURL, item: file("Projects", path: "", kind: "directory"))
        let dirPerms = permissions(path: "Projects", mode: 0o40_755, isDirectory: true)
        state.permissions = dirPerms
        state.grid = dirPerms.grid
        state.recursive = true

        let store = TestStore(initialState: state) {
            PermissionsFeature()
        } withDependencies: {
            $0.filesClient.changePermissions = { _, _, mode, recursive in
                recorded.setValue((mode, recursive))
            }
            $0.filesClient.fetchPermissions = { _, _ in dirPerms }
        }
        store.exhaustivity = .off

        await store.send(.toggle(.others, .write)) // 755 -> 757
        await store.send(.applyModeTapped) { $0.isSavingMode = true }
        await store.receive(\.modeResponse.success) { $0.isSavingMode = false }
        await store.receive(\.onAppear)
        await store.receive(\.permissionsResponse.success)

        #expect(recorded.value?.0 == "757")
        #expect(recorded.value?.1 == true)
    }

    @Test
    func aFailedChmodSurfacesTheMessageAndKeepsTheEditedGrid() async {
        var state = PermissionsFeature.State(serverURL: serverURL, item: file())
        let perms = permissions()
        state.permissions = perms
        state.grid = perms.grid

        let store = TestStore(initialState: state) {
            PermissionsFeature()
        } withDependencies: {
            $0.filesClient.changePermissions = { _, _, _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.toggle(.owner, .write)) { $0.grid[.owner] = [.read, .execute] }
        await store.send(.applyModeTapped) { $0.isSavingMode = true }
        await store.receive(\.modeResponse.failure) {
            $0.isSavingMode = false
            $0.actionError = FilesClientError.server(statusCode: 403).userMessage
        }
        #expect(store.state.grid[.owner] == [.read, .execute])
    }

    @Test
    func applyOwnershipSendsOnlyTheChangedFields() async {
        let recorded = LockIsolated<(String?, String?)?>(nil)
        var state = PermissionsFeature.State(serverURL: serverURL, item: file())
        let perms = permissions()
        state.permissions = perms
        state.grid = perms.grid
        state.ownerDraft = "root"
        state.groupDraft = "staff" // unchanged

        let store = TestStore(initialState: state) {
            PermissionsFeature()
        } withDependencies: {
            $0.filesClient.changeOwnership = { _, _, owner, group in
                recorded.setValue((owner, group))
            }
            $0.filesClient.fetchPermissions = { _, _ in perms }
        }
        store.exhaustivity = .off

        await store.send(.applyOwnershipTapped) { $0.isSavingOwnership = true }
        await store.receive(\.ownershipResponse.success)

        #expect(recorded.value?.0 == "root")
        #expect(recorded.value?.1 == nil)
    }

    @Test
    func applyOwnershipIsANoOpWhenNeitherDraftChanged() async {
        var state = PermissionsFeature.State(serverURL: serverURL, item: file())
        let perms = permissions()
        state.permissions = perms
        state.ownerDraft = "phillip"
        state.groupDraft = "staff"
        let store = TestStore(initialState: state) { PermissionsFeature() }

        await store.send(.applyOwnershipTapped)
        #expect(!store.state.isSavingOwnership)
    }

    @Test
    func aDeniedChownSurfacesTheServerMessage() async {
        let message = "Permission denied. Changing ownership typically requires root/admin privileges."
        var state = PermissionsFeature.State(serverURL: serverURL, item: file())
        let perms = permissions()
        state.permissions = perms
        state.ownerDraft = "root"

        let store = TestStore(initialState: state) {
            PermissionsFeature()
        } withDependencies: {
            $0.filesClient.changeOwnership = { _, _, _, _ in
                throw FilesClientError.serverMessage(statusCode: 403, message: message)
            }
        }

        await store.send(.applyOwnershipTapped) { $0.isSavingOwnership = true }
        await store.receive(\.ownershipResponse.failure) {
            $0.isSavingOwnership = false
            $0.actionError = FilesClientError.serverMessage(statusCode: 403, message: message).userMessage
        }
    }

    @Test
    func aLoadFailureSurfacesAReadableMessage() async {
        let store = TestStore(
            initialState: PermissionsFeature.State(serverURL: serverURL, item: file())
        ) {
            PermissionsFeature()
        } withDependencies: {
            $0.filesClient.fetchPermissions = { _, _ in throw FilesClientError.sessionExpired }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.permissionsResponse.failure) {
            $0.isLoading = false
            $0.loadError = FilesClientError.sessionExpired.userMessage
        }
    }
}
