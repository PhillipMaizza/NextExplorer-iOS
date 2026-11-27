import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct ShareAccessChoiceTests {
    private let serverURL = TestHost.serverURL
    private let now = MockDate.date

    private func folderState() -> CreateShareLinkFeature.State {
        CreateShareLinkFeature.State(
            serverURL: serverURL,
            itemName: TestFolder.documents,
            itemPath: "",
            isDirectory: true,
            now: now
        )
    }

    private func share(accessMode: ShareAccessMode, permissions: SharePermissions) -> Share {
        Share(
            id: "s1", shareToken: "AbC123xyz0", ownerId: "u1",
            sourcePath: "Docs/Report", isDirectory: true,
            accessMode: accessMode, sharingType: .anyone, hasPassword: false,
            permissions: permissions, label: "Report",
            createdAt: now, updatedAt: now
        )
    }

    @Test("A new link opens on Can download, presets set their flags, and Custom starts from what View only allowed")
    func presetsSetTheFlags() async {
        let store = TestStore(initialState: folderState()) { CreateShareLinkFeature() }

        #expect(store.state.accessChoice == .canDownload)
        await store.send(.accessChoiceChanged(.viewOnly)) {
            $0.accessChoice = .viewOnly
            $0.permissions.canDownload = false
        }
        await store.send(.accessChoiceChanged(.custom)) {
            $0.accessChoice = .custom
            $0.permissions = SharePermissions(
                canDownload: false, canDelete: false, canCreateFolders: false, canCreateFiles: false, canUpload: false
            )
        }
        await store.send(.permissionsChanged(SharePermissions(
            canDownload: false, canDelete: false, canCreateFolders: false, canCreateFiles: false
        ))) {
            $0.permissions.canUpload = true
        }
        await store.send(.accessChoiceChanged(.canEdit)) {
            $0.accessChoice = .canEdit
            $0.permissions = SharePermissions()
        }
    }

    @Test("Creating sends the chosen flags with the link")
    func createSendsTheFlags() async {
        var state = folderState()
        state.accessChoice = .custom
        state.permissions = SharePermissions(canUpload: false)
        let sent = LockIsolated<CreateShareLinkRequest?>(nil)
        let store = TestStore(initialState: state) { CreateShareLinkFeature() } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.createShareLink = { _, request in
                sent.setValue(request)
                throw FilesClientError.offline
            }
        }

        await store.send(.createTapped) { $0.step = .creating }
        await store.receive(\.createResponse.failure) {
            $0.step = .form
            $0.errorMessage = FilesClientError.offline.userMessage
        }

        #expect(sent.value?.accessMode == .readwrite)
        #expect(sent.value?.permissions == SharePermissions(canUpload: false))
    }

    @Test("A share whose flags match no preset opens on Custom and saves them untouched")
    func unmatchedFlagsOpenOnCustom() {
        let flags = SharePermissions(canDelete: false, showsVersions: true)
        let opened = EditShareFeature.State(
            serverURL: serverURL,
            share: share(accessMode: .readwrite, permissions: flags),
            now: now
        )
        let viewOnly = EditShareFeature.State(
            serverURL: serverURL,
            share: share(accessMode: .readonly, permissions: SharePermissions(canDownload: false)),
            now: now
        )

        #expect(opened.accessChoice == .custom)
        #expect(opened.permissions == flags)
        #expect(!opened.hasChanges)
        #expect(viewOnly.accessChoice == .viewOnly)
    }

    @Test("Turning one switch under Custom is a change worth saving")
    func aSwitchIsAChange() async {
        let original = share(accessMode: .readwrite, permissions: SharePermissions(canDelete: false))
        let store = TestStore(
            initialState: EditShareFeature.State(serverURL: serverURL, share: original, now: now)
        ) { EditShareFeature() }

        await store.send(.permissionsChanged(SharePermissions(canDelete: false, canUpload: false))) {
            $0.permissions.canUpload = false
        }

        #expect(store.state.hasChanges)
    }
}
