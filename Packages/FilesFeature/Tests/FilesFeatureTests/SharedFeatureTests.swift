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
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.sharesResponse) {
            $0.isLoading = false
            $0.byMe = [share]
            $0.loadedSegments = [.byMe]
        }
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
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.sharesResponse) {
            $0.isLoading = false
            $0.byMe = [byMeShare]
            $0.loadedSegments = [.byMe]
        }

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

    // MARK: Error paths

    @Test
    func aLoadFailureSurfacesAReadableMessage() async {
        let store = TestStore(initialState: SharedFeature.State(serverURL: serverURL)) {
            SharedFeature()
        } withDependencies: {
            $0.filesClient.mySharedLinks = { _ in throw FilesClientError.sessionExpired }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.sharesResponse) {
            $0.isLoading = false
            $0.errorMessage = FilesClientError.sessionExpired.userMessage
        }
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
            $0.errorMessage = FilesClientError.server(statusCode: 500).userMessage
        }
        #expect(store.state.byMe == [share])
    }
}
