import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
import NetworkClient
@testable import ShareExtensionFeature
import ShareUploads
import Testing
import TestUtils

/// Opening the sheet: session and account loading, default folder and automatic upload. Nested in `ShareUploadFeatureTests` so it inherits `.serialized` with every other share upload suite.
extension ShareUploadFeatureTests {
    @MainActor
    @Suite(.isolatedDependencies)
    struct ShareUploadStartupTests: ShareUploadHarness {
        @Test
        func startsInTheDefaultFolderAndWaitsForUpload() async {
            let calls = Calls()
            let store = store(defaults: UploadDefaults(folderPath: "Photos"), calls: calls)

            await store.send(.onAppear) { $0.itemCount = 3 }
            await store.receive(\.accountsLoaded) { $0.accounts = [credentials] }
            await store.receive(\.sessionLoaded) {
                $0.credentials = credentials
                $0.destination = "Photos"
                $0.phase = .checking
            }
            #expect(!store.state.canUpload, "no upload before the server has answered")
            await store.receive(\.connectionChecked) { $0.phase = .ready }
            await store.finish()
            #expect(calls.all.isEmpty, "Upload Without Asking is off, so it waits for the tap")
            #expect(store.state.canUpload)
        }

        @Test
        func uploadsStraightAwayWhenTheDefaultFolderSaysSo() async {
            let calls = Calls()
            let clock = TestClock()
            let store = store(defaults: UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true), calls: calls, clock: clock)

            await startAutomatic(store)
            await store.receive(\.defaultFolderChecked) { $0.phase = .ready }
            await store.receive(\.uploadTapped) {
                $0.phase = .preparing
                $0.preparingTotal = 3
            }
            await store.receive(\.preparationFinished) {
                $0.stagedCount = 3
                $0.phase = .handingOff
            }
            await store.receive(\.uploadResponse.success) { $0.phase = .started }
            await clock.advance(by: .seconds(2))
            await store.receive(.delegate(.close(completed: true)))
            #expect(calls.all == ["prepare", "start"])
            #expect(calls.folders == ["Photos"])
        }

        @Test
        func noFolderMeansNoUploadUntilOneIsChosen() async {
            let calls = Calls()
            let store = store(calls: calls)

            await becomeReady(store)
            #expect(!store.state.canUpload)
            await store.send(.uploadTapped)
            #expect(calls.all.isEmpty)

            await store.send(.chooseFolderTapped) {
                $0.folderPicker = .init(serverURL: credentials.serverBaseURL, uploadStartingAt: "")
            }
            await store.send(.folderPicker(.presented(.delegate(.confirmed(destination: "Docs"))))) {
                $0.destination = "Docs"
                $0.folderPicker = nil
            }
            #expect(store.state.canUpload)
        }

        @Test
        func signedOutWhenNoAccountIsSignedIn() async {
            let store = store(credentials: nil)
            await store.send(.onAppear) { $0.itemCount = 3 }
            await store.receive(\.accountsLoaded)
            await store.receive(\.sessionLoaded) { $0.phase = .signedOut }
        }

        @Test
        func anUnreadableKeychainIsNotTheSameAsSignedOut() async {
            let announcements = LockIsolated<[String]>([])
            let store = TestStore(initialState: ShareUploadFeature.State()) {
                ShareUploadFeature()
            } withDependencies: {
                $0.sharedItems.count = { 1 }
                $0.authClient.loadSession = { throw AuthClientError.keychain("errSecInteractionNotAllowed") }
                $0.shareAccessibility = ShareAccessibilityClient(
                    isAssistiveTechnologyRunning: { false },
                    announce: { message in announcements.withValue { $0.append(message) } }
                )
            }
            await store.send(.onAppear) { $0.itemCount = 1 }
            await store.receive(\.sessionUnreadable) { $0.phase = .sessionUnreadable }
            await store.finish()
            #expect(store.state.credentials == nil)
            #expect(announcements.value == [L10n.ShareUpload.sessionUnreadable])
        }

        @Test
        func tryAgainAfterAnUnreadableSessionReadsItAgain() async {
            let isReadable = LockIsolated(false)
            let store = TestStore(initialState: ShareUploadFeature.State()) {
                ShareUploadFeature()
            } withDependencies: {
                $0.sharedItems.count = { 1 }
                $0.authClient.loadSession = {
                    guard isReadable.value else { throw AuthClientError.keychain("locked") }
                    return .preview
                }
                $0.authClient.listSessions = { [.preview] }
                $0.authClient.me = { _ in Self.user }
                $0.uploadDefaults = .inMemory()
            }
            await store.send(.onAppear) { $0.itemCount = 1 }
            await store.receive(\.sessionUnreadable) { $0.phase = .sessionUnreadable }
            isReadable.setValue(true)

            await store.send(.retryTapped) { $0.phase = .loading }
            await store.receive(\.accountsLoaded) { $0.accounts = [.preview] }
            await store.receive(\.sessionLoaded) {
                $0.credentials = .preview
                $0.phase = .checking
            }
            await store.receive(\.connectionChecked) { $0.phase = .ready }
        }

        @Test
        func anExpiredSessionShowsSignedOutBeforeAFolderIsPicked() async {
            let store = TestStore(initialState: ShareUploadFeature.State()) {
                ShareUploadFeature()
            } withDependencies: {
                $0.sharedItems.count = { 1 }
                $0.authClient.loadSession = { .preview }
                $0.authClient.listSessions = { [.preview] }
                $0.authClient.me = { _ in throw AuthClientError.sessionExpired }
                $0.uploadDefaults = .inMemory()
            }
            await store.send(.onAppear) { $0.itemCount = 1 }
            await store.receive(\.accountsLoaded) { $0.accounts = [.preview] }
            await store.receive(\.sessionLoaded) {
                $0.credentials = .preview
                $0.phase = .checking
            }
            await store.receive(\.connectionChecked) { $0.phase = .signedOut }
            #expect(store.state.primaryAction(canOpenApp: true) == .openApp)
        }

        @Test
        func livePhotosAreCountedForTheSummaryNote() async {
            let store = TestStore(initialState: ShareUploadFeature.State()) {
                ShareUploadFeature()
            } withDependencies: {
                $0.sharedItems.count = { 4 }
                $0.sharedItems.livePhotoCount = { 2 }
                $0.authClient.loadSession = { nil }
                $0.authClient.listSessions = { [] }
            }
            await store.send(.onAppear) {
                $0.itemCount = 4
                $0.livePhotoCount = 2
            }
            await store.receive(\.accountsLoaded)
            await store.receive(\.sessionLoaded) { $0.phase = .signedOut }
        }

        @Test
        func nothingSharedThatCanBeUploaded() async {
            let store = store(count: 0)
            await store.send(.onAppear) { $0.phase = .nothingToUpload }
            #expect(store.state.primaryAction(canOpenApp: true) == nil)
            #expect(store.state.secondaryAction(canOpenApp: true) == nil)
        }
    }
}
