import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct CreateShareLinkFeatureTests {
    private let serverURL = URL(string: "https://cloud.example.com")!
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func makeState() -> CreateShareLinkFeature.State {
        CreateShareLinkFeature.State(
            serverURL: serverURL,
            itemName: "Report.pdf",
            itemPath: "Documents",
            isDirectory: false,
            now: now
        )
    }

    private func makeCreated(target: ShareTarget = .anyone) -> CreatedShare {
        CreatedShare(
            share: Share(
                id: "s1", shareToken: "TOK123", ownerId: "me",
                sourcePath: "Documents/Report.pdf", isDirectory: false,
                accessMode: .readonly, sharingType: target, hasPassword: false,
                createdAt: now, updatedAt: now
            ),
            shareUrl: URL(string: "https://cloud.example.com/share/TOK123")!,
            directFileUrl: URL(string: "https://cloud.example.com/api/share/TOK123/file")!
        )
    }

    // MARK: Happy path

    @Test
    func labelDefaultsToTheItemName() {
        #expect(makeState().label == "Report.pdf")
        #expect(makeState().sourcePath == "Documents/Report.pdf")
    }

    @Test
    func creatingASharePutsTheResultIntoTheCreatedPhase() async {
        let created = makeCreated()
        let store = TestStore(initialState: makeState()) {
            CreateShareLinkFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.createShareLink = { url, request in
                #expect(url == self.serverURL)
                #expect(request.sourcePath == "Documents/Report.pdf")
                #expect(request.accessMode == .readonly)
                return created
            }
        }

        await store.send(.accessModeChanged(.readonly))
        await store.send(.createTapped) { $0.isCreating = true }
        await store.receive(\.createResponse.success) {
            $0.isCreating = false
            $0.createdShare = created
        }
    }

    @Test
    func fieldChangesUpdateState() async {
        let store = TestStore(initialState: makeState()) { CreateShareLinkFeature() }

        await store.send(.labelChanged("Bills")) { $0.label = "Bills" }
        await store.send(.accessModeChanged(.readwrite)) { $0.accessMode = .readwrite }
        await store.send(.passwordEnabledChanged(true)) { $0.isPasswordEnabled = true }
        await store.send(.passwordChanged("hunter2")) { $0.password = "hunter2" }
        await store.send(.expiryEnabledChanged(true)) { $0.isExpiryEnabled = true }
        await store.send(.directLinkModeChanged(.raw)) { $0.directLinkMode = .raw }
    }

    // MARK: Error / guard paths

    @Test
    func aPastExpirationDateIsRejectedBeforeAnyRequest() async {
        var state = makeState()
        state.isExpiryEnabled = true
        state.expiresAt = now.addingTimeInterval(-3600)

        let store = TestStore(initialState: state) {
            CreateShareLinkFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.createTapped) {
            $0.errorMessage = "Pick an expiration date in the future."
        }
    }

    @Test
    func choosingSpecificUsersBlocksCreation() async {
        let store = TestStore(initialState: makeState()) {
            CreateShareLinkFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.targetChanged(.users)) { $0.target = .users }
        #expect(store.state.isCreateEnabled == false)
        // No effect, no state change.
        await store.send(.createTapped)
    }

    @Test
    func aServerFailureSurfacesAReadableMessage() async {
        let store = TestStore(initialState: makeState()) {
            CreateShareLinkFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.createShareLink = { _, _ in throw FilesClientError.server(statusCode: 400) }
        }

        await store.send(.createTapped) { $0.isCreating = true }
        await store.receive(\.createResponse.failure) {
            $0.isCreating = false
            $0.errorMessage = FilesClientError.server(statusCode: 400).userMessage
        }
    }

    @Test
    func directLinkAppendsTheModeQuery() {
        var state = makeState()
        state.createdShare = makeCreated()
        state.directLinkMode = .download
        #expect(state.directLink?.absoluteString == "https://cloud.example.com/api/share/TOK123/file?mode=download")
        state.directLinkMode = .auto
        #expect(state.directLink?.absoluteString == "https://cloud.example.com/api/share/TOK123/file")
    }
}
