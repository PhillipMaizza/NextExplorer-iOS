import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// After a copy or move into the folder on screen, the listing is refetched a few times until the
/// server lists what was created. Driven on one `BrowseFeature` with a `TestClock`, so every
/// refetch happens exactly when the test advances time and nothing else reloads the folder.
@Suite(.isolatedDependencies)
@MainActor
struct ArrivalRecheckTests {
    private typealias Store = TestStoreOf<BrowseFeature>

    private let serverURL = URL(fileURLWithPath: "/")
    private let access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)
    private let recheckDelay = Duration.milliseconds(700)

    private nonisolated func file(_ name: String) -> FileItem {
        FileItem(name: name, path: TestFolder.docs, dateModified: MockDate.date, size: 1, kind: TestKind.text)
    }

    /// The favorites fetch fails on purpose: production sends nothing for a failed fetch, which keeps
    /// the action stream to the listing refetches this suite is about.
    private func store(
        listing: LockIsolated<[FileItem]>,
        fetches: LockIsolated<Int>,
        clock: TestClock<Duration>
    ) -> Store {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: TestFolder.docs, title: TestFolder.docs)
        state.phase = .loaded
        state.access = access
        state.awaitedArrivalIDs = ["Docs/report (2).txt"]
        state.arrivalChecksLeft = 3
        let access = access
        return TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                fetches.withValue { $0 += 1 }
                return BrowseResult(items: listing.value, access: access, path: path)
            }
            $0.filesClient.favorites = { _ in throw FilesClientError.offline }
            $0.continuousClock = clock
            $0.date = .constant(MockDate.date)
        }
    }

    private func listed(_ items: [FileItem]) -> BrowseResult {
        BrowseResult(items: items, access: access, path: TestFolder.docs)
    }

    /// Advances to the next recheck and receives the refetch it starts, up to the offline availability pass.
    private func recheck(_ store: Store, clock: TestClock<Duration>, expectingItems items: [FileItem], then update: @escaping (inout BrowseFeature.State) -> Void) async {
        await clock.advance(by: recheckDelay)
        await store.receive(\.refreshButtonTapped) { $0.phase = .loading }
        await store.receive(\.itemsResponse.success) {
            $0.phase = .loaded
            $0.items = IdentifiedArray(uniqueElements: items)
            update(&$0)
        }
        await store.receive(\.offlineAvailabilityComputed)
    }

    @Test
    func aCopyTheServerListsLateIsRefetchedUntilItAppears() async {
        let report = file("report.txt")
        let copy = file("report (2).txt")
        let listing = LockIsolated([report])
        let fetches = LockIsolated(0)
        let clock = TestClock<Duration>()
        let store = store(listing: listing, fetches: fetches, clock: clock)

        await store.send(.itemsResponse(.success(listed([report])))) {
            $0.items = IdentifiedArray(uniqueElements: [report])
            $0.arrivalChecksLeft = 2
        }
        await store.receive(\.offlineAvailabilityComputed)
        #expect(fetches.value == 0)

        listing.setValue([report, copy])
        await recheck(store, clock: clock, expectingItems: [copy, report]) {
            $0.awaitedArrivalIDs = []
            $0.arrivalChecksLeft = 0
        }
        await store.finish()

        #expect(fetches.value == 1)
    }

    @Test
    func theRefetchingStopsOnceTheRechecksRunOut() async {
        let report = file("report.txt")
        let listing = LockIsolated([report])
        let fetches = LockIsolated(0)
        let clock = TestClock<Duration>()
        let store = store(listing: listing, fetches: fetches, clock: clock)

        await store.send(.itemsResponse(.success(listed([report])))) {
            $0.items = IdentifiedArray(uniqueElements: [report])
            $0.arrivalChecksLeft = 2
        }
        await store.receive(\.offlineAvailabilityComputed)
        await recheck(store, clock: clock, expectingItems: [report]) { $0.arrivalChecksLeft = 1 }
        await recheck(store, clock: clock, expectingItems: [report]) { $0.arrivalChecksLeft = 0 }
        await recheck(store, clock: clock, expectingItems: [report]) { $0.awaitedArrivalIDs = [] }
        await store.finish()

        #expect(fetches.value == 3)
    }

    @Test
    func nothingIsRefetchedWhenTheCopyIsAlreadyListed() async {
        let report = file("report.txt")
        let copy = file("report (2).txt")
        let fetches = LockIsolated(0)
        let clock = TestClock<Duration>()
        let store = store(listing: LockIsolated([report, copy]), fetches: fetches, clock: clock)

        await store.send(.itemsResponse(.success(listed([report, copy])))) {
            $0.items = IdentifiedArray(uniqueElements: [copy, report])
            $0.awaitedArrivalIDs = []
            $0.arrivalChecksLeft = 0
        }
        await store.receive(\.offlineAvailabilityComputed)
        await store.finish()

        #expect(fetches.value == 0)
    }
}
