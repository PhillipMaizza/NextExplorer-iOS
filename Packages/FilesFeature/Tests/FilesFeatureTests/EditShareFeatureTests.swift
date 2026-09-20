import ComposableArchitecture
import CoreModels
import DependenciesTestSupport
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing

@Suite(.dependencies)
@MainActor
struct EditShareFeatureTests {
    private let serverURL = URL(string: "https://cloud.example.com")!
    private let fixedNow = Date(timeIntervalSince1970: 1_800_000_000)

    private nonisolated func share(
        label: String? = "Report",
        accessMode: ShareAccessMode = .readonly,
        target: ShareTarget = .anyone,
        hasPassword: Bool = false,
        expiresAt: Date? = nil,
        permittedUserIds: [String]? = nil
    ) -> Share {
        Share(
            id: "s1", shareToken: "AbC123xyz0", ownerId: "u1",
            sourcePath: "Docs/Report", isDirectory: true,
            accessMode: accessMode, sharingType: target, hasPassword: hasPassword,
            expiresAt: expiresAt, label: label, downloadCount: 2, lastAccessedAt: nil,
            permittedUserIds: permittedUserIds,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    @Test
    func seedsEveryFieldFromTheShare() {
        let expiry = Date(timeIntervalSince1970: 1_900_000_000)
        let state = EditShareFeature.State(
            serverURL: serverURL,
            share: share(label: "Bills", accessMode: .readwrite, target: .users, hasPassword: true,
                         expiresAt: expiry, permittedUserIds: ["u2", "u3"])
        )
        #expect(state.label == "Bills")
        #expect(state.accessMode == .readwrite)
        #expect(state.target == .users)
        #expect(state.wantsPassword)
        #expect(state.isExpiryEnabled)
        #expect(state.expiresAt == expiry)
        #expect(state.selectedUserIDs == ["u2", "u3"])
    }

    @Test
    func passwordChangeReflectsTheTogglesAndField() {
        var state = EditShareFeature.State(serverURL: serverURL, share: share(hasPassword: true))
        #expect(state.passwordChange == .keep) // on, blank

        state.newPassword = "hunter2"
        #expect(state.passwordChange == .set("hunter2"))

        state.newPassword = ""
        state.wantsPassword = false
        #expect(state.passwordChange == .remove) // was protected, now off

        var fresh = EditShareFeature.State(serverURL: serverURL, share: share(hasPassword: false))
        fresh.wantsPassword = false
        #expect(fresh.passwordChange == .keep) // never had one
    }

    @Test
    func switchingToUsersLoadsTheShareableListOnce() async {
        let store = TestStore(
            initialState: EditShareFeature.State(serverURL: serverURL, share: share())
        ) {
            EditShareFeature()
        } withDependencies: {
            $0.filesClient.shareableUsers = { _ in
                [User(id: "u2", username: "jamie", email: "jamie@example.com", displayName: "Jamie")]
            }
        }

        await store.send(.targetChanged(.users)) {
            $0.target = .users
            $0.usersPhase = .loading
        }
        await store.receive(\.shareableUsersResponse.success) {
            $0.usersPhase = .loaded
            $0.shareableUsers = [User(id: "u2", username: "jamie", email: "jamie@example.com", displayName: "Jamie")]
        }

        // Toggling away and back doesn't refetch.
        await store.send(.targetChanged(.anyone)) { $0.target = .anyone }
        await store.send(.targetChanged(.users)) { $0.target = .users }
    }

    @Test
    func saveSendsAnUpdateRequestMatchingTheFormAndPublishesTheResult() async {
        var initial = EditShareFeature.State(serverURL: serverURL, share: share())
        initial.$shareLinksRevision.withLock { $0 = 0 }
        initial.label = "Renamed"
        initial.accessMode = .readwrite
        initial.isExpiryEnabled = false
        let updated = share(label: "Renamed", accessMode: .readwrite)

        let recorded = LockIsolated<UpdateShareRequest?>(nil)
        let store = TestStore(initialState: initial) {
            EditShareFeature()
        } withDependencies: {
            $0.date = .constant(fixedNow)
            $0.filesClient.updateShareLink = { _, id, request in
                #expect(id == "s1")
                recorded.setValue(request)
                return updated
            }
        }

        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) {
            $0.isSaving = false
            $0.$shareLinksRevision.withLock { $0 = 1 }
        }
        await store.receive(.delegate(.updated(updated)))

        let request = recorded.value
        #expect(request?.label == "Renamed")
        #expect(request?.accessMode == .readwrite)
        #expect(request?.expiresAt == nil)
        #expect(request?.password == .keep)
    }

    @Test
    func aPastExpiryBlocksSaving() async {
        var initial = EditShareFeature.State(serverURL: serverURL, share: share())
        initial.isExpiryEnabled = true
        initial.expiresAt = fixedNow.addingTimeInterval(-3600)
        let store = TestStore(initialState: initial) {
            EditShareFeature()
        } withDependencies: {
            $0.date = .constant(fixedNow)
        }

        await store.send(.saveTapped) {
            $0.errorMessage = L10n.CreateShare.errorPastExpiration
        }
    }

    @Test
    func aSaveFailureSurfacesAMessage() async {
        var initial = EditShareFeature.State(serverURL: serverURL, share: share())
        initial.label = "x"
        let store = TestStore(initialState: initial) {
            EditShareFeature()
        } withDependencies: {
            $0.date = .constant(fixedNow)
            $0.filesClient.updateShareLink = { _, _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.failure) {
            $0.isSaving = false
            $0.errorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
    }
}
