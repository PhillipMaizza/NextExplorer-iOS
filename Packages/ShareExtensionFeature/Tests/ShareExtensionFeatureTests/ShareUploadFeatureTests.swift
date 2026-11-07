import AuthClient
import ComposableArchitecture
import CoreModels
import Foundation
@testable import ShareExtensionFeature
import ShareUploads
import Testing

@MainActor
struct ShareUploadFeatureTests {
    private let credentials = SessionCredentials.preview

    private func store(
        count: Int = 3,
        credentials: SessionCredentials? = .preview,
        defaults: UploadDefaults = UploadDefaults(),
        uploaded: LockIsolated<(String, Int)?> = LockIsolated(nil),
        clock: TestClock<Duration> = TestClock()
    ) -> TestStoreOf<ShareUploadFeature> {
        let store = TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { count }
            $0.sharedItems.upload = { _, destination, onPrepared in
                onPrepared(count)
                uploaded.setValue((destination, count))
                return count
            }
            $0.authClient.restoreSession = { credentials }
            $0.authClient.me = { _ in User(id: "1", username: "phillip", email: nil, roles: []) }
            $0.uploadDefaults = .inMemory(credentials.map { [$0.accountID: defaults] } ?? [:])
            $0.continuousClock = clock
        }
        store.exhaustivity = .off
        return store
    }

    @Test
    func startsInTheDefaultFolderAndWaitsForUpload() async {
        let uploaded = LockIsolated<(String, Int)?>(nil)
        let store = store(defaults: UploadDefaults(folderPath: "Photos"), uploaded: uploaded)

        await store.send(.onAppear)
        await store.receive(\.sessionLoaded) {
            $0.phase = .checking
            $0.destination = "Photos"
        }
        #expect(!store.state.canUpload, "no upload before the server has answered")
        await store.receive(\.connectionChecked) {
            $0.phase = .ready
        }
        await store.finish()
        #expect(uploaded.value == nil, "Upload Without Asking is off, so it waits for the tap")
        #expect(store.state.canUpload)
    }

    @Test
    func uploadsStraightAwayWhenTheDefaultFolderSaysSo() async {
        let uploaded = LockIsolated<(String, Int)?>(nil)
        let clock = TestClock()
        let store = store(defaults: UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true), uploaded: uploaded, clock: clock)

        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        await store.receive(\.uploadTapped)
        await store.receive(\.uploadResponse.success) {
            $0.phase = .started
        }
        await clock.advance(by: .seconds(2))
        await store.receive(\.delegate.close)
        #expect(uploaded.value?.0 == "Photos")
        #expect(uploaded.value?.1 == 3)
    }

    @Test
    func noFolderMeansNoUploadUntilOneIsChosen() async {
        let uploaded = LockIsolated<(String, Int)?>(nil)
        let store = store(uploaded: uploaded)

        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        #expect(!store.state.canUpload)
        await store.send(.uploadTapped)
        #expect(uploaded.value == nil)

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
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded) {
            $0.phase = .signedOut
        }
    }

    @Test
    func anExpiredSessionShowsSignedOutBeforeAFolderIsPicked() async {
        let store = TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { 1 }
            $0.authClient.restoreSession = { .preview }
            $0.authClient.me = { _ in throw AuthClientError.sessionExpired }
            $0.uploadDefaults = .inMemory()
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked) {
            $0.phase = .signedOut
        }
    }

    @Test
    func nothingSharedThatCanBeUploaded() async {
        let store = store(count: 0)
        await store.send(.onAppear) {
            $0.phase = .nothingToUpload
        }
    }

    @Test
    func aFailedPreparationSaysSoAndSendsNothing() async {
        let store = TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { 2 }
            $0.sharedItems.upload = { _, _, _ in throw CocoaError(.fileReadUnknown) }
            $0.authClient.restoreSession = { .preview }
            $0.authClient.me = { _ in User(id: "1", username: "phillip", email: nil, roles: []) }
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos")])
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        await store.send(.uploadTapped) {
            $0.phase = .preparing
        }
        await store.receive(\.uploadResponse.failure) {
            $0.phase = .failed
        }
    }

    @Test
    func cancellingBeforeTheUploadStartsClosesWithoutCompleting() async {
        let store = store()
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        await store.send(.cancelTapped)
        await store.receive(\.delegate.close)
        #expect(store.state.phase == .ready)
    }

    @Test(arguments: [
        (AuthClientError.clientCertificateRequired, ShareUploadFeature.Phase.certificateRequired),
        (AuthClientError.clientCertificateRejected, ShareUploadFeature.Phase.certificateRejected),
    ])
    func aCertificateProblemStopsBeforeAnythingIsSent(error: AuthClientError, phase: ShareUploadFeature.Phase) async {
        let uploaded = LockIsolated<(String, Int)?>(nil)
        let store = TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { 1 }
            $0.sharedItems.upload = { _, destination, _ in
                uploaded.setValue((destination, 1))
                return 1
            }
            $0.authClient.restoreSession = { .preview }
            $0.authClient.me = { _ in throw error }
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true)])
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked) {
            $0.phase = phase
        }
        await store.finish()
        #expect(uploaded.value == nil, "even Upload Without Asking sends nothing")
    }

    @Test
    func offlineStillUploadsWithoutAsking() async {
        let uploaded = LockIsolated<(String, Int)?>(nil)
        let store = TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { 1 }
            $0.sharedItems.upload = { _, destination, _ in
                uploaded.setValue((destination, 1))
                return 1
            }
            $0.authClient.restoreSession = { .preview }
            $0.authClient.me = { _ in throw AuthClientError.network("offline") }
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true)])
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        await store.receive(\.uploadTapped)
        await store.receive(\.uploadResponse.success)
        #expect(uploaded.value?.0 == "Photos", "the background upload waits for the network")
    }

    @Test
    func uploadIsIgnoredWhileTheServerIsBeingChecked() async {
        let uploaded = LockIsolated<(String, Int)?>(nil)
        let serverClock = TestClock()
        let store = TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { 1 }
            $0.sharedItems.upload = { _, destination, _ in
                uploaded.setValue((destination, 1))
                return 1
            }
            $0.authClient.restoreSession = { .preview }
            $0.authClient.me = { _ in
                try await serverClock.sleep(for: .seconds(1))
                throw AuthClientError.clientCertificateRequired
            }
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos")])
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.send(.uploadTapped)
        #expect(store.state.phase == .checking)
        await serverClock.advance(by: .seconds(1))
        await store.receive(\.connectionChecked) {
            $0.phase = .certificateRequired
        }
        #expect(uploaded.value == nil)
    }
}
