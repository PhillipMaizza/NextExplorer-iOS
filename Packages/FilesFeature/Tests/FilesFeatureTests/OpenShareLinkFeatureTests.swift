import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct OpenShareLinkFeatureTests {
    private let serverURL = URL(string: "https://cloud.example.com")!

    // MARK: Token parsing

    @Test
    func tokenParsingAcceptsUrlsAndBareTokens() {
        #expect(OpenShareLinkFeature.token(from: "https://cloud.example.com/share/AbC123xyz0") == "AbC123xyz0")
        #expect(OpenShareLinkFeature.token(from: "https://cloud.example.com/share/AbC123xyz0?redirect=/x") == "AbC123xyz0")
        #expect(OpenShareLinkFeature.token(from: "  cloud.example.com/share/AbC123xyz0/  ") == "AbC123xyz0")
        #expect(OpenShareLinkFeature.token(from: "AbC123xyz0") == "AbC123xyz0")
        #expect(OpenShareLinkFeature.token(from: "tok_9-Xy") == "tok_9-Xy")
    }

    @Test
    func tokenParsingRejectsGarbage() {
        #expect(OpenShareLinkFeature.token(from: "") == nil)
        #expect(OpenShareLinkFeature.token(from: "   ") == nil)
        #expect(OpenShareLinkFeature.token(from: "short") == nil) // < 6 chars
        #expect(OpenShareLinkFeature.token(from: "has spaces here") == nil)
        #expect(OpenShareLinkFeature.token(from: "https://cloud.example.com/browse/Documents") == nil)
    }

    // MARK: Look up

    @Test
    func lookUpResolvesAFolderShareAndStoresIt() async {
        let info = ShareInfo(shareToken: "AbC123xyz0", label: "Q3 Report", isDirectory: true, sharingType: .anyone)
        var state = OpenShareLinkFeature.State(serverURL: serverURL)
        state.linkText = "https://cloud.example.com/share/AbC123xyz0"

        let store = TestStore(initialState: state) {
            OpenShareLinkFeature()
        } withDependencies: {
            $0.filesClient.resolveShareLink = { _, token in
                #expect(token == "AbC123xyz0")
                return info
            }
        }

        await store.send(.lookUpTapped) { $0.isResolving = true }
        await store.receive(\.infoResponse.success) {
            $0.isResolving = false
            $0.info = info
        }
        #expect(store.state.canOpen)
    }

    @Test
    func anExpiredShareBecomesAnErrorWithNothingToOpen() async {
        let info = ShareInfo(shareToken: "AbC123xyz0", isDirectory: true, sharingType: .anyone, isExpired: true)
        var state = OpenShareLinkFeature.State(serverURL: serverURL)
        state.linkText = "AbC123xyz0"

        let store = TestStore(initialState: state) {
            OpenShareLinkFeature()
        } withDependencies: {
            $0.filesClient.resolveShareLink = { _, _ in info }
        }

        await store.send(.lookUpTapped) { $0.isResolving = true }
        await store.receive(\.infoResponse.success) {
            $0.isResolving = false
            $0.errorMessage = L10n.OpenShareLink.errorExpired
        }
        #expect(!store.state.canOpen)
    }

    @Test
    func aMissingShareSurfacesTheNotFoundMessage() async {
        var state = OpenShareLinkFeature.State(serverURL: serverURL)
        state.linkText = "https://cloud.example.com/share/nope00"

        let store = TestStore(initialState: state) {
            OpenShareLinkFeature()
        } withDependencies: {
            $0.filesClient.resolveShareLink = { _, _ in throw FilesClientError.server(statusCode: 404) }
        }

        await store.send(.lookUpTapped) { $0.isResolving = true }
        await store.receive(\.infoResponse.failure) {
            $0.isResolving = false
            $0.errorMessage = L10n.OpenShareLink.errorNotFound
        }
    }

    @Test
    func lookUpWithAnUnparseableLinkIsAValidationError() async {
        var state = OpenShareLinkFeature.State(serverURL: serverURL)
        state.linkText = "not a real link"
        let store = TestStore(initialState: state) { OpenShareLinkFeature() }

        await store.send(.lookUpTapped) {
            $0.errorMessage = L10n.OpenShareLink.errorInvalidLink
        }
    }

    // MARK: Open

    @Test
    func openTappedEmitsTheLogicalPathDelegate() async {
        let info = ShareInfo(shareToken: "AbC123xyz0", label: "Q3 Report", isDirectory: true, sharingType: .anyone)
        var state = OpenShareLinkFeature.State(serverURL: serverURL)
        state.info = info
        let store = TestStore(initialState: state) { OpenShareLinkFeature() }

        await store.send(.openTapped)
        await store.receive(.delegate(.open(path: "share/AbC123xyz0", title: "Q3 Report")))
    }

    @Test
    func openTappedFallsBackToAGenericTitleWhenTheShareIsUnlabelled() async {
        let info = ShareInfo(shareToken: "AbC123xyz0", isDirectory: false, sharingType: .anyone)
        var state = OpenShareLinkFeature.State(serverURL: serverURL)
        state.info = info
        let store = TestStore(initialState: state) { OpenShareLinkFeature() }

        await store.send(.openTapped)
        await store.receive(.delegate(.open(path: "share/AbC123xyz0", title: L10n.OpenShareLink.sharedFile)))
    }
}
