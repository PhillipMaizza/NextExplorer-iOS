import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import NetworkClient
@testable import ShareExtensionFeature
import ShareUploads
import Testing

@MainActor
struct ShareUploadFeatureTests {
    private let credentials = SessionCredentials.preview

    /// What a store's fake extension did: the batch calls it saw, in order.
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        private var indexLists: [[Int]?] = []
        private var uploadedFolders: [String] = []

        var all: [String] {
            lock.withLock { entries }
        }

        var preparedIndexes: [[Int]?] {
            lock.withLock { indexLists }
        }

        var folders: [String] {
            lock.withLock { uploadedFolders }
        }

        func record(_ name: String) {
            lock.withLock { entries.append(name) }
        }

        func record(indexes: [Int]?, folder: String) {
            lock.withLock {
                entries.append("prepare")
                indexLists.append(indexes)
                uploadedFolders.append(folder)
            }
        }
    }

    private nonisolated static func listing(canUpload: Bool = true) -> BrowseResult {
        BrowseResult(
            items: [],
            access: FileAccess(
                canRead: true, canWrite: canUpload, canUpload: canUpload, canDelete: false,
                canShare: false, canDownload: true
            ),
            path: "Photos"
        )
    }

    private func store(
        count: Int = 3,
        credentials: SessionCredentials? = .preview,
        defaults: UploadDefaults = UploadDefaults(),
        calls: Calls = Calls(),
        report: PreparationReport? = nil,
        browse: (@Sendable (URL, String) async throws -> BrowseResult)? = nil,
        clock: TestClock<Duration> = TestClock(),
        isAssistive: Bool = false,
        announcements: LockIsolated<[String]> = LockIsolated([])
    ) -> TestStoreOf<ShareUploadFeature> {
        let store = TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { count }
            $0.sharedItems.prepare = { _, destination, indexes, onProgress in
                calls.record(indexes: indexes, folder: destination)
                onProgress(PreparationProgress(completed: count))
                return report ?? PreparationReport(stagedCount: count, failures: [])
            }
            $0.sharedItems.start = {
                calls.record("start")
                return report?.stagedCount ?? count
            }
            $0.sharedItems.discard = { calls.record("discard") }
            $0.authClient.loadSession = { credentials }
            $0.authClient.listSessions = { credentials.map { [$0] } ?? [] }
            $0.authClient.me = { _ in User(id: "1", username: "phillip", email: nil, roles: []) }
            $0.filesClient.browse = browse ?? { _, _ in Self.listing() }
            $0.uploadDefaults = .inMemory(credentials.map { [$0.accountID: defaults] } ?? [:])
            $0.continuousClock = clock
            $0.shareAccessibility = ShareAccessibilityClient(
                isAssistiveTechnologyRunning: { isAssistive },
                announce: { message in announcements.withValue { $0.append(message) } }
            )
        }
        store.exhaustivity = .off
        return store
    }

    private func becomeReady(_ store: TestStoreOf<ShareUploadFeature>) async {
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
    }

    // MARK: Starting up

    @Test
    func startsInTheDefaultFolderAndWaitsForUpload() async {
        let calls = Calls()
        let store = store(defaults: UploadDefaults(folderPath: "Photos"), calls: calls)

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
        #expect(calls.all.isEmpty, "Upload Without Asking is off, so it waits for the tap")
        #expect(store.state.canUpload)
    }

    @Test
    func uploadsStraightAwayWhenTheDefaultFolderSaysSo() async {
        let calls = Calls()
        let clock = TestClock()
        let store = store(defaults: UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true), calls: calls, clock: clock)

        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        await store.receive(\.defaultFolderChecked)
        await store.receive(\.uploadTapped)
        await store.receive(\.preparationFinished)
        await store.receive(\.uploadResponse.success) {
            $0.phase = .started
        }
        await clock.advance(by: .seconds(2))
        await store.receive(\.delegate.close)
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
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded) {
            $0.phase = .signedOut
        }
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
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.sessionUnreadable) {
            $0.phase = .sessionUnreadable
        }
        #expect(store.state.credentials == nil)
        #expect(store.state.shouldOfferOpeningTheApp)
        #expect(store.state.canRetry)
        #expect(announcements.value.count == 1)
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
            $0.authClient.me = { _ in User(id: "1", username: "phillip", email: nil, roles: []) }
            $0.uploadDefaults = .inMemory()
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.sessionUnreadable)
        isReadable.setValue(true)

        await store.send(.retryTapped) {
            $0.phase = .loading
        }
        await store.receive(\.sessionLoaded) {
            $0.phase = .checking
        }
        await store.receive(\.connectionChecked) {
            $0.phase = .ready
        }
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
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked) {
            $0.phase = .signedOut
        }
        #expect(store.state.canRetry)
        #expect(store.state.shouldOfferOpeningTheApp)
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
        store.exhaustivity = .off
        await store.send(.onAppear) {
            $0.itemCount = 4
            $0.livePhotoCount = 2
        }
        await store.receive(\.sessionLoaded)
    }

    @Test
    func nothingSharedThatCanBeUploaded() async {
        let store = store(count: 0)
        await store.send(.onAppear) {
            $0.phase = .nothingToUpload
        }
        #expect(!store.state.canRetry)
    }

    // MARK: Preparing

    @Test
    func aSuccessfulPassStartsTheBatch() async {
        let calls = Calls()
        let store = store(defaults: UploadDefaults(folderPath: "Photos"), calls: calls)
        await becomeReady(store)

        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 3
        }
        await store.receive(\.preparationFinished)
        await store.receive(\.uploadResponse.success) {
            $0.phase = .started
        }
        #expect(calls.all == ["prepare", "start"])
    }

    @Test
    func oneUnreadableItemDoesNotDiscardTheRest() async {
        let calls = Calls()
        let failures = [ItemFailure(index: 1, name: "IMG_0042.MOV", cause: .cannotRead)]
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos"),
            calls: calls,
            report: PreparationReport(stagedCount: 2, failures: failures)
        )
        await becomeReady(store)

        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished) {
            $0.phase = .partiallyPrepared
            $0.stagedCount = 2
            $0.failures = failures
        }
        #expect(calls.all == ["prepare"], "nothing is sent and nothing is discarded while the user decides")
        #expect(store.state.failures.map(\.name) == ["IMG_0042.MOV"], "the file is named")
        #expect(store.state.canRetry)

        await store.send(.uploadReadyTapped) {
            $0.phase = .preparing
        }
        await store.receive(\.uploadResponse.success) {
            $0.phase = .started
        }
        #expect(calls.all == ["prepare", "start"])
    }

    @Test
    func retryingPreparesOnlyTheFailedItems() async {
        let calls = Calls()
        let failures = [
            ItemFailure(index: 1, name: "a.mov", cause: .cannotRead),
            ItemFailure(index: 4, name: "b.pdf", cause: .notEnoughSpace),
        ]
        let store = store(
            count: 6,
            defaults: UploadDefaults(folderPath: "Photos"),
            calls: calls,
            report: PreparationReport(stagedCount: 4, failures: failures)
        )
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished)
        #expect(store.state.phase == .partiallyPrepared)

        await store.send(.retryTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 2
            $0.failures = []
        }
        await store.receive(\.preparationFinished)
        #expect(calls.preparedIndexes.count == 2)
        #expect(calls.preparedIndexes[0] == nil)
        #expect(calls.preparedIndexes[1] == [1, 4])
    }

    @Test
    func aRetryThatSucceedsStartsEverythingStaged() async {
        let calls = Calls()
        let passes = LockIsolated(0)
        let store = TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { 3 }
            $0.sharedItems.prepare = { _, _, _, _ in
                let pass = passes.withValue { value -> Int in
                    value += 1
                    return value
                }
                calls.record("prepare")
                return pass == 1
                    ? PreparationReport(stagedCount: 2, failures: [ItemFailure(index: 2, name: "c.heic", cause: .other)])
                    : PreparationReport(stagedCount: 3, failures: [])
            }
            $0.sharedItems.start = {
                calls.record("start")
                return 3
            }
            $0.sharedItems.discard = { calls.record("discard") }
            $0.authClient.loadSession = { .preview }
            $0.authClient.listSessions = { [.preview] }
            $0.authClient.me = { _ in User(id: "1", username: "phillip", email: nil, roles: []) }
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos")])
            $0.continuousClock = TestClock()
        }
        store.exhaustivity = .off
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished)
        await store.send(.retryTapped)
        await store.receive(\.preparationFinished)
        await store.receive(\.uploadResponse.success) {
            $0.phase = .started
        }
        #expect(calls.all == ["prepare", "prepare", "start"])
    }

    @Test
    func whenEveryItemFailsThePhaseIsFailedAndNamesThem() async {
        let failures = [
            ItemFailure(index: 0, name: "one.pdf", cause: .cannotRead),
            ItemFailure(index: 1, name: "two.pdf", cause: .notEnoughSpace),
        ]
        let calls = Calls()
        let store = store(
            count: 2,
            defaults: UploadDefaults(folderPath: "Photos"),
            calls: calls,
            report: PreparationReport(stagedCount: 0, failures: failures)
        )
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished) {
            $0.phase = .failed
            $0.failures = failures
        }
        #expect(store.state.failures.map(\.cause) == [.cannotRead, .notEnoughSpace])
        #expect(!calls.all.contains("start"))
    }

    @Test
    func aWholePassFailureDiscardsTheBatchAndRetriesFromScratch() async {
        let calls = Calls()
        let shouldFail = LockIsolated(true)
        let store = TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { 2 }
            $0.sharedItems.prepare = { _, _, indexes, _ in
                calls.record(indexes: indexes, folder: "Photos")
                if shouldFail.value {
                    throw CocoaError(.fileWriteUnknown)
                }
                return PreparationReport(stagedCount: 2, failures: [])
            }
            $0.sharedItems.start = { 2 }
            $0.sharedItems.discard = { calls.record("discard") }
            $0.authClient.loadSession = { .preview }
            $0.authClient.listSessions = { [.preview] }
            $0.authClient.me = { _ in User(id: "1", username: "phillip", email: nil, roles: []) }
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos")])
            $0.continuousClock = TestClock()
        }
        store.exhaustivity = .off
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished.failure) {
            $0.phase = .failed
        }
        #expect(store.state.failures.isEmpty)
        #expect(store.state.canRetry)

        shouldFail.setValue(false)
        await store.send(.retryTapped)
        await store.receive(\.preparationFinished.success)
        await store.receive(\.uploadResponse.success) {
            $0.phase = .started
        }
        #expect(calls.preparedIndexes.last == .some(nil), "no named failures: every item is read again")
        #expect(calls.all.contains("discard"))
    }

    @Test
    func aBatchWithNothingInItIsNothingToUpload() async {
        let calls = Calls()
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos"),
            calls: calls,
            report: PreparationReport(stagedCount: 0, failures: [])
        )
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished) {
            $0.phase = .nothingToUpload
        }
        await store.finish()
        #expect(calls.all == ["prepare", "discard"])
    }

    @Test
    func progressOnlyMovesForward() async {
        var state = ShareUploadFeature.State()
        state.phase = .preparing
        state.preparingTotal = 4
        let progressStore = TestStore(initialState: state) {
            ShareUploadFeature()
        }
        progressStore.exhaustivity = .off
        await progressStore.send(.progressed(PreparationProgress(completed: 2, fraction: 0.5)))
        await progressStore.send(.progressed(PreparationProgress(completed: 1, fraction: 0.9)))
        #expect(progressStore.state.progress == PreparationProgress(completed: 2, fraction: 0.5), "a late older update never rewinds")
        #expect(progressStore.state.preparationFraction == 0.625)
        await progressStore.send(.progressed(PreparationProgress(completed: 4, fraction: 0)))
        #expect(progressStore.state.preparationFraction == 1)
    }

    @Test
    func theFractionHandlesAnEmptyPass() {
        var state = ShareUploadFeature.State()
        #expect(state.preparationFraction == 0)
        state.preparingTotal = 2
        state.progress = PreparationProgress(completed: 5, fraction: 1)
        #expect(state.preparationFraction == 1, "never above full")
    }

    // MARK: Cancelling and closing

    @Test
    func cancellingBeforeAnythingIsStagedClosesWithoutDiscarding() async {
        let calls = Calls()
        let store = store(calls: calls)
        await becomeReady(store)
        await store.send(.cancelTapped)
        await store.receive(\.delegate.close)
        #expect(store.state.phase == .ready)
        #expect(calls.all.isEmpty)
    }

    @Test
    func cancellingMidPreparationStopsTheLoadAndDiscardsTheHalfStagedBatch() async {
        let calls = Calls()
        let wasCancelled = LockIsolated(false)
        let isInside = LockIsolated(false)
        let store = TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { 2 }
            $0.sharedItems.prepare = { _, _, _, _ in
                isInside.setValue(true)
                do {
                    try await Task.sleep(for: .seconds(60))
                } catch {
                    wasCancelled.setValue(true)
                    throw error
                }
                return PreparationReport(stagedCount: 2, failures: [])
            }
            $0.sharedItems.discard = { calls.record("discard") }
            $0.authClient.loadSession = { .preview }
            $0.authClient.listSessions = { [.preview] }
            $0.authClient.me = { _ in User(id: "1", username: "phillip", email: nil, roles: []) }
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos")])
            $0.continuousClock = TestClock()
        }
        store.exhaustivity = .off
        await becomeReady(store)
        await store.send(.uploadTapped)
        while !isInside.value {
            await Task.yield()
        }

        await store.send(.cancelTapped)
        await store.receive(\.delegate.close)
        await store.finish()
        #expect(wasCancelled.value, "the in flight preparation was cancelled, not left running")
        #expect(calls.all == ["discard"], "the half staged batch is dropped at once")
    }

    @Test
    func cancellingWhileTheUserChoosesBetweenReadyAndFailedDiscardsTheBatch() async {
        let calls = Calls()
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos"),
            calls: calls,
            report: PreparationReport(stagedCount: 1, failures: [ItemFailure(index: 1, name: "x", cause: .other)])
        )
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished)
        await store.send(.cancelTapped)
        await store.receive(\.delegate.close)
        await store.finish()
        #expect(calls.all == ["prepare", "discard"])
    }

    @Test
    func theSystemClosingTheSheetMidPreparationDiscardsTheBatch() async {
        let calls = Calls()
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos"),
            calls: calls,
            report: PreparationReport(stagedCount: 1, failures: [ItemFailure(index: 1, name: "x", cause: .other)])
        )
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished)

        await store.send(.viewDisappeared)
        await store.finish()
        #expect(calls.all == ["prepare", "discard"])
    }

    @Test
    func theSheetDisappearingAfterTheUploadStartedLeavesItAlone() async {
        let calls = Calls()
        let store = store(defaults: UploadDefaults(folderPath: "Photos"), calls: calls)
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished)
        await store.receive(\.uploadResponse.success)

        await store.send(.viewDisappeared)
        await store.finish()
        #expect(calls.all == ["prepare", "start"], "once started the uploads belong to the system")
    }

    @Test
    func closingAfterTheUploadStartedReportsCompleted() async {
        let store = store(defaults: UploadDefaults(folderPath: "Photos"))
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished)
        await store.receive(\.uploadResponse.success)
        await store.send(.cancelTapped)
        await store.receive(.delegate(.close(completed: true)))
    }

    // MARK: Connection and certificates

    @Test(arguments: [
        (AuthClientError.clientCertificateRequired, ShareUploadFeature.Phase.certificateRequired),
        (AuthClientError.clientCertificateRejected, ShareUploadFeature.Phase.certificateRejected),
    ])
    func aCertificateProblemStopsBeforeAnythingIsSent(error: AuthClientError, phase: ShareUploadFeature.Phase) async {
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
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true)])
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked) {
            $0.phase = phase
        }
        await store.finish()
        #expect(calls.all.isEmpty, "even Upload Without Asking sends nothing")
        #expect(store.state.canRetry)
        #expect(store.state.shouldOfferOpeningTheApp)
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
                return User(id: "1", username: "phillip", email: nil, roles: [])
            }
            $0.uploadDefaults = .inMemory()
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked) {
            $0.phase = .certificateRequired
        }
        error.setValue(nil)
        await store.send(.retryTapped) {
            $0.phase = .checking
        }
        await store.receive(\.connectionChecked) {
            $0.phase = .ready
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
            $0.authClient.me = { _ in throw AuthClientError.network("offline") }
            $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true)])
            $0.continuousClock = ImmediateClock()
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        await store.receive(\.defaultFolderChecked)
        await store.receive(\.uploadTapped)
        await store.receive(\.preparationFinished)
        await store.receive(\.uploadResponse.success)
        #expect(calls.folders == ["Photos"], "the background upload waits for the network")
    }

    @Test
    func uploadIsIgnoredWhileTheServerIsBeingChecked() async {
        let calls = Calls()
        let serverClock = TestClock()
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
        #expect(calls.all.isEmpty)
    }

    // MARK: Stale default folder

    @Test
    func aMissingDefaultFolderFallsBackToTheFolderPickerWithAMessage() async {
        let calls = Calls()
        let store = store(
            defaults: UploadDefaults(folderPath: "Gone", shouldUploadWithoutAsking: true),
            calls: calls,
            browse: { _, _ in throw FilesClientError.server(statusCode: 404) }
        )
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        await store.receive(\.defaultFolderChecked) {
            $0.phase = .ready
            $0.destination = ""
            $0.shouldUploadWithoutAsking = false
            $0.notice = .defaultFolderUnavailable
            $0.folderPicker = .init(serverURL: credentials.serverBaseURL, uploadStartingAt: "")
        }
        await store.finish()
        #expect(calls.all.isEmpty, "nothing is uploaded to a folder that is gone")
        #expect(!store.state.canUpload)
    }

    @Test
    func aDefaultFolderTheAccountCanNoLongerUploadToIsTreatedAsGone() async {
        let store = store(
            defaults: UploadDefaults(folderPath: "ReadOnly", shouldUploadWithoutAsking: true),
            browse: { _, _ in Self.listing(canUpload: false) }
        )
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        await store.receive(\.defaultFolderChecked)
        #expect(store.state.notice == .defaultFolderUnavailable)
        #expect(store.state.folderPicker != nil)
    }

    @Test
    func choosingAnotherFolderClearsTheMessageAndAllowsTheUpload() async {
        let store = store(
            defaults: UploadDefaults(folderPath: "Gone", shouldUploadWithoutAsking: true),
            browse: { _, _ in throw FilesClientError.server(statusCode: 404) }
        )
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        await store.receive(\.defaultFolderChecked)

        await store.send(.folderPicker(.presented(.delegate(.confirmed(destination: "Docs"))))) {
            $0.destination = "Docs"
            $0.folderPicker = nil
            $0.notice = nil
        }
        #expect(store.state.canUpload)
    }

    @Test
    func theDefaultFolderIsCheckedOnceBeforeTheAutomaticUpload() async {
        let browsed = LockIsolated<[String]>([])
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos/2026", shouldUploadWithoutAsking: true),
            browse: { _, path in
                browsed.withValue { $0.append(path) }
                return Self.listing()
            }
        )
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        await store.receive(\.defaultFolderChecked)
        await store.receive(\.uploadTapped)
        await store.receive(\.preparationFinished)
        await store.receive(\.uploadResponse.success)
        #expect(browsed.value == ["Photos/2026"])
    }

    @Test
    func anExpiredSessionFoundWhileCheckingTheDefaultFolderShowsSignedOut() async {
        let calls = Calls()
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true),
            calls: calls,
            browse: { _, _ in throw FilesClientError.sessionExpired }
        )
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        await store.receive(\.defaultFolderChecked) {
            $0.phase = .signedOut
        }
        #expect(calls.all.isEmpty)
    }

    @Test
    func aFolderPathIsNotCheckedWhenTheUploadWaitsForATap() async {
        let browsed = LockIsolated(0)
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos"),
            browse: { _, _ in
                browsed.withValue { $0 += 1 }
                return Self.listing()
            }
        )
        await becomeReady(store)
        await store.finish()
        #expect(browsed.value == 0)
    }

    // MARK: Accounts

    @Test
    func anotherAccountCanBeChosenWithItsOwnFolder() async {
        let cookies = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "share-tests-\(UUID().uuidString)")
        cookies.cookieAcceptPolicy = .always
        let store = TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { 1 }
            $0.authClient.loadSession = { .preview }
            $0.authClient.listSessions = { [.preview, .previewSecond] }
            $0.authClient.me = { _ in User(id: "1", username: "phillip", email: nil, roles: []) }
            $0.uploadDefaults = .inMemory([
                SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos"),
                SessionCredentials.previewSecond.accountID: UploadDefaults(folderPath: "Family", shouldUploadWithoutAsking: true),
            ])
            $0.cookieStorage = cookies
        }
        store.exhaustivity = .off
        await store.send(.onAppear)
        await store.receive(\.accountsLoaded)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)
        #expect(store.state.canChooseAccount)

        await store.send(.accountSelected(SessionCredentials.previewSecond.accountID)) {
            $0.credentials = .previewSecond
            $0.destination = "Family"
            $0.phase = .checking
        }
        await store.receive(\.connectionChecked) {
            $0.phase = .ready
        }
        #expect(!store.state.shouldUploadWithoutAsking, "choosing an account never uploads on its own")
        #expect(cookies.cookies(for: SessionCredentials.previewSecond.serverBaseURL)?.first?.value == "preview")
    }

    @Test
    func oneAccountHasNoPicker() async {
        let store = store()
        await store.send(.onAppear)
        await store.receive(\.accountsLoaded)
        await store.receive(\.sessionLoaded)
        #expect(!store.state.canChooseAccount)
        await store.send(.accountSelected("someone else"))
        #expect(store.state.credentials == .preview)
    }

    // MARK: Switching accounts while the default folder is being checked

    /// Two signed in accounts: the first uploads without asking from "Photos", the second has its
    /// own folder and waits for a tap. `browse` answers for whichever account asks.
    private func twoAccountStore(
        calls: Calls = Calls(),
        browse: @escaping @Sendable (URL, String) async throws -> BrowseResult
    ) -> TestStoreOf<ShareUploadFeature> {
        let cookies = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "share-tests-\(UUID().uuidString)")
        cookies.cookieAcceptPolicy = .always
        let store = TestStore(initialState: ShareUploadFeature.State()) {
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
            $0.authClient.me = { _ in User(id: "1", username: "phillip", email: nil, roles: []) }
            $0.filesClient.browse = browse
            $0.uploadDefaults = .inMemory([
                SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true),
                SessionCredentials.previewSecond.accountID: UploadDefaults(folderPath: "Family"),
            ])
            $0.cookieStorage = cookies
        }
        store.exhaustivity = .off
        return store
    }

    @Test
    func pickingAnotherAccountWhileTheFolderIsBeingCheckedNeverUploadsToIt() async {
        let calls = Calls()
        let (gate, release) = AsyncStream.makeStream(of: Void.self)
        let store = twoAccountStore(calls: calls) { _, _ in
            for await _ in gate {
                break
            }
            return Self.listing()
        }
        await store.send(.onAppear)
        await store.receive(\.sessionLoaded)
        await store.receive(\.connectionChecked)

        await store.send(.accountSelected(SessionCredentials.previewSecond.accountID))
        release.yield()
        release.finish()
        await store.receive(\.connectionChecked)
        await store.finish()

        #expect(calls.all.isEmpty, "the first account's folder result must not start an upload to the second")
        #expect(store.state.phase == .ready)
        #expect(store.state.credentials == .previewSecond)
        #expect(store.state.destination == "Family")
    }

    @Test
    func aFolderResultForAnotherAccountIsDroppedWhateverItSays() async {
        var state = ShareUploadFeature.State()
        state.phase = .checking
        state.credentials = .previewSecond
        state.destination = "Family"
        let checking = TestStore(initialState: state) { ShareUploadFeature() }
        checking.exhaustivity = .on

        await checking.send(.defaultFolderChecked(accountID: SessionCredentials.preview.accountID, .usable))
        await checking.send(.defaultFolderChecked(accountID: SessionCredentials.preview.accountID, .unavailable))
        await checking.send(.defaultFolderChecked(accountID: SessionCredentials.preview.accountID, .signedOut))
        #expect(checking.state.destination == "Family", "another account's missing folder never wipes this one's")
        #expect(checking.state.folderPicker == nil)
        #expect(checking.state.phase == .checking)

        await checking.send(.defaultFolderChecked(accountID: SessionCredentials.previewSecond.accountID, .signedOut)) {
            $0.phase = .signedOut
        }
    }

    // MARK: The close timer

    @Test
    func cancellingAfterTheUploadStartedStopsTheCloseTimerSoTheSheetClosesOnce() async {
        let clock = TestClock()
        let store = store(defaults: UploadDefaults(folderPath: "Photos"), clock: clock)
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished)
        await store.receive(\.uploadResponse.success)
        store.exhaustivity = .on

        await store.send(.cancelTapped)
        await store.receive(.delegate(.close(completed: true)))
        await clock.advance(by: Self.longerThanAnyCloseDelay)
        await store.finish()
    }

    @Test
    func theSheetDisappearingAfterTheUploadStartedStopsTheCloseTimer() async {
        let clock = TestClock()
        let store = store(defaults: UploadDefaults(folderPath: "Photos"), clock: clock)
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished)
        await store.receive(\.uploadResponse.success)
        store.exhaustivity = .on

        await store.send(.viewDisappeared)
        await clock.advance(by: Self.longerThanAnyCloseDelay)
        await store.finish()
    }

    private static let longerThanAnyCloseDelay: Duration = .seconds(60)

    // MARK: Opening the app

    @Test
    func openNextExplorerAsksTheSystemToOpenTheApp() async {
        let opened = LockIsolated(0)
        var state = ShareUploadFeature.State()
        state.phase = .signedOut
        let store = TestStore(initialState: state) {
            ShareUploadFeature()
        } withDependencies: {
            $0.openApp = OpenAppClient(isAvailable: true) { opened.withValue { $0 += 1 } }
        }
        await store.send(.openAppTapped)
        await store.finish()
        #expect(opened.value == 1)
    }

    @Test(arguments: [
        (ShareUploadFeature.Phase.signedOut, true, true),
        (.sessionUnreadable, true, true),
        (.certificateRequired, true, true),
        (.certificateRejected, true, true),
        (.failed, false, true),
        (.partiallyPrepared, false, true),
        (.ready, false, false),
        (.checking, false, false),
        (.preparing, false, false),
        (.started, false, false),
        (.nothingToUpload, false, false),
        (.loading, false, false),
    ])
    func whichDeadEndsOfferWhat(phase: ShareUploadFeature.Phase, shouldOpen: Bool, canRetry: Bool) {
        var state = ShareUploadFeature.State()
        state.phase = phase
        #expect(state.shouldOfferOpeningTheApp == shouldOpen)
        #expect(state.canRetry == canRetry)
    }

    @Test
    func retryDoesNothingWhereItMakesNoSense() async {
        for phase in [ShareUploadFeature.Phase.ready, .started, .nothingToUpload, .preparing, .checking, .loading] {
            var state = ShareUploadFeature.State()
            state.phase = phase
            let store = TestStore(initialState: state) { ShareUploadFeature() }
            await store.send(.retryTapped)
        }
    }

    // MARK: Accessibility

    @Test
    func theResultIsAnnouncedAndTheSheetClosesAfterTheShortDelay() async {
        let announcements = LockIsolated<[String]>([])
        let clock = TestClock()
        let store = store(defaults: UploadDefaults(folderPath: "Photos"), clock: clock, announcements: announcements)
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished)
        await store.receive(\.uploadResponse.success)

        #expect(announcements.value.count == 1)
        await clock.advance(by: .seconds(1.5))
        await store.receive(\.delegate.close)
    }

    @Test
    func withVoiceOverTheSheetStaysOpenLongerThanTheShortDelay() async {
        let announcements = LockIsolated<[String]>([])
        let clock = TestClock()
        let store = store(defaults: UploadDefaults(folderPath: "Photos"), clock: clock, isAssistive: true, announcements: announcements)
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished)
        await store.receive(\.uploadResponse.success)

        await clock.advance(by: .seconds(2))
        #expect(store.state.phase == .started, "still open after the short delay")
        await clock.advance(by: .seconds(6))
        await store.receive(\.delegate.close)
        #expect(announcements.value.count == 1)
    }

    @Test
    func aFailureIsAnnouncedToo() async {
        let announcements = LockIsolated<[String]>([])
        let failures = [ItemFailure(index: 0, name: "x", cause: .cannotRead)]
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos"),
            report: PreparationReport(stagedCount: 1, failures: failures),
            announcements: announcements
        )
        await becomeReady(store)
        await store.send(.uploadTapped)
        await store.receive(\.preparationFinished)
        await store.finish()
        #expect(announcements.value.count == 1)
    }
}
