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

/// Cancelling, closing, the upload hand off and the close timer. Nested in `ShareUploadFeatureTests` so it inherits `.serialized` with every other share upload suite.
extension ShareUploadFeatureTests {
    @MainActor
    @Suite(.isolatedDependencies)
    struct ShareUploadClosingTests: ShareUploadHarness {
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

        private static let longerThanAnyCloseDelay: Duration = .seconds(60)

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
            let (entered, signalEntered) = AsyncStream.makeStream(of: Void.self)
            let store = TestStore(initialState: ShareUploadFeature.State()) {
                ShareUploadFeature()
            } withDependencies: {
                $0.sharedItems.count = { 2 }
                $0.sharedItems.prepare = { _, _, _, _ in
                    signalEntered.yield()
                    do {
                        try await suspendUntilCancelled()
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
    }
}
