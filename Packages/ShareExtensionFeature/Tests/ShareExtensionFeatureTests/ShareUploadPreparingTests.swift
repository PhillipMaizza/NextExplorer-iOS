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

/// Staging the shared items: partial failures, retries, progress. Nested in `ShareUploadFeatureTests` so it inherits `.serialized` with every other share upload suite.
extension ShareUploadFeatureTests {
    @MainActor
    @Suite(.isolatedDependencies)
    struct ShareUploadPreparingTests: ShareUploadHarness {
        /// A store whose first pass throws `firstError` and whose later passes stage everything.
        private func failingFirstPassStore(calls: Calls, firstError: @escaping @Sendable () -> (any Error)?) -> Store {
            TestStore(initialState: ShareUploadFeature.State()) {
                ShareUploadFeature()
            } withDependencies: {
                $0.sharedItems.count = { 2 }
                $0.sharedItems.prepare = { _, _, indexes, _ in
                    calls.record(indexes: indexes, folder: TestFolder.photos)
                    if let error = firstError() {
                        throw error
                    }
                    return PreparationReport(stagedCount: 2, failures: [])
                }
                $0.sharedItems.start = {
                    calls.record(ShareExtensionFeatureTestValue.startCall)
                    return 2
                }
                $0.sharedItems.discard = { calls.record(ShareExtensionFeatureTestValue.discardCall) }
                $0.authClient.loadSession = { .preview }
                $0.authClient.listSessions = { [.preview] }
                $0.authClient.me = { _ in Self.user }
                $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: TestFolder.photos)])
                $0.continuousClock = TestClock()
            }
        }

        @Test
        func theHandOffHasItsOwnPhaseSoClosingDoesNotCountAsHavingStagedFiles() async {
            let store = store(defaults: UploadDefaults(folderPath: TestFolder.photos))
            await becomeReady(store, folder: TestFolder.photos)
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
            let failures = [ItemFailure(index: 1, name: ShareExtensionFeatureTestValue.movieName, cause: .cannotRead)]
            let store = store(
                defaults: UploadDefaults(folderPath: TestFolder.photos),
                calls: calls,
                report: PreparationReport(stagedCount: 2, failures: failures),
                announcements: announcements
            )
            await becomeReady(store, folder: TestFolder.photos)

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
            #expect(calls.all == [ShareExtensionFeatureTestValue.prepareCall], "nothing is sent and nothing is discarded while the user decides")
            #expect(store.state.failures.map(\.name) == [ShareExtensionFeatureTestValue.movieName], "the file is named")
            #expect(announcements.value == [L10n.ShareUpload.failedItemsHeader])

            await store.send(.uploadReadyTapped) {
                $0.phase = .handingOff
                $0.progress = PreparationProgress(completed: 3)
            }
            await store.receive(\.uploadResponse.success) { $0.phase = .started }
            #expect(calls.all == [ShareExtensionFeatureTestValue.prepareCall, ShareExtensionFeatureTestValue.startCall])
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
            let store = store(count: 6, defaults: UploadDefaults(folderPath: TestFolder.photos), calls: calls, report: report)
            await becomeReady(store, count: 6, folder: TestFolder.photos)
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
                    calls.record(ShareExtensionFeatureTestValue.prepareCall)
                    return pass == 1
                        ? PreparationReport(stagedCount: 2, failures: failed)
                        : PreparationReport(stagedCount: 3, failures: [])
                }
                $0.sharedItems.start = {
                    calls.record(ShareExtensionFeatureTestValue.startCall)
                    return 3
                }
                $0.sharedItems.discard = { calls.record(ShareExtensionFeatureTestValue.discardCall) }
                $0.authClient.loadSession = { .preview }
                $0.authClient.listSessions = { [.preview] }
                $0.authClient.me = { _ in Self.user }
                $0.uploadDefaults = .inMemory([SessionCredentials.preview.accountID: UploadDefaults(folderPath: TestFolder.photos)])
                $0.continuousClock = TestClock()
            }
            await becomeReady(store, folder: TestFolder.photos)
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
            #expect(calls.all == [ShareExtensionFeatureTestValue.prepareCall, ShareExtensionFeatureTestValue.prepareCall, ShareExtensionFeatureTestValue.startCall])
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
                defaults: UploadDefaults(folderPath: TestFolder.photos),
                calls: calls,
                report: PreparationReport(stagedCount: 0, failures: failures)
            )
            await becomeReady(store, count: 2, folder: TestFolder.photos)
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
            #expect(!calls.all.contains(ShareExtensionFeatureTestValue.startCall))
        }

        @Test
        func aWholePassFailureDiscardsTheBatchAndRetriesFromScratchInThatOrder() async {
            let calls = Calls()
            let shouldFail = LockIsolated(true)
            let store = failingFirstPassStore(calls: calls) { shouldFail.value ? CocoaError(.fileWriteUnknown) : nil }
            await becomeReady(store, count: 2, folder: TestFolder.photos)
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
                calls.all == [ShareExtensionFeatureTestValue.prepareCall, ShareExtensionFeatureTestValue.discardCall, ShareExtensionFeatureTestValue.discardCall, ShareExtensionFeatureTestValue.prepareCall, ShareExtensionFeatureTestValue.startCall],
                "the old batch is dropped before the new pass creates its own, never after"
            )
            await store.send(.viewDisappeared)
        }

        @Test
        func aPassThatGivesUpOnItsOwnIsAFailureNotAnEndlessPreparing() async {
            let calls = Calls()
            let store = failingFirstPassStore(calls: calls) { CancellationError() }
            await becomeReady(store, count: 2, folder: TestFolder.photos)

            await store.send(.uploadTapped) {
                $0.phase = .preparing
                $0.preparingTotal = 2
            }
            await store.receive(\.preparationFinished.failure) { $0.phase = .failed }
            await store.finish()

            #expect(calls.all == [ShareExtensionFeatureTestValue.prepareCall, ShareExtensionFeatureTestValue.discardCall])
        }

        @Test
        func aBatchWithNothingInItIsNothingToUpload() async {
            let calls = Calls()
            let store = store(
                defaults: UploadDefaults(folderPath: TestFolder.photos),
                calls: calls,
                report: PreparationReport(stagedCount: 0, failures: [])
            )
            await becomeReady(store, folder: TestFolder.photos)
            await store.send(.uploadTapped) {
                $0.phase = .preparing
                $0.preparingTotal = 3
            }
            await store.receive(\.preparationFinished) { $0.phase = .nothingToUpload }
            await store.finish()
            #expect(calls.all == [ShareExtensionFeatureTestValue.prepareCall, ShareExtensionFeatureTestValue.discardCall])
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
    }
}
