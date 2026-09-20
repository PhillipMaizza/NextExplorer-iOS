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
                #expect(url == serverURL)
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
            $0.$shareLinksRevision.withLock { $0 += 1 }
        }
    }

    @Test
    func fieldChangesUpdateState() async {
        let store = TestStore(initialState: makeState()) { CreateShareLinkFeature() }

        await store.send(.labelChanged("Bills")) { $0.label = "Bills" }
        await store.send(.accessModeChanged(.readwrite)) { $0.accessMode = .readwrite }
        await store.send(.passwordEnabledChanged(true)) { $0.isPasswordEnabled = true }
        await store.send(.passwordChanged("hunter2")) { $0.password = "hunter2" }
        await store.send(.expiryEnabledChanged(true)) {
            $0.isExpiryEnabled = true
            $0.hasTouchedExpiry = true
        }
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
            $0.errorMessage = L10n.CreateShare.errorPastExpiration
        }
    }

    @Test
    func passwordProtectionOnButBlankIsRejectedBeforeAnyRequest() async {
        var state = makeState()
        state.isPasswordEnabled = true
        state.password = ""

        let store = TestStore(initialState: state) {
            CreateShareLinkFeature()
        } withDependencies: {
            $0.date = .constant(now)
        }

        await store.send(.createTapped) {
            $0.errorMessage = L10n.CreateShare.errorPasswordRequired
        }
    }

    @Test
    func choosingSpecificUsersLoadsUsersAndBlocksCreationUntilOneIsPicked() async {
        let jamie = User(id: "u2", username: "jamie", email: "jamie@example.com", displayName: "Jamie")
        let store = TestStore(initialState: makeState()) {
            CreateShareLinkFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.shareableUsers = { _ in [jamie] }
        }

        await store.send(.targetChanged(.users)) {
            $0.target = .users
            $0.usersPhase = .loading
        }
        await store.receive(\.shareableUsersResponse.success) {
            $0.usersPhase = .loaded
            $0.shareableUsers = [jamie]
        }
        #expect(store.state.isCreateEnabled == false)
        // No effect, no state change while nothing is selected.
        await store.send(.createTapped)

        await store.send(.userToggled(jamie.id)) { $0.selectedUserIDs = [jamie.id] }
        #expect(store.state.isCreateEnabled == true)
    }

    @Test
    func specificUsersAreSentInTheCreateRequest() async {
        let jamie = User(id: "u2", username: "jamie", email: "jamie@example.com", displayName: "Jamie")
        let created = makeCreated(target: .users)
        var state = makeState()
        state.target = .users
        state.usersPhase = .loaded
        state.shareableUsers = [jamie]
        state.selectedUserIDs = [jamie.id]

        let store = TestStore(initialState: state) {
            CreateShareLinkFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.createShareLink = { _, request in
                #expect(request.target == .users)
                #expect(request.userIds == ["u2"])
                return created
            }
        }

        await store.send(.createTapped) { $0.isCreating = true }
        await store.receive(\.createResponse.success) {
            $0.isCreating = false
            $0.createdShare = created
            $0.$shareLinksRevision.withLock { $0 += 1 }
        }
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

    // MARK: Default expiration

    @Test
    func onAppearAppliesTheUsersDefaultShareExpiration() async {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let store = TestStore(initialState: makeState()) {
            CreateShareLinkFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.calendar = calendar
            $0.filesClient.fetchPreferences = { _ in
                UserPreferences(defaultShareExpiration: .init(value: 2, unit: .weeks))
            }
        }

        await store.send(.onAppear)
        await store.receive(\.preferencesResponse) {
            $0.isExpiryEnabled = true
            $0.expiresAt = now.addingTimeInterval(14 * 86_400)
        }
    }

    @Test
    func onAppearLeavesExpiryOffWhenTheUserHasNoDefault() async {
        let store = TestStore(initialState: makeState()) {
            CreateShareLinkFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.fetchPreferences = { _ in UserPreferences() }
        }

        await store.send(.onAppear)
        await store.receive(\.preferencesResponse)
        #expect(!store.state.isExpiryEnabled)
    }

    @Test
    func aLateArrivingDefaultDoesNotOverrideAManualExpiryChoice() async {
        let store = TestStore(initialState: makeState()) {
            CreateShareLinkFeature()
        } withDependencies: {
            $0.date = .constant(now)
            $0.filesClient.fetchPreferences = { _ in
                UserPreferences(defaultShareExpiration: .init(value: 1, unit: .months))
            }
        }

        await store.send(.expiryEnabledChanged(false)) {
            $0.isExpiryEnabled = false
            $0.hasTouchedExpiry = true
        }
        await store.send(.onAppear)
        await store.receive(\.preferencesResponse)
        #expect(!store.state.isExpiryEnabled)
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
