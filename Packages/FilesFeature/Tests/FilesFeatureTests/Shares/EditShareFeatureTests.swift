import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct EditShareFeatureTests {
    private let serverURL = TestHost.serverURL
    private let fixedNow = MockDate.date.addingTimeInterval(100_000_000)

    private nonisolated func share(
        label: String? = "Report",
        accessMode: ShareAccessMode = .readonly,
        target: ShareTarget = .anyone,
        hasPassword: Bool = false,
        expiresAt: Date? = nil,
        permittedUserIds: [String]? = nil
    ) -> Share {
        .editFixture(
            label: label,
            accessMode: accessMode,
            target: target,
            hasPassword: hasPassword,
            expiresAt: expiresAt,
            permittedUserIds: permittedUserIds
        )
    }

    @Test
    func seedsEveryFieldFromTheShare() {
        let expiry = MockDate.date.addingTimeInterval(200_000_000)
        let state = EditShareFeature.State(
            serverURL: serverURL,
            share: share(
                label: "Bills",
                accessMode: .readwrite,
                target: .users,
                hasPassword: true,
                expiresAt: expiry,
                permittedUserIds: ["u2", "u3"]
            ),
            now: fixedNow
        )
        #expect(state.label == "Bills")
        #expect(state.accessMode == .readwrite)
        #expect(state.target == .users)
        #expect(state.isPasswordEnabled)
        #expect(state.isExpiryEnabled)
        #expect(state.expiresAt == expiry)
        #expect(state.selectedUserIDs == ["u2", "u3"])
    }

    @Test
    func passwordChangeReflectsTheTogglesAndField() {
        var state = EditShareFeature.State(serverURL: serverURL, share: share(hasPassword: true), now: fixedNow)
        #expect(state.passwordChange == .keep) // on, blank

        state.newPassword = TestAccount.password
        #expect(state.passwordChange == .set(TestAccount.password))

        state.newPassword = ""
        state.isPasswordEnabled = false
        #expect(state.passwordChange == .remove) // was protected, now off

        var fresh = EditShareFeature.State(serverURL: serverURL, share: share(hasPassword: false), now: fixedNow)
        fresh.isPasswordEnabled = false
        #expect(fresh.passwordChange == .keep) // never had one
    }

    @Test
    func switchingToUsersLoadsTheShareableListOnce() async {
        let store = TestStore(
            initialState: EditShareFeature.State(serverURL: serverURL, share: share(), now: fixedNow)
        ) {
            EditShareFeature()
        } withDependencies: {
            $0.filesClient.shareableUsers = { _ in
                [User.jamieFixture]
            }
        }

        await store.send(.targetChanged(.users)) {
            $0.target = .users
            $0.usersPhase = .loading
        }
        await store.receive(\.shareableUsersResponse.success) {
            $0.usersPhase = .loaded
            $0.shareableUsers = [User.jamieFixture]
        }

        // Toggling away and back doesn't refetch.
        await store.send(.targetChanged(.anyone)) { $0.target = .anyone }
        await store.send(.targetChanged(.users)) { $0.target = .users }
    }

    @Test
    func saveSendsAnUpdateRequestMatchingTheFormAndPublishesTheResult() async {
        var initial = EditShareFeature.State(serverURL: serverURL, share: share(), now: fixedNow)
        initial.$shareLinksRevision.withLock { $0 = 0 }
        initial.label = "Renamed"
        initial.accessMode = .readwrite
        let updated = share(label: "Renamed", accessMode: .readwrite)

        let recorded = LockIsolated<UpdateShareRequest?>(nil)
        let gate = AsyncGate()
        let store = TestStore(initialState: initial) {
            EditShareFeature()
        } withDependencies: {
            $0.date = .constant(fixedNow)
            $0.filesClient.updateShareLink = { _, id, request in
                #expect(id == "s1")
                recorded.setValue(request)
                try await gate.wait()
                return updated
            }
        }

        await store.send(.saveTapped) { $0.isSaving = true }
        gate.open()
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
        var initial = EditShareFeature.State(serverURL: serverURL, share: share(), now: fixedNow)
        initial.expiryPreset = .custom
        initial.expiresAt = fixedNow.addingTimeInterval(-3600)
        let store = TestStore(initialState: initial) {
            EditShareFeature()
        } withDependencies: {
            $0.date = .constant(fixedNow)
        }

        await store.send(.saveTapped) {
            $0.fieldError = .pastExpiration
        }
    }

    @Test
    func aSaveFailureSurfacesAMessage() async {
        var initial = EditShareFeature.State(serverURL: serverURL, share: share(), now: fixedNow)
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
