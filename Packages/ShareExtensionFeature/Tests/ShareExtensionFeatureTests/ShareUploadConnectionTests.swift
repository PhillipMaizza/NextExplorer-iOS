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

/// Connection check, certificate problems and account switching. Nested in `ShareUploadFeatureTests` so it inherits
/// `.serialized` with every other share upload suite.
extension ShareUploadFeatureTests {
    @MainActor
    @Suite(.isolatedDependencies)
    struct ShareUploadConnectionTests: ShareUploadHarness {
        /// Two signed in accounts: the first uploads without asking from "Photos", the second has its
        /// own folder and waits for a tap. `browse` answers for whichever account asks.
        private func twoAccountStore(
            calls: Calls = Calls(),
            browse: @escaping @Sendable (URL, String) async throws -> BrowseResult
        ) -> Store {
            let cookies = HTTPCookieStorage
                .sharedCookieStorage(forGroupContainerIdentifier: "share-tests-\(TestID.name())")
            cookies.cookieAcceptPolicy = .always
            return TestStore(initialState: ShareUploadFeature.State()) {
                ShareUploadFeature()
            } withDependencies: {
                $0.sharedItems.count = { 1 }
                $0.sharedItems.prepare = { _, destination, indexes, _ in
                    calls.record(indexes: indexes, folder: destination)
                    return PreparationReport(stagedCount: 1, failures: [])
                }
                $0.sharedItems.start = {
                    calls.record("start")
                    return 1
                }
                $0.sharedItems.discard = { calls.record("discard") }
                $0.authClient.loadSession = { .preview }
                $0.authClient.listSessions = { [.preview, .previewSecond] }
                $0.authClient.me = { _ in Self.user }
                $0.filesClient.browse = browse
                $0.uploadDefaults = .inMemory([
                    SessionCredentials.preview.accountID: UploadDefaults(
                        folderPath: TestFolder.photos,
                        shouldUploadWithoutAsking: true
                    ),
                    SessionCredentials.previewSecond.accountID: UploadDefaults(folderPath: Constants.familyFolder),
                ])
                $0.cookieStorage = cookies
            }
        }

        @Test(arguments: [
            (AuthClientError.clientCertificateRequired, ShareUploadFeature.Phase.certificateRequired),
            (AuthClientError.clientCertificateRejected, ShareUploadFeature.Phase.certificateRejected),
        ])
        func aCertificateProblemStopsBeforeAnythingIsSent(
            error: AuthClientError,
            phase: ShareUploadFeature.Phase
        ) async {
            let calls = Calls()
            let store = TestStore(initialState: ShareUploadFeature.State()) {
                ShareUploadFeature()
            } withDependencies: {
                $0.sharedItems.count = { 1 }
                $0.sharedItems.prepare = { _, destination, _, _ in
                    calls.record(indexes: nil, folder: destination)
                    return PreparationReport(stagedCount: 1, failures: [])
                }
                $0.authClient.loadSession = { .preview }
                $0.authClient.listSessions = { [.preview] }
                $0.authClient.me = { _ in throw error }
                $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(
                    folderPath: TestFolder.photos,
                    shouldUploadWithoutAsking: true
                )])
            }
            await store.send(.onAppear) { $0.itemCount = 1 }
            await store.receive(\.accountsLoaded) { $0.accounts = [.preview] }
            await store.receive(\.sessionLoaded) {
                $0.credentials = .preview
                $0.destination = TestFolder.photos
                $0.shouldUploadWithoutAsking = true
                $0.phase = .checking
            }
            await store.receive(\.connectionChecked) { $0.phase = phase }
            await store.finish()
            #expect(calls.all.isEmpty, "even Upload Without Asking sends nothing")
            #expect(store.state.primaryAction(canOpenApp: true) == .openApp)
        }

        @Test
        func tryAgainAfterACertificateProblemChecksTheConnectionAgain() async {
            let error = LockIsolated<AuthClientError?>(.clientCertificateRequired)
            let store = TestStore(initialState: ShareUploadFeature.State()) {
                ShareUploadFeature()
            } withDependencies: {
                $0.sharedItems.count = { 1 }
                $0.authClient.loadSession = { .preview }
                $0.authClient.listSessions = { [.preview] }
                $0.authClient.me = { _ in
                    if let failure = error.value {
                        throw failure
                    }
                    return Self.user
                }
                $0.uploadDefaults = .inMemory()
            }
            await store.send(.onAppear) { $0.itemCount = 1 }
            await store.receive(\.accountsLoaded) { $0.accounts = [.preview] }
            await store.receive(\.sessionLoaded) {
                $0.credentials = .preview
                $0.phase = .checking
            }
            await store.receive(\.connectionChecked) { $0.phase = .certificateRequired }
            error.setValue(nil)
            await store.send(.retryTapped) { $0.phase = .checking }
            await store.receive(\.connectionChecked) { $0.phase = .ready }
        }

        @Test
        func aConnectionResultForAnotherAccountIsDroppedWhateverItSays() async {
            var state = ShareUploadFeature.State()
            state.phase = .checking
            state.credentials = .previewSecond
            state.destination = Constants.familyFolder
            let store = TestStore(initialState: state) { ShareUploadFeature() }
            let stale = SessionCredentials.preview.accountID

            for check in [
                ShareUploadFeature.ConnectionCheck.usable, .signedOut, .certificateRequired, .certificateRejected,
            ] {
                await store.send(.connectionChecked(accountID: stale, check))
            }
            #expect(store.state.phase == .checking, "the old account's answer never settles the new account's check")

            await store.send(.connectionChecked(accountID: SessionCredentials.previewSecond.accountID, .signedOut)) {
                $0.phase = .signedOut
            }
        }

        @Test
        func offlineStillUploadsWithoutAsking() async {
            let calls = Calls()
            let store = TestStore(initialState: ShareUploadFeature.State()) {
                ShareUploadFeature()
            } withDependencies: {
                $0.sharedItems.count = { 1 }
                $0.sharedItems.prepare = { _, destination, indexes, _ in
                    calls.record(indexes: indexes, folder: destination)
                    return PreparationReport(stagedCount: 1, failures: [])
                }
                $0.sharedItems.start = { 1 }
                $0.authClient.loadSession = { .preview }
                $0.authClient.listSessions = { [.preview] }
                $0.authClient.me = { _ in throw AuthClientError.network(TestFailure.offline) }
                $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
                $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(
                    folderPath: TestFolder.photos,
                    shouldUploadWithoutAsking: true
                )])
                $0.continuousClock = ImmediateClock()
            }
            await store.send(.onAppear) { $0.itemCount = 1 }
            await store.receive(\.accountsLoaded) { $0.accounts = [.preview] }
            await store.receive(\.sessionLoaded) {
                $0.credentials = .preview
                $0.destination = TestFolder.photos
                $0.shouldUploadWithoutAsking = true
                $0.phase = .checking
            }
            await store.receive(\.connectionChecked)
            await store.receive(\.defaultFolderChecked) { $0.phase = .ready }
            await store.receive(\.uploadTapped) {
                $0.phase = .preparing
                $0.preparingTotal = 1
            }
            await store.receive(\.preparationFinished) {
                $0.stagedCount = 1
                $0.phase = .handingOff
            }
            await store.receive(\.uploadResponse.success) { $0.phase = .started }
            await store.receive(.delegate(.close(completed: true)))
            #expect(calls.folders == [TestFolder.photos], "the background upload waits for the network")
        }

        @Test
        func uploadIsIgnoredWhileTheServerIsBeingChecked() async {
            let calls = Calls()
            let gate = AsyncGate()
            let store = TestStore(initialState: ShareUploadFeature.State()) {
                ShareUploadFeature()
            } withDependencies: {
                $0.sharedItems.count = { 1 }
                $0.sharedItems.prepare = { _, destination, indexes, _ in
                    calls.record(indexes: indexes, folder: destination)
                    return PreparationReport(stagedCount: 1, failures: [])
                }
                $0.authClient.loadSession = { .preview }
                $0.authClient.listSessions = { [.preview] }
                $0.authClient.me = { _ in
                    try await gate.wait()
                    throw AuthClientError.clientCertificateRequired
                }
                $0
                    .uploadDefaults =
                    .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: TestFolder.photos)])
            }
            await store.send(.onAppear) { $0.itemCount = 1 }
            await store.receive(\.accountsLoaded) { $0.accounts = [.preview] }
            await store.receive(\.sessionLoaded) {
                $0.credentials = .preview
                $0.destination = TestFolder.photos
                $0.phase = .checking
            }
            await store.send(.uploadTapped)
            #expect(store.state.phase == .checking)
            gate.open()
            await store.receive(\.connectionChecked) { $0.phase = .certificateRequired }
            #expect(calls.all.isEmpty)
        }

        @Test
        func anotherAccountCanBeChosenWithItsOwnFolder() async {
            let cookies = HTTPCookieStorage
                .sharedCookieStorage(forGroupContainerIdentifier: "share-tests-\(TestID.name())")
            cookies.cookieAcceptPolicy = .always
            let store = TestStore(initialState: ShareUploadFeature.State()) {
                ShareUploadFeature()
            } withDependencies: {
                $0.sharedItems.count = { 1 }
                $0.authClient.loadSession = { .preview }
                $0.authClient.listSessions = { [.preview, .previewSecond] }
                $0.authClient.me = { _ in Self.user }
                $0.uploadDefaults = .inMemory([
                    SessionCredentials.preview.accountID: UploadDefaults(folderPath: TestFolder.photos),
                    SessionCredentials.previewSecond.accountID: UploadDefaults(
                        folderPath: Constants.familyFolder,
                        shouldUploadWithoutAsking: true
                    ),
                ])
                $0.cookieStorage = cookies
            }
            await store.send(.onAppear) { $0.itemCount = 1 }
            await store.receive(\.accountsLoaded) { $0.accounts = [.preview, .previewSecond] }
            await store.receive(\.sessionLoaded) {
                $0.credentials = .preview
                $0.destination = TestFolder.photos
                $0.phase = .checking
            }
            await store.receive(\.connectionChecked) { $0.phase = .ready }
            #expect(store.state.canChooseAccount)

            await store.send(.accountSelected(SessionCredentials.previewSecond.accountID)) {
                $0.credentials = .previewSecond
                $0.destination = Constants.familyFolder
                $0.phase = .checking
            }
            await store.receive(\.connectionChecked) { $0.phase = .ready }
            #expect(!store.state.shouldUploadWithoutAsking, "choosing an account never uploads on its own")
            #expect(cookies.cookies(for: SessionCredentials.previewSecond.serverBaseURL)?.first?.value == "preview")
        }

        @Test
        func oneAccountHasNoPicker() async {
            let store = store(count: 1)
            await store.send(.onAppear) { $0.itemCount = 1 }
            await store.receive(\.accountsLoaded) { $0.accounts = [credentials] }
            await store.receive(\.sessionLoaded) {
                $0.credentials = credentials
                $0.phase = .checking
            }
            await store.receive(\.connectionChecked) { $0.phase = .ready }
            #expect(!store.state.canChooseAccount)
            await store.send(.accountSelected(TestUser.someoneElse))
            #expect(store.state.credentials == .preview)
        }

        @Test
        func pickingAnotherAccountWhileTheFolderIsBeingCheckedNeverUploadsToIt() async {
            let calls = Calls()
            let gate = AsyncGate()
            let store = twoAccountStore(calls: calls) { _, _ in
                try await gate.wait()
                return Self.listing()
            }
            await store.send(.onAppear) { $0.itemCount = 1 }
            await store.receive(\.accountsLoaded) { $0.accounts = [.preview, .previewSecond] }
            await store.receive(\.sessionLoaded) {
                $0.credentials = .preview
                $0.destination = TestFolder.photos
                $0.shouldUploadWithoutAsking = true
                $0.phase = .checking
            }
            await store.receive(\.connectionChecked)

            await store.send(.accountSelected(SessionCredentials.previewSecond.accountID)) {
                $0.credentials = .previewSecond
                $0.destination = Constants.familyFolder
                $0.shouldUploadWithoutAsking = false
            }
            gate.open()
            await store.receive(\.connectionChecked) { $0.phase = .ready }
            await store.finish()

            #expect(calls.all.isEmpty, "the first account's folder result must not start an upload to the second")
            #expect(store.state.phase == .ready)
            #expect(store.state.credentials == .previewSecond)
            #expect(store.state.destination == Constants.familyFolder)
        }

        @Test
        func aFolderResultForAnotherAccountIsDroppedWhateverItSays() async {
            var state = ShareUploadFeature.State()
            state.phase = .checking
            state.credentials = .previewSecond
            state.destination = Constants.familyFolder
            let checking = TestStore(initialState: state) { ShareUploadFeature() }

            await checking.send(.defaultFolderChecked(accountID: SessionCredentials.preview.accountID, .usable))
            await checking.send(.defaultFolderChecked(accountID: SessionCredentials.preview.accountID, .unavailable))
            await checking.send(.defaultFolderChecked(accountID: SessionCredentials.preview.accountID, .signedOut))
            #expect(
                checking.state.destination == Constants.familyFolder,
                "another account's missing folder never wipes this one's"
            )
            #expect(checking.state.folderPicker == nil)
            #expect(checking.state.phase == .checking)

            await checking.send(.defaultFolderChecked(
                accountID: SessionCredentials.previewSecond.accountID,
                .signedOut
            )) {
                $0.phase = .signedOut
            }
        }
    }
}

private enum Constants {
    static let familyFolder = "Family"
}
