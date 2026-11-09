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

/// Serialized for the same reason as the login suites: ninety TestStore tests waiting at once starve
/// the executor that has to deliver the effect, and TCA's one second default timeout runs out.
@MainActor
@Suite(.serialized)
struct ShareUploadFeatureTests {
    private let credentials = SessionCredentials.preview
    private typealias Store = TestStoreOf<ShareUploadFeature>

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

    private nonisolated static let user = User(id: "1", username: "phillip", email: nil, roles: [])

    /// A store whose fake extension records what it is asked. Exhaustive: every state change and
    /// every received action is asserted.
    private func store(
        count: Int = 3,
        credentials: SessionCredentials? = .preview,
        defaults: UploadDefaults = UploadDefaults(),
        calls: Calls = Calls(),
        report: PreparationReport? = nil,
        browse: (@Sendable (URL, String) async throws -> BrowseResult)? = nil,
        clock: any Clock<Duration> = TestClock(),
        isAssistive: Bool = false,
        announcements: LockIsolated<[String]> = LockIsolated([])
    ) -> Store {
        TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { count }
            $0.sharedItems.prepare = { _, destination, indexes, _ in
                calls.record(indexes: indexes, folder: destination)
                return report ?? PreparationReport(stagedCount: count, failures: [])
            }
            $0.sharedItems.start = {
                calls.record("start")
                return report?.stagedCount ?? count
            }
            $0.sharedItems.discard = { calls.record("discard") }
            $0.authClient.loadSession = { credentials }
            $0.authClient.listSessions = { credentials.map { [$0] } ?? [] }
            $0.authClient.me = { _ in Self.user }
            $0.filesClient.browse = browse ?? { _, _ in Self.listing() }
            $0.uploadDefaults = .inMemory(credentials.map { [$0.accountID: defaults] } ?? [:])
            $0.continuousClock = clock
            $0.shareAccessibility = ShareAccessibilityClient(
                isAssistiveTechnologyRunning: { isAssistive },
                announce: { message in announcements.withValue { $0.append(message) } }
            )
        }
    }

    /// Opens the sheet and lets the connection check finish, ending ready for the user.
    private func becomeReady(_ store: Store, count: Int = 3, folder: String = "") async {
        await store.send(.onAppear) { $0.itemCount = count }
        await store.receive(\.accountsLoaded) { $0.accounts = [credentials] }
        await store.receive(\.sessionLoaded) {
            $0.credentials = credentials
            $0.destination = folder
            $0.phase = .checking
        }
        await store.receive(\.connectionChecked) { $0.phase = .ready }
    }

    /// Opens the sheet with Upload Without Asking on, up to the connection check that starts the
    /// default folder check.
    private func startAutomatic(_ store: Store, count: Int = 3, folder: String = "Photos") async {
        await store.send(.onAppear) { $0.itemCount = count }
        await store.receive(\.accountsLoaded) { $0.accounts = [credentials] }
        await store.receive(\.sessionLoaded) {
            $0.credentials = credentials
            $0.destination = folder
            $0.shouldUploadWithoutAsking = true
            $0.phase = .checking
        }
        await store.receive(\.connectionChecked)
    }

    /// Taps Upload on a ready sheet and lets a clean pass hand off, ending started.
    private func uploadCleanly(_ store: Store, count: Int = 3) async {
        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = count
        }
        await store.receive(\.preparationFinished) {
            $0.stagedCount = count
            $0.phase = .handingOff
        }
        await store.receive(\.uploadResponse.success) { $0.phase = .started }
    }

    // MARK: Starting up

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

    // MARK: Preparing

    @Test
    func aSuccessfulPassStartsTheBatch() async {
        let calls = Calls()
        let store = store(defaults: UploadDefaults(folderPath: "Photos"), calls: calls)
        await becomeReady(store, folder: "Photos")

        await uploadCleanly(store)

        #expect(calls.all == ["prepare", "start"])
        await store.send(.viewDisappeared)
    }

    @Test
    func theHandOffHasItsOwnPhaseSoClosingDoesNotCountAsHavingStagedFiles() async {
        let store = store(defaults: UploadDefaults(folderPath: "Photos"))
        await becomeReady(store, folder: "Photos")
        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 3
        }
        #expect(store.state.hasStagedFiles)
        await store.receive(\.preparationFinished) {
            $0.stagedCount = 3
            $0.phase = .handingOff
        }
        #expect(!store.state.hasStagedFiles, "the uploads may already be running")
        await store.receive(\.uploadResponse.success) { $0.phase = .started }
        await store.send(.viewDisappeared)
    }

    @Test
    func oneUnreadableItemDoesNotDiscardTheRest() async {
        let calls = Calls()
        let announcements = LockIsolated<[String]>([])
        let failures = [ItemFailure(index: 1, name: "IMG_0042.MOV", cause: .cannotRead)]
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos"),
            calls: calls,
            report: PreparationReport(stagedCount: 2, failures: failures),
            announcements: announcements
        )
        await becomeReady(store, folder: "Photos")

        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 3
        }
        await store.receive(\.preparationFinished) {
            $0.phase = .partiallyPrepared
            $0.stagedCount = 2
            $0.failures = failures
        }
        await store.finish()
        #expect(calls.all == ["prepare"], "nothing is sent and nothing is discarded while the user decides")
        #expect(store.state.failures.map(\.name) == ["IMG_0042.MOV"], "the file is named")
        #expect(announcements.value == [L10n.ShareUpload.failedItemsHeader])

        await store.send(.uploadReadyTapped) {
            $0.phase = .handingOff
            $0.progress = PreparationProgress(completed: 3)
        }
        await store.receive(\.uploadResponse.success) { $0.phase = .started }
        #expect(calls.all == ["prepare", "start"])
        await store.send(.viewDisappeared)
    }

    @Test
    func retryingPreparesOnlyTheFailedItems() async {
        let calls = Calls()
        let failures = [
            ItemFailure(index: 1, name: "a.mov", cause: .cannotRead),
            ItemFailure(index: 4, name: "b.pdf", cause: .notEnoughSpace),
        ]
        let report = PreparationReport(stagedCount: 4, failures: failures)
        let store = store(count: 6, defaults: UploadDefaults(folderPath: "Photos"), calls: calls, report: report)
        await becomeReady(store, count: 6, folder: "Photos")
        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 6
        }
        await store.receive(\.preparationFinished) {
            $0.phase = .partiallyPrepared
            $0.stagedCount = 4
            $0.failures = failures
        }

        await store.send(.retryTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 2
            $0.failures = []
        }
        await store.receive(\.preparationFinished) {
            $0.phase = .partiallyPrepared
            $0.failures = failures
        }
        #expect(calls.preparedIndexes.count == 2)
        #expect(calls.preparedIndexes[0] == nil)
        #expect(calls.preparedIndexes[1] == [1, 4])
    }

    @Test
    func aRetryThatSucceedsStartsEverythingStaged() async {
        let calls = Calls()
        let passes = LockIsolated(0)
        let failed = [ItemFailure(index: 2, name: "c.heic", cause: .other)]
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
                    ? PreparationReport(stagedCount: 2, failures: failed)
                    : PreparationReport(stagedCount: 3, failures: [])
            }
            $0.sharedItems.start = {
                calls.record("start")
                return 3
            }
            $0.sharedItems.discard = { calls.record("discard") }
            $0.authClient.loadSession = { .preview }
            $0.authClient.listSessions = { [.preview] }
            $0.authClient.me = { _ in Self.user }
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos")])
            $0.continuousClock = TestClock()
        }
        await becomeReady(store, folder: "Photos")
        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 3
        }
        await store.receive(\.preparationFinished) {
            $0.phase = .partiallyPrepared
            $0.stagedCount = 2
            $0.failures = failed
        }
        await store.send(.retryTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 1
            $0.failures = []
        }
        await store.receive(\.preparationFinished) {
            $0.stagedCount = 3
            $0.phase = .handingOff
        }
        await store.receive(\.uploadResponse.success) { $0.phase = .started }
        #expect(calls.all == ["prepare", "prepare", "start"])
        await store.send(.viewDisappeared)
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
        await becomeReady(store, count: 2, folder: "Photos")
        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 2
        }
        await store.receive(\.preparationFinished) {
            $0.phase = .failed
            $0.failures = failures
        }
        await store.finish()
        #expect(store.state.failures.map(\.cause) == [.cannotRead, .notEnoughSpace])
        #expect(!calls.all.contains("start"))
    }

    /// A store whose first pass throws `firstError` and whose later passes stage everything.
    private func failingFirstPassStore(calls: Calls, firstError: @escaping @Sendable () -> (any Error)?) -> Store {
        TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { 2 }
            $0.sharedItems.prepare = { _, _, indexes, _ in
                calls.record(indexes: indexes, folder: "Photos")
                if let error = firstError() {
                    throw error
                }
                return PreparationReport(stagedCount: 2, failures: [])
            }
            $0.sharedItems.start = {
                calls.record("start")
                return 2
            }
            $0.sharedItems.discard = { calls.record("discard") }
            $0.authClient.loadSession = { .preview }
            $0.authClient.listSessions = { [.preview] }
            $0.authClient.me = { _ in Self.user }
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos")])
            $0.continuousClock = TestClock()
        }
    }

    @Test
    func aWholePassFailureDiscardsTheBatchAndRetriesFromScratchInThatOrder() async {
        let calls = Calls()
        let shouldFail = LockIsolated(true)
        let store = failingFirstPassStore(calls: calls) { shouldFail.value ? CocoaError(.fileWriteUnknown) : nil }
        await becomeReady(store, count: 2, folder: "Photos")
        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 2
        }
        await store.receive(\.preparationFinished.failure) { $0.phase = .failed }
        await store.finish()
        #expect(store.state.failures.isEmpty)
        #expect(store.state.primaryAction(canOpenApp: false) == .retry)

        shouldFail.setValue(false)
        await store.send(.retryTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 2
        }
        await store.receive(\.preparationFinished.success) {
            $0.stagedCount = 2
            $0.phase = .handingOff
        }
        await store.receive(\.uploadResponse.success) { $0.phase = .started }
        #expect(calls.preparedIndexes.last == .some(nil), "no named failures: every item is read again")
        #expect(
            calls.all == ["prepare", "discard", "discard", "prepare", "start"],
            "the old batch is dropped before the new pass creates its own, never after"
        )
        await store.send(.viewDisappeared)
    }

    @Test
    func aPassThatGivesUpOnItsOwnIsAFailureNotAnEndlessPreparing() async {
        let calls = Calls()
        let store = failingFirstPassStore(calls: calls) { CancellationError() }
        await becomeReady(store, count: 2, folder: "Photos")

        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 2
        }
        await store.receive(\.preparationFinished.failure) { $0.phase = .failed }
        await store.finish()

        #expect(calls.all == ["prepare", "discard"])
    }

    @Test
    func aBatchWithNothingInItIsNothingToUpload() async {
        let calls = Calls()
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos"),
            calls: calls,
            report: PreparationReport(stagedCount: 0, failures: [])
        )
        await becomeReady(store, folder: "Photos")
        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 3
        }
        await store.receive(\.preparationFinished) { $0.phase = .nothingToUpload }
        await store.finish()
        #expect(calls.all == ["prepare", "discard"])
    }

    @Test
    func progressOnlyMovesForward() async {
        var state = ShareUploadFeature.State()
        state.phase = .preparing
        state.preparingTotal = 4
        let store = TestStore(initialState: state) { ShareUploadFeature() }

        await store.send(.progressed(PreparationProgress(completed: 2, fraction: 0.5))) {
            $0.progress = PreparationProgress(completed: 2, fraction: 0.5)
        }
        await store.send(.progressed(PreparationProgress(completed: 1, fraction: 0.9)))
        #expect(store.state.progress == PreparationProgress(completed: 2, fraction: 0.5), "a late older update never rewinds")
        #expect(store.state.preparationFraction == 0.625)
        await store.send(.progressed(PreparationProgress(completed: 4, fraction: 0))) {
            $0.progress = PreparationProgress(completed: 4, fraction: 0)
        }
        #expect(store.state.preparationFraction == 1)
    }

    @Test
    func theFractionHandlesAnEmptyPass() {
        var state = ShareUploadFeature.State()
        #expect(state.preparationFraction == 0)
        state.preparingTotal = 2
        state.progress = PreparationProgress(completed: 5, fraction: 1)
        #expect(state.preparationFraction == 1, "never above full")
    }

    @Test
    func theStepShownIsTheItemBeingReadAndNeverPastTheTotal() {
        var state = ShareUploadFeature.State()
        state.preparingTotal = 3
        #expect(state.preparingStep == 1)
        state.progress = PreparationProgress(completed: 1)
        #expect(state.preparingStep == 2)
        state.progress = PreparationProgress(completed: 3)
        #expect(state.preparingStep == 3, "the last item stays at 3 of 3")
        state.preparingTotal = 0
        state.progress = PreparationProgress()
        #expect(state.preparingStep == 0)
    }

    // MARK: Cancelling and closing

    @Test
    func cancellingBeforeAnythingIsStagedClosesWithoutDiscarding() async {
        let calls = Calls()
        let store = store(calls: calls)
        await becomeReady(store)
        await store.send(.cancelTapped)
        await store.receive(.delegate(.close(completed: false)))
        #expect(store.state.phase == .ready)
        #expect(calls.all.isEmpty)
    }

    @Test
    func cancellingMidPreparationStopsTheLoadAndDiscardsTheHalfStagedBatch() async {
        let calls = Calls()
        let wasCancelled = LockIsolated(false)
        let neverAdvanced = TestClock()
        let (entered, signalEntered) = AsyncStream.makeStream(of: Void.self)
        let store = TestStore(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.count = { 2 }
            $0.sharedItems.prepare = { _, _, _, _ in
                signalEntered.yield()
                do {
                    try await neverAdvanced.sleep(for: .seconds(1))
                } catch {
                    wasCancelled.setValue(true)
                    throw error
                }
                return PreparationReport(stagedCount: 2, failures: [])
            }
            $0.sharedItems.discard = { calls.record("discard") }
            $0.authClient.loadSession = { .preview }
            $0.authClient.listSessions = { [.preview] }
            $0.authClient.me = { _ in Self.user }
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos")])
            $0.continuousClock = TestClock()
        }
        await becomeReady(store, count: 2, folder: "Photos")
        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 2
        }
        var iterator = entered.makeAsyncIterator()
        await iterator.next()

        await store.send(.cancelTapped)
        await store.receive(.delegate(.close(completed: false)))
        await store.finish()
        #expect(wasCancelled.value, "the in flight preparation was cancelled, not left running")
        #expect(calls.all == ["discard"], "the half staged batch is dropped at once")
    }

    @Test
    func cancellingWhileTheUserChoosesBetweenReadyAndFailedDiscardsTheBatch() async {
        let calls = Calls()
        let failures = [ItemFailure(index: 1, name: "x", cause: .other)]
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos"),
            calls: calls,
            report: PreparationReport(stagedCount: 1, failures: failures)
        )
        await becomeReady(store, folder: "Photos")
        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 3
        }
        await store.receive(\.preparationFinished) {
            $0.phase = .partiallyPrepared
            $0.stagedCount = 1
            $0.failures = failures
        }
        await store.send(.cancelTapped)
        await store.receive(.delegate(.close(completed: false)))
        await store.finish()
        #expect(calls.all == ["prepare", "discard"])
    }

    @Test
    func theSystemClosingTheSheetWhileTheUserChoosesDiscardsTheBatch() async {
        let calls = Calls()
        let failures = [ItemFailure(index: 1, name: "x", cause: .other)]
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos"),
            calls: calls,
            report: PreparationReport(stagedCount: 1, failures: failures)
        )
        await becomeReady(store, folder: "Photos")
        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 3
        }
        await store.receive(\.preparationFinished) {
            $0.phase = .partiallyPrepared
            $0.stagedCount = 1
            $0.failures = failures
        }

        await store.send(.viewDisappeared)
        await store.finish()
        #expect(calls.all == ["prepare", "discard"])
    }

    private func handingOffStore(calls: Calls) -> Store {
        var state = ShareUploadFeature.State()
        state.phase = .handingOff
        state.credentials = .preview
        state.itemCount = 3
        state.stagedCount = 3
        state.preparingTotal = 3
        return TestStore(initialState: state) {
            ShareUploadFeature()
        } withDependencies: {
            $0.sharedItems.discard = { calls.record("discard") }
            $0.continuousClock = TestClock()
        }
    }

    @Test
    func closingTheSheetWhileTheUploadsAreBeingHandedOffNeitherDiscardsNorCloses() async {
        let calls = Calls()
        let store = handingOffStore(calls: calls)

        await store.send(.cancelTapped)
        await store.send(.viewDisappeared)
        await store.finish()

        #expect(calls.all.isEmpty, "the folder must not be deleted under uploads that may already be running")
        #expect(store.state.phase == .handingOff, "the hand off finishes and the sheet closes itself afterwards")
    }

    @Test
    func theHandOffResultStillLandsAfterAnIgnoredClose() async {
        let calls = Calls()
        let store = handingOffStore(calls: calls)
        await store.send(.cancelTapped)

        await store.send(.uploadResponse(.success(3))) { $0.phase = .started }
        await store.send(.viewDisappeared)

        #expect(calls.all.isEmpty)
    }

    @Test
    func aSecondTapDuringTheHandOffStartsNothing() async {
        let calls = Calls()
        let store = handingOffStore(calls: calls)

        await store.send(.uploadReadyTapped)
        await store.send(.uploadTapped)
        await store.send(.retryTapped)

        #expect(calls.all.isEmpty)
        #expect(store.state.phase == .handingOff)
    }

    @Test
    func aHandOffResultOutsideTheHandOffIsIgnored() async {
        for phase in [ShareUploadFeature.Phase.ready, .preparing, .failed, .started, .nothingToUpload] {
            var state = ShareUploadFeature.State()
            state.phase = phase
            let store = TestStore(initialState: state) { ShareUploadFeature() }
            await store.send(.uploadResponse(.success(2)))
            await store.send(.uploadResponse(.failure(.init())))
            #expect(store.state.phase == phase)
        }
    }

    @Test
    func aFailedHandOffIsAFailure() async {
        let calls = Calls()
        let announcements = LockIsolated<[String]>([])
        var state = ShareUploadFeature.State()
        state.phase = .handingOff
        let store = TestStore(initialState: state) {
            ShareUploadFeature()
        } withDependencies: {
            $0.shareAccessibility = ShareAccessibilityClient(
                isAssistiveTechnologyRunning: { false },
                announce: { message in announcements.withValue { $0.append(message) } }
            )
            $0.sharedItems.discard = { calls.record("discard") }
        }

        await store.send(.uploadResponse(.failure(.init()))) { $0.phase = .failed }
        await store.finish()

        #expect(announcements.value == [L10n.ShareUpload.failed])
        #expect(calls.all.isEmpty, "a failed start already removed its own batch")
    }

    @Test
    func theSheetDisappearingAfterTheUploadStartedLeavesItAlone() async {
        let calls = Calls()
        let store = store(defaults: UploadDefaults(folderPath: "Photos"), calls: calls)
        await becomeReady(store, folder: "Photos")
        await uploadCleanly(store)

        await store.send(.viewDisappeared)
        await store.finish()
        #expect(calls.all == ["prepare", "start"], "once started the uploads belong to the system")
    }

    @Test
    func closingAfterTheUploadStartedReportsCompleted() async {
        let store = store(defaults: UploadDefaults(folderPath: "Photos"))
        await becomeReady(store, folder: "Photos")
        await uploadCleanly(store)
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
        await store.send(.onAppear) { $0.itemCount = 1 }
        await store.receive(\.accountsLoaded) { $0.accounts = [.preview] }
        await store.receive(\.sessionLoaded) {
            $0.credentials = .preview
            $0.destination = "Photos"
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
        state.destination = "Family"
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
            $0.authClient.me = { _ in throw AuthClientError.network("offline") }
            $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
            $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true)])
            $0.continuousClock = ImmediateClock()
        }
        await store.send(.onAppear) { $0.itemCount = 1 }
        await store.receive(\.accountsLoaded) { $0.accounts = [.preview] }
        await store.receive(\.sessionLoaded) {
            $0.credentials = .preview
            $0.destination = "Photos"
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
        await store.send(.onAppear) { $0.itemCount = 1 }
        await store.receive(\.accountsLoaded) { $0.accounts = [.preview] }
        await store.receive(\.sessionLoaded) {
            $0.credentials = .preview
            $0.destination = "Photos"
            $0.phase = .checking
        }
        await store.send(.uploadTapped)
        #expect(store.state.phase == .checking)
        await serverClock.advance(by: .seconds(1))
        await store.receive(\.connectionChecked) { $0.phase = .certificateRequired }
        #expect(calls.all.isEmpty)
    }

    // MARK: Stale default folder

    private func folderGone(_ store: Store) async {
        await store.receive(\.defaultFolderChecked) {
            $0.phase = .ready
            $0.destination = ""
            $0.shouldUploadWithoutAsking = false
            $0.notice = .defaultFolderUnavailable
            $0.folderPicker = .init(serverURL: credentials.serverBaseURL, uploadStartingAt: "")
        }
    }

    @Test
    func aMissingDefaultFolderFallsBackToTheFolderPickerWithAMessage() async {
        let calls = Calls()
        let announcements = LockIsolated<[String]>([])
        let store = store(
            defaults: UploadDefaults(folderPath: "Gone", shouldUploadWithoutAsking: true),
            calls: calls,
            browse: { _, _ in throw FilesClientError.server(statusCode: 404) },
            announcements: announcements
        )
        await startAutomatic(store, folder: "Gone")
        await folderGone(store)
        await store.finish()
        #expect(calls.all.isEmpty, "nothing is uploaded to a folder that is gone")
        #expect(!store.state.canUpload)
        #expect(announcements.value == [L10n.ShareUpload.defaultFolderUnavailable])
    }

    @Test(arguments: [
        FilesClientError.forbidden(message: nil),
        FilesClientError.forbidden(message: "No access to this folder."),
        FilesClientError.server(statusCode: 404),
        FilesClientError.serverMessage(statusCode: 404, message: "Folder not found."),
    ])
    func aFolderTheServerDeniesOrCannotFindIsGone(error: FilesClientError) async {
        let calls = Calls()
        let store = store(
            defaults: UploadDefaults(folderPath: "Gone", shouldUploadWithoutAsking: true),
            calls: calls,
            browse: { _, _ in throw error }
        )
        await startAutomatic(store, folder: "Gone")
        await folderGone(store)
        await store.finish()
        #expect(calls.all.isEmpty, "\(error) must not start an upload that would fail file by file")
    }

    @Test(arguments: [
        FilesClientError.offline,
        FilesClientError.network("down"),
        FilesClientError.timedOut,
        FilesClientError.changedOnServer,
        FilesClientError.decoding("bad"),
        FilesClientError.server(statusCode: 500),
        FilesClientError.serverMessage(statusCode: 500, message: "Oops."),
        FilesClientError.rateLimited,
        FilesClientError.clientCertificateRequired,
        FilesClientError.clientCertificateRejected,
    ])
    func anErrorThatSaysNothingAboutTheFolderStillUploads(error: FilesClientError) async {
        let calls = Calls()
        let store = store(
            defaults: UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true),
            calls: calls,
            browse: { _, _ in throw error }
        )
        await startAutomatic(store)
        await store.receive(.defaultFolderChecked(accountID: credentials.accountID, .usable)) { $0.phase = .ready }
        await store.receive(\.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 3
        }
        await store.receive(\.preparationFinished) {
            $0.stagedCount = 3
            $0.phase = .handingOff
        }
        await store.receive(\.uploadResponse.success) { $0.phase = .started }
        await store.send(.viewDisappeared)
        #expect(calls.all == ["prepare", "start"])
    }

    @Test
    func aDefaultFolderTheAccountCanNoLongerUploadToIsTreatedAsGone() async {
        let store = store(
            defaults: UploadDefaults(folderPath: "ReadOnly", shouldUploadWithoutAsking: true),
            browse: { _, _ in Self.listing(canUpload: false) }
        )
        await startAutomatic(store, folder: "ReadOnly")
        await folderGone(store)
        #expect(store.state.notice == .defaultFolderUnavailable)
        #expect(store.state.folderPicker != nil)
    }

    @Test
    func choosingAnotherFolderClearsTheMessageAndAllowsTheUpload() async {
        let store = store(
            defaults: UploadDefaults(folderPath: "Gone", shouldUploadWithoutAsking: true),
            browse: { _, _ in throw FilesClientError.server(statusCode: 404) }
        )
        await startAutomatic(store, folder: "Gone")
        await folderGone(store)

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
        await startAutomatic(store, folder: "Photos/2026")
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
        await store.send(.viewDisappeared)
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
        await startAutomatic(store)
        await store.receive(\.defaultFolderChecked) { $0.phase = .signedOut }
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
        await becomeReady(store, folder: "Photos")
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
            $0.authClient.me = { _ in Self.user }
            $0.uploadDefaults = .inMemory([
                SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos"),
                SessionCredentials.previewSecond.accountID: UploadDefaults(folderPath: "Family", shouldUploadWithoutAsking: true),
            ])
            $0.cookieStorage = cookies
        }
        await store.send(.onAppear) { $0.itemCount = 1 }
        await store.receive(\.accountsLoaded) { $0.accounts = [.preview, .previewSecond] }
        await store.receive(\.sessionLoaded) {
            $0.credentials = .preview
            $0.destination = "Photos"
            $0.phase = .checking
        }
        await store.receive(\.connectionChecked) { $0.phase = .ready }
        #expect(store.state.canChooseAccount)

        await store.send(.accountSelected(SessionCredentials.previewSecond.accountID)) {
            $0.credentials = .previewSecond
            $0.destination = "Family"
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
        await store.send(.accountSelected("someone else"))
        #expect(store.state.credentials == .preview)
    }

    // MARK: Switching accounts while the default folder is being checked

    /// Two signed in accounts: the first uploads without asking from "Photos", the second has its
    /// own folder and waits for a tap. `browse` answers for whichever account asks.
    private func twoAccountStore(
        calls: Calls = Calls(),
        browse: @escaping @Sendable (URL, String) async throws -> BrowseResult
    ) -> Store {
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
            $0.authClient.me = { _ in Self.user }
            $0.filesClient.browse = browse
            $0.uploadDefaults = .inMemory([
                SessionCredentials.preview.accountID: UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true),
                SessionCredentials.previewSecond.accountID: UploadDefaults(folderPath: "Family"),
            ])
            $0.cookieStorage = cookies
        }
        // The first account's folder check is cancelled when the account changes, and whether a
        // cancelled effect still delivers its last action is up to the runtime, so only the end
        // result is asserted.
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
        await becomeReady(store, folder: "Photos")
        await uploadCleanly(store)

        await store.send(.cancelTapped)
        await store.receive(.delegate(.close(completed: true)))
        await clock.advance(by: Self.longerThanAnyCloseDelay)
        await store.finish()
    }

    @Test
    func theSheetDisappearingAfterTheUploadStartedStopsTheCloseTimer() async {
        let clock = TestClock()
        let store = store(defaults: UploadDefaults(folderPath: "Photos"), clock: clock)
        await becomeReady(store, folder: "Photos")
        await uploadCleanly(store)

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

    // MARK: What each phase offers

    private static let deadEnds: [ShareUploadFeature.Phase] = [.signedOut, .sessionUnreadable, .certificateRequired, .certificateRejected]

    @Test(arguments: [true, false])
    func eachPhaseOffersItsOwnButtons(canOpenApp: Bool) {
        let expected: [ShareUploadFeature.Phase: (primary: ShareUploadFeature.Control?, secondary: ShareUploadFeature.Control?)] = [
            .loading: (nil, nil),
            .checking: (.upload, nil),
            .ready: (.upload, nil),
            .preparing: (.upload, nil),
            .handingOff: (.upload, nil),
            .partiallyPrepared: (.uploadReady, .retryFailed),
            .started: (nil, nil),
            .failed: (.retry, nil),
            .nothingToUpload: (nil, nil),
            .signedOut: (canOpenApp ? .openApp : nil, canOpenApp ? .retry : nil),
            .sessionUnreadable: (canOpenApp ? .openApp : nil, canOpenApp ? .retry : nil),
            .certificateRequired: (canOpenApp ? .openApp : nil, canOpenApp ? .retry : nil),
            .certificateRejected: (canOpenApp ? .openApp : nil, canOpenApp ? .retry : nil),
        ]
        #expect(expected.count == ShareUploadFeature.Phase.previewCases.count, "every phase is covered")
        for (phase, buttons) in expected {
            var state = ShareUploadFeature.State()
            state.phase = phase
            #expect(state.primaryAction(canOpenApp: canOpenApp) == buttons.primary, "primary of \(phase)")
            #expect(state.secondaryAction(canOpenApp: canOpenApp) == buttons.secondary, "secondary of \(phase)")
            #expect(state.hasActions(canOpenApp: canOpenApp) == (buttons.primary != nil || buttons.secondary != nil), "footer of \(phase)")
        }
    }

    @Test
    func aPhoneOffersNoRetryWhereTheAppHasToFixIt() {
        for phase in Self.deadEnds {
            var state = ShareUploadFeature.State()
            state.phase = phase
            #expect(state.primaryAction(canOpenApp: false) == nil)
            #expect(state.secondaryAction(canOpenApp: false) == nil)
            #expect(!state.hasActions(canOpenApp: false), "the instruction and Close are all that is left")
        }
    }

    @Test
    func theButtonsSendTheActionsTheyAreNamedAfter() {
        #expect(ShareUploadFeature.Control.upload.action == .uploadTapped)
        #expect(ShareUploadFeature.Control.uploadReady.action == .uploadReadyTapped)
        #expect(ShareUploadFeature.Control.retryFailed.action == .retryTapped)
        #expect(ShareUploadFeature.Control.retry.action == .retryTapped)
        #expect(ShareUploadFeature.Control.openApp.action == .openAppTapped)
    }

    @Test
    func theButtonsAreTitledWithTheirLocalizedNames() {
        #expect(ShareUploadFeature.Control.upload.title == L10n.ShareUpload.upload)
        #expect(ShareUploadFeature.Control.uploadReady.title == L10n.ShareUpload.uploadReady)
        #expect(ShareUploadFeature.Control.retryFailed.title == L10n.ShareUpload.retryFailed)
        #expect(ShareUploadFeature.Control.retry.title == L10n.Common.retry)
        #expect(ShareUploadFeature.Control.openApp.title == L10n.ShareUpload.openApp)
    }

    @Test
    func theAccountAndFolderRowsStayVisibleAfterAFailedOrPartialPass() {
        let shown: Set<ShareUploadFeature.Phase> = [
            .checking, .ready, .preparing, .handingOff, .started, .partiallyPrepared, .failed,
        ]
        for phase in ShareUploadFeature.Phase.previewCases {
            var state = ShareUploadFeature.State()
            state.phase = phase
            #expect(state.shouldShowDetails == shown.contains(phase), "\(phase)")
        }
    }

    @Test
    func workIsInFlightWhileCheckingPreparingAndHandingOff() {
        let working: Set<ShareUploadFeature.Phase> = [.checking, .preparing, .handingOff]
        for phase in ShareUploadFeature.Phase.previewCases {
            var state = ShareUploadFeature.State()
            state.phase = phase
            #expect(state.isWorking == working.contains(phase), "\(phase)")
        }
    }

    @Test
    func theAccountIsNamedWithItsUserAndServerThroughTheLocalizedFormat() {
        #expect(ShareUploadFeature.State.name(for: .preview) == L10n.ShareUpload.accountSummary("phillip", "files.example.com"))
        var anonymous = SessionCredentials.preview
        anonymous.username = nil
        #expect(ShareUploadFeature.State.name(for: anonymous) == "files.example.com")
        anonymous.username = ""
        #expect(ShareUploadFeature.State.name(for: anonymous) == "files.example.com")
    }

    @Test
    func retryDoesNothingWhereItMakesNoSense() async {
        for phase in [ShareUploadFeature.Phase.ready, .started, .nothingToUpload, .preparing, .handingOff, .checking, .loading] {
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
        await becomeReady(store, folder: "Photos")
        await uploadCleanly(store)

        #expect(announcements.value == [L10n.ShareUpload.started])
        await clock.advance(by: .seconds(1.5))
        await store.receive(.delegate(.close(completed: true)))
    }

    @Test
    func withVoiceOverTheSheetStaysOpenLongerThanTheShortDelay() async {
        let announcements = LockIsolated<[String]>([])
        let clock = TestClock()
        let store = store(defaults: UploadDefaults(folderPath: "Photos"), clock: clock, isAssistive: true, announcements: announcements)
        await becomeReady(store, folder: "Photos")
        await uploadCleanly(store)

        await clock.advance(by: .seconds(2))
        #expect(store.state.phase == .started, "still open after the short delay")
        await clock.advance(by: .seconds(6))
        await store.receive(.delegate(.close(completed: true)))
        #expect(announcements.value == [L10n.ShareUpload.started])
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
        await becomeReady(store, folder: "Photos")
        await store.send(.uploadTapped) {
            $0.phase = .preparing
            $0.preparingTotal = 3
        }
        await store.receive(\.preparationFinished) {
            $0.phase = .partiallyPrepared
            $0.stagedCount = 1
            $0.failures = failures
        }
        await store.finish()
        #expect(announcements.value == [L10n.ShareUpload.failedItemsHeader])
    }
}
