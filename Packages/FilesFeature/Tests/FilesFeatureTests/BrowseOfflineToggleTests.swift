import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The per item Available Offline toggle: pin, unpin, and what a folder's pin covers below it.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseOfflineToggleTests: OfflineDownloadsTestSupport {
    private enum Constants {
        static let trips = "Trips"
        static let tripsPath = "Docs/Trips"
        static let other = "Other"
        static let nested = "Nested"
        static let nestedPath = "Docs/Trips/Nested"
    }

    private let photo = BrowseFixtures.file(TestFile.vacationPhoto, in: TestFolder.docs)
    private let trips = BrowseFixtures.folder(Constants.trips, in: TestFolder.docs)
    private let other = BrowseFixtures.folder(Constants.other, in: TestFolder.docs)
    private let tripsPhoto = BrowseFixtures.file(TestFile.vacationPhoto, in: Constants.tripsPath)
    private let nested = BrowseFixtures.folder(Constants.nested, in: Constants.tripsPath)

    @Test
    func togglingAnItemThatIsNotOfflinePinsIt() async {
        let store = BrowseFixtures.store(BrowseFixtures.loadedState(TestFolder.docs, items: [photo]))

        await store.send(.offlineToggleTapped(photo)) {
            $0.offlineItemIDs = [photo.id]
            $0.offlinePinnedItemIDs = [photo.id]
        }
        await store.receive(.delegate(.offlinePinRequested([photo])))
    }

    @Test
    func togglingAnItemYouPinnedAsksBeforeUnpinning() async {
        var state = BrowseFixtures.loadedState(TestFolder.docs, items: [trips])
        state.offlineItemIDs = [trips.id]
        state.offlinePinnedItemIDs = [trips.id]
        let store = BrowseFixtures.store(state)

        await store.send(.offlineToggleTapped(trips)) {
            $0.offlineRemoval = OfflineRemovalRequest(paths: [trips.id], names: [Constants.trips])
        }
    }

    @Test
    func confirmingTheRemovalUnpinsAndCancellingKeepsIt() async {
        var state = BrowseFixtures.loadedState(TestFolder.docs, items: [trips])
        state.offlineItemIDs = [trips.id]
        state.offlinePinnedItemIDs = [trips.id]
        state.offlineRemoval = OfflineRemovalRequest(paths: [trips.id], names: [Constants.trips])
        let store = BrowseFixtures.store(state)

        await store.send(.offlineRemovalCancelled) { $0.offlineRemoval = nil }
        await store.send(.offlineToggleTapped(trips)) {
            $0.offlineRemoval = OfflineRemovalRequest(paths: [trips.id], names: [Constants.trips])
        }
        await store.send(.offlineRemovalConfirmed) {
            $0.offlineRemoval = nil
            $0.offlineItemIDs = []
            $0.offlinePinnedItemIDs = []
        }
        await store.receive(.delegate(.offlineUnpinRequested(path: trips.id)))
    }

    @Test
    func confirmingWithNothingPendingDoesNothing() async {
        let store = BrowseFixtures.store(BrowseFixtures.loadedState(TestFolder.docs, items: [trips]))

        await store.send(.offlineRemovalConfirmed)
    }

    @Test
    func togglingAnItemOfflineOnlyThroughItsFolderDoesNothing() async {
        var state = BrowseFixtures.loadedState(Constants.tripsPath, items: [tripsPhoto])
        state.offlineItemIDs = [tripsPhoto.id]
        let store = BrowseFixtures.store(state)

        await store.send(.offlineToggleTapped(tripsPhoto))
    }

    @Test
    func aPinnedFolderMakesEverythingBelowItAvailableButNotAPinnedRoot() async {
        let offline = pinnedStore([Constants.tripsPath])
        let store = BrowseFixtures.store(
            BrowseFixtures.loadedState(Constants.tripsPath, items: [tripsPhoto, nested])
        ) {
            $0.offlineFileStore = offline
        }

        await store.send(.computeOfflineAvailability)
        await store.receive(\.offlineAvailabilityComputed) {
            $0.offlineItemIDs = [tripsPhoto.id, nested.id]
            $0.offlinePinnedItemIDs = []
        }
    }

    @Test
    func theFolderYouPinnedIsAvailableAndPinnedWhileItsSiblingIsNot() async {
        let offline = pinnedStore([Constants.tripsPath])
        let store = BrowseFixtures.store(
            BrowseFixtures.loadedState(TestFolder.docs, items: [trips, other, photo])
        ) {
            $0.offlineFileStore = offline
        }

        await store.send(.computeOfflineAvailability)
        await store.receive(\.offlineAvailabilityComputed) {
            $0.offlineItemIDs = [trips.id]
            $0.offlinePinnedItemIDs = [trips.id]
        }
    }

    @Test
    func aFolderNamedLikeAPinnedFoldersPrefixIsNotCovered() async {
        let lookalike = BrowseFixtures.folder("Trips2", in: TestFolder.docs)
        let offline = pinnedStore([Constants.tripsPath])
        let store = BrowseFixtures.store(BrowseFixtures.loadedState(TestFolder.docs, items: [lookalike])) {
            $0.offlineFileStore = offline
        }

        await store.send(.computeOfflineAvailability)
        await store.receive(\.offlineAvailabilityComputed)
        #expect(store.state.offlineItemIDs.isEmpty)
        #expect(store.state.offlinePinnedItemIDs.isEmpty)
    }

    @Test
    func unpinningDropsTheRootFromTheManifest() async {
        let offline = pinnedStore([Constants.tripsPath, TestFolder.docs])
        let store = makeStore(
            freshState(),
            hold: BrowseHold(),
            offline: offline,
            browse: { _ in BrowseResult(items: [], access: BrowseTestSupport.fullAccess, path: "") }
        )

        await store.send(.unpinTapped(path: Constants.tripsPath))
        await store.receive(\.unpinFinished)
        #expect(offline.pinnedRoots().map(\.path) == [TestFolder.docs])
    }

    @Test
    func unpinningAPathThatIsNotPinnedChangesNothing() async {
        let offline = pinnedStore([TestFolder.docs])
        let store = makeStore(
            freshState(),
            hold: BrowseHold(),
            offline: offline,
            browse: { _ in BrowseResult(items: [], access: BrowseTestSupport.fullAccess, path: "") }
        )

        await store.send(.unpinTapped(path: Constants.tripsPath))
        await store.receive(\.unpinFinished)
        #expect(offline.pinnedRoots().map(\.path) == [TestFolder.docs])
    }

    @Test
    func bulkOfflinePinsEverySelectedItemThatIsNotOfflineYet() async {
        var state = BrowseFixtures.loadedState(TestFolder.docs, items: [photo, trips, other])
        state.isSelecting = true
        state.selectedItemIDs = [photo.id, trips.id]
        state.offlineItemIDs = [trips.id]
        state.offlinePinnedItemIDs = [trips.id]
        let store = BrowseFixtures.store(state)

        await store.send(.bulkOfflineTapped) {
            $0.isSelecting = false
            $0.selectedItemIDs = []
            $0.offlineItemIDs = [photo.id, trips.id]
            $0.offlinePinnedItemIDs = [photo.id, trips.id]
        }
        await store.receive(.delegate(.offlinePinRequested([photo])))
    }

    @Test
    func bulkOfflineAsksBeforeUnpinningWhenEverySelectedItemIsAlreadyOffline() async {
        var state = BrowseFixtures.loadedState(TestFolder.docs, items: [trips, other])
        state.isSelecting = true
        state.selectedItemIDs = [trips.id, other.id]
        state.offlineItemIDs = [trips.id, other.id]
        state.offlinePinnedItemIDs = [trips.id]
        let store = BrowseFixtures.store(state)

        await store.send(.bulkOfflineTapped) {
            $0.isSelecting = false
            $0.selectedItemIDs = []
            $0.offlineRemoval = OfflineRemovalRequest(paths: [trips.id], names: [Constants.trips])
        }
        await store.send(.offlineRemovalConfirmed) {
            $0.offlineRemoval = nil
            $0.offlineItemIDs = [other.id]
            $0.offlinePinnedItemIDs = []
        }
        await store.receive(.delegate(.offlineUnpinRequested(path: trips.id)))
    }

    @Test
    func bulkOfflineOnItemsOfflineOnlyThroughAFolderDoesNothing() async {
        var state = BrowseFixtures.loadedState(Constants.tripsPath, items: [tripsPhoto])
        state.isSelecting = true
        state.selectedItemIDs = [tripsPhoto.id]
        state.offlineItemIDs = [tripsPhoto.id]
        let store = BrowseFixtures.store(state)

        await store.send(.bulkOfflineTapped) {
            $0.isSelecting = false
            $0.selectedItemIDs = []
        }
    }

    @Test
    func bulkOfflineWithNothingSelectedDoesNothing() async {
        let store = BrowseFixtures.store(BrowseFixtures.loadedState(TestFolder.docs, items: [photo]))

        await store.send(.bulkOfflineTapped)
    }
}
