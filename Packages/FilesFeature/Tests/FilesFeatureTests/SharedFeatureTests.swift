import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct SharedFeatureTests {
    private let serverURL = URL(string: "https://cloud.example.com")!

    private func makeShare(id: String = "1", byMe: Bool = true) -> Share {
        Share(
            id: id,
            shareToken: "tok\(id)",
            ownerId: byMe ? "me" : "other",
            sourcePath: byMe ? "Documents/Report.pdf" : nil,
            sourceName: byMe ? nil : "Report.pdf",
            isDirectory: false,
            accessMode: .readonly,
            sharingType: .anyone,
            hasPassword: false,
            createdAt: Date(),
            updatedAt: Date()
        )
    }

    // MARK: Happy path

    @Test
    func onAppearLoadsTheByMeSegment() async {
        let share = makeShare()
        let store = TestStore(initialState: SharedFeature.State(serverURL: serverURL)) {
            SharedFeature()
        } withDependencies: {
            $0.filesClient.mySharedLinks = { _ in [share] }
            $0.filesClient.shareableUsers = { _ in [] }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.sharesResponse) {
            $0.isLoading = false
            $0.byMe = [share]
            $0.loadedSegments = [.byMe]
        }
        await store.receive(\.usersResponse)
    }

    @Test
    func switchingToWithMeLoadsItThenSwitchingBackDoesNotReload() async {
        let byMeShare = makeShare(id: "1")
        let withMeShare = makeShare(id: "2", byMe: false)
        let store = TestStore(initialState: SharedFeature.State(serverURL: serverURL)) {
            SharedFeature()
        } withDependencies: {
            $0.filesClient.mySharedLinks = { _ in [byMeShare] }
            $0.filesClient.sharedWithMeLinks = { _ in [withMeShare] }
            $0.filesClient.shareableUsers = { _ in [] }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.sharesResponse) {
            $0.isLoading = false
            $0.byMe = [byMeShare]
            $0.loadedSegments = [.byMe]
        }
        await store.receive(\.usersResponse)

        await store.send(.segmentChanged(.withMe)) {
            $0.segment = .withMe
            $0.isLoading = true
        }
        await store.receive(\.sharesResponse) {
            $0.isLoading = false
            $0.withMe = [withMeShare]
            $0.loadedSegments = [.byMe, .withMe]
        }

        // Already loaded — TestStore would flag any unexpected reload effect/action here.
        await store.send(.segmentChanged(.byMe)) { $0.segment = .byMe }
    }

    @Test
    func editTappedPresentsTheSheetSeededFromTheShareAndAnUpdateSwapsTheRow() async {
        let share = makeShare(id: "s1")
        var state = SharedFeature.State(serverURL: serverURL)
        state.byMe = [share]
        state.loadedSegments = [.byMe]
        let store = TestStore(initialState: state) { SharedFeature() }
        store.exhaustivity = .off

        await store.send(.editTapped(share))
        #expect(store.state.editSheet?.share == share)

        let updated = Share(
            id: "s1", shareToken: share.shareToken, ownerId: "me",
            sourcePath: "Documents/Report.pdf", isDirectory: false,
            accessMode: .readwrite, sharingType: .anyone, hasPassword: true,
            expiresAt: nil, label: "Q3 Report", createdAt: share.createdAt, updatedAt: Date()
        )
        await store.send(.editSheet(.presented(.delegate(.updated(updated)))))
        #expect(store.state.byMe[id: "s1"] == updated)
        #expect(store.state.editSheet == nil)
    }

    @Test
    func deleteFlowRemovesTheShareFromByMe() async {
        let share = makeShare()
        var state = SharedFeature.State(serverURL: serverURL)
        state.byMe = [share]
        state.loadedSegments = [.byMe]

        let store = TestStore(initialState: state) {
            SharedFeature()
        } withDependencies: {
            $0.filesClient.deleteShareLink = { _, _ in }
        }

        await store.send(.deleteTapped(share)) { $0.deleteConfirmationShare = share }
        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationShare = nil
            $0.deletingIDs = [share.id]
        }
        await store.receive(\.deleteResponse) {
            $0.deletingIDs = []
            $0.byMe = []
        }
    }

    @Test
    func aBumpedRevisionReloadsTheCurrentSegment() async {
        let first = makeShare(id: "1")
        let second = makeShare(id: "2")
        var state = SharedFeature.State(serverURL: serverURL)
        state.byMe = [first]
        state.loadedSegments = [.byMe]

        let store = TestStore(initialState: state) {
            SharedFeature()
        } withDependencies: {
            $0.filesClient.mySharedLinks = { _ in [first, second] }
        }

        await store.send(.externalRevisionChanged) {
            $0.loadedSegments = []
            $0.isLoading = true
        }
        await store.receive(\.sharesResponse) {
            $0.isLoading = false
            $0.byMe = [first, second]
            $0.loadedSegments = [.byMe]
        }
    }

    @Test
    func sortOptionAndDirectionReorderTheList() async {
        let alpha = Share(
            id: "a", shareToken: "a", ownerId: "me", sourcePath: "Alpha", sourceName: nil,
            isDirectory: true, accessMode: .readonly, sharingType: .anyone, hasPassword: false,
            label: "Alpha", createdAt: Date(timeIntervalSince1970: 100), updatedAt: Date()
        )
        let zulu = Share(
            id: "z", shareToken: "z", ownerId: "me", sourcePath: "Zulu", sourceName: nil,
            isDirectory: true, accessMode: .readonly, sharingType: .anyone, hasPassword: false,
            label: "Zulu", createdAt: Date(timeIntervalSince1970: 200), updatedAt: Date()
        )
        var state = SharedFeature.State(serverURL: serverURL)
        state.byMe = [alpha, zulu]

        let store = TestStore(initialState: state) { SharedFeature() }

        await store.send(.sortOptionChanged(.name)) { $0.sortOption = .name }
        await store.send(.sortDirectionChanged(.ascending)) { $0.sortDirection = .ascending }
        #expect(store.state.displayedShares.map(\.id) == ["a", "z"])

        await store.send(.sortDirectionChanged(.descending)) { $0.sortDirection = .descending }
        #expect(store.state.displayedShares.map(\.id) == ["z", "a"])
    }

    // MARK: Error paths

    @Test
    func aLoadFailureSurfacesAReadableMessage() async {
        let store = TestStore(initialState: SharedFeature.State(serverURL: serverURL)) {
            SharedFeature()
        } withDependencies: {
            $0.filesClient.mySharedLinks = { _ in throw FilesClientError.sessionExpired }
            $0.filesClient.shareableUsers = { _ in [] }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.sharesResponse) {
            $0.isLoading = false
            $0.errorMessage = FilesClientError.sessionExpired.userMessage
        }
        await store.receive(\.usersResponse)
    }

    @Test
    func deleteCancelledClearsTheConfirmation() async {
        let share = makeShare()
        var state = SharedFeature.State(serverURL: serverURL)
        state.byMe = [share]

        let store = TestStore(initialState: state) { SharedFeature() }

        await store.send(.deleteTapped(share)) { $0.deleteConfirmationShare = share }
        await store.send(.deleteCancelled) { $0.deleteConfirmationShare = nil }
    }

    @Test
    func aFailedDeleteKeepsTheShareAndShowsAnError() async {
        let share = makeShare()
        var state = SharedFeature.State(serverURL: serverURL)
        state.byMe = [share]
        state.deleteConfirmationShare = share

        let store = TestStore(initialState: state) {
            SharedFeature()
        } withDependencies: {
            $0.filesClient.deleteShareLink = { _, _ in throw FilesClientError.server(statusCode: 500) }
        }

        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationShare = nil
            $0.deletingIDs = [share.id]
        }
        await store.receive(\.deleteResponse) {
            $0.deletingIDs = []
            $0.actionErrorMessage = FilesClientError.server(statusCode: 500).userMessage
        }
        #expect(store.state.byMe == [share])
    }
}
