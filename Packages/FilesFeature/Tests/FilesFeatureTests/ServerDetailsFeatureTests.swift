import ComposableArchitecture
import DependenciesTestSupport
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing

@Suite(.dependencies)
@MainActor
struct ServerDetailsFeatureTests {
    private let serverURL = URL(string: "https://cloud.example.com")!

    private func makeState(
        branding: Branding = Branding(appName: "Explorer", appLogoUrl: Branding.defaultLogoPath)
    ) -> ServerDetailsFeature.State {
        var state = ServerDetailsFeature.State(serverURL: serverURL, branding: branding)
        state.$sharedBranding.withLock { $0 = Branding() }
        return state
    }

    @Test
    func onAppearRefreshesBrandingAndFollowsTheUntouchedNameDraft() async {
        let fetched = Branding(appName: "Rivendell", appLogoUrl: "/static/logos/custom-logo.png")
        let store = TestStore(initialState: makeState()) {
            ServerDetailsFeature()
        } withDependencies: {
            $0.filesClient.fetchBranding = { _ in fetched }
        }

        await store.send(.onAppear)
        await store.receive(\.brandingResponse.success) {
            $0.branding = fetched
            $0.nameDraft = "Rivendell"
            $0.$sharedBranding.withLock { $0 = fetched }
        }
    }

    @Test
    func onAppearKeepsAnEditedNameDraftEvenWhenBrandingRefreshes() async {
        var state = makeState()
        state.nameDraft = "My Server"
        let fetched = Branding(appName: "Rivendell", appLogoUrl: Branding.defaultLogoPath)
        let store = TestStore(initialState: state) {
            ServerDetailsFeature()
        } withDependencies: {
            $0.filesClient.fetchBranding = { _ in fetched }
        }

        await store.send(.onAppear)
        await store.receive(\.brandingResponse.success) {
            $0.branding = fetched
            $0.$sharedBranding.withLock { $0 = fetched }
        }
        #expect(store.state.nameDraft == "My Server")
        #expect(store.state.isDirty)
    }

    @Test
    func nameChangesAreClampedToTheServerLimitAndMarkTheFormDirty() async {
        let store = TestStore(initialState: makeState()) { ServerDetailsFeature() }

        await store.send(.nameChanged("Rivendell")) {
            $0.nameDraft = "Rivendell"
        }
        #expect(store.state.isDirty)

        let long = String(repeating: "x", count: 150)
        await store.send(.nameChanged(long)) {
            $0.nameDraft = String(repeating: "x", count: ServerDetailsFeature.maxNameLength)
        }
    }

    @Test
    func aNameOnlyUpdateSkipsTheLogoUploadAndPublishesTheResult() async {
        var state = makeState()
        state.nameDraft = "Rivendell"
        let saved = Branding(appName: "Rivendell", appLogoUrl: Branding.defaultLogoPath)
        let store = TestStore(initialState: state) {
            ServerDetailsFeature()
        } withDependencies: {
            $0.filesClient.uploadServerLogo = { _, _ in
                Issue.record("logo upload should not run for a name-only change")
                return ""
            }
            $0.filesClient.updateBranding = { _, name, logoPath in
                #expect(name == "Rivendell")
                #expect(logoPath == Branding.defaultLogoPath)
                return saved
            }
        }

        await store.send(.updateTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) {
            $0.isSaving = false
            $0.branding = saved
            $0.nameDraft = "Rivendell"
            $0.$sharedBranding.withLock { $0 = saved }
        }
        await store.receive(\.delegate)
    }

    @Test
    func aPickedLogoIsUploadedThenSavedWithTheReturnedPath() async {
        var state = makeState()
        state.pendingLogoData = Data([0xFF, 0xD8, 0xFF])
        let saved = Branding(appName: "Explorer", appLogoUrl: "/static/logos/custom-logo.jpg")
        let store = TestStore(initialState: state) {
            ServerDetailsFeature()
        } withDependencies: {
            $0.filesClient.uploadServerLogo = { _, data in
                #expect(data == Data([0xFF, 0xD8, 0xFF]))
                return "/static/logos/custom-logo.jpg"
            }
            $0.filesClient.updateBranding = { _, _, logoPath in
                #expect(logoPath == "/static/logos/custom-logo.jpg")
                return saved
            }
        }

        await store.send(.updateTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) {
            $0.isSaving = false
            $0.branding = saved
            $0.pendingLogoData = nil
            $0.$sharedBranding.withLock { $0 = saved }
        }
        await store.receive(\.delegate)
    }

    @Test
    func aSaveFailureSurfacesAMessageAndLeavesTheSharedBrandingUntouched() async {
        var state = makeState()
        state.nameDraft = "Rivendell"
        let store = TestStore(initialState: state) {
            ServerDetailsFeature()
        } withDependencies: {
            $0.filesClient.updateBranding = { _, _, _ in throw FilesClientError.server(statusCode: 403) }
        }

        await store.send(.updateTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.failure) {
            $0.isSaving = false
            $0.errorMessage = FilesClientError.server(statusCode: 403).userMessage
        }
        #expect(store.state.sharedBranding == Branding())
    }

    @Test
    func clearingTheNameBlocksSavingAndFlagsAnError() async {
        var state = makeState(branding: Branding(appName: "Rivendell", appLogoUrl: Branding.defaultLogoPath))
        state.pendingLogoData = Data([0xFF, 0xD8, 0xFF]) // dirty, so only the name gates the save
        let store = TestStore(initialState: state) { ServerDetailsFeature() }

        await store.send(.nameChanged("   ")) {
            $0.nameDraft = "   "
        }
        #expect(store.state.nameError == .empty)
        #expect(store.state.isSaveEnabled == false)

        await store.send(.updateTapped) // guarded — no state change, no effect
    }

    @Test
    func logoPickFailedShowsTheTooLargeMessage() async {
        let store = TestStore(initialState: makeState()) { ServerDetailsFeature() }

        await store.send(.logoPickFailed) {
            $0.errorMessage = L10n.ServerDetails.logoErrorTooLarge
        }
    }
}
