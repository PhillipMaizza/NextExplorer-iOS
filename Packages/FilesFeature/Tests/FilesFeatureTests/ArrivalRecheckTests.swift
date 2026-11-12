import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

/// After a copy or move into the folder on screen, the listing is refetched a few times until the
/// server lists what was created. Driven on one `BrowseFeature` with a `TestClock`, so every
/// refetch happens exactly when the test advances time and nothing else reloads the folder.
@MainActor
struct ArrivalRecheckTests {
    private let serverURL = URL(string: "https://example.com")!
    private let access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)

    private nonisolated func file(_ name: String) -> FileItem {
        FileItem(name: name, path: "Docs", dateModified: Date(timeIntervalSince1970: 1), size: 1, kind: "txt")
    }

    private func store(
        listing: LockIsolated<[FileItem]>,
        fetches: LockIsolated<Int>,
        clock: TestClock<Duration>
    ) -> TestStoreOf<BrowseFeature> {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
        state.phase = .loaded
        state.access = access
        state.awaitedArrivalIDs = ["Docs/report (2).txt"]
        state.arrivalChecksLeft = 3
        let access = access
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                fetches.withValue { $0 += 1 }
                return BrowseResult(items: listing.value, access: access, path: path)
            }
            $0.filesClient.favorites = { _ in [] }
            $0.continuousClock = clock
            $0.date = .constant(Date(timeIntervalSince1970: 3))
        }
        store.exhaustivity = .off
        return store
    }

    private func listed(_ items: [FileItem]) -> BrowseResult {
        BrowseResult(items: items, access: access, path: "Docs")
    }

    @Test
    func aCopyTheServerListsLateIsRefetchedUntilItAppears() async {
        let report = file("report.txt")
        let copy = file("report (2).txt")
        let listing = LockIsolated([report])
        let fetches = LockIsolated(0)
        let clock = TestClock<Duration>()
        let store = store(listing: listing, fetches: fetches, clock: clock)

        await store.send(.itemsResponse(.success(listed([report]))))
        #expect(store.state.awaitedArrivalIDs == ["Docs/report (2).txt"])
        #expect(store.state.arrivalChecksLeft == 2)
        #expect(fetches.value == 0)

        listing.setValue([report, copy])
        await clock.advance(by: .seconds(1))
        await store.receive(\.refreshButtonTapped)
        await store.receive(\.itemsResponse.success)
        await store.finish()

        #expect(store.state.items.map(\.name) == ["report (2).txt", "report.txt"])
        #expect(store.state.awaitedArrivalIDs.isEmpty)
        #expect(fetches.value == 1)
    }

    @Test
    func theRefetchingStopsOnceTheRechecksRunOut() async {
        let report = file("report.txt")
        let listing = LockIsolated([report])
        let fetches = LockIsolated(0)
        let clock = TestClock<Duration>()
        let store = store(listing: listing, fetches: fetches, clock: clock)

        await store.send(.itemsResponse(.success(listed([report]))))
        for _ in 0 ..< 3 {
            await clock.advance(by: .seconds(1))
            await store.receive(\.refreshButtonTapped)
            await store.receive(\.itemsResponse.success)
        }
        await store.finish()

        #expect(fetches.value == 3)
        #expect(store.state.awaitedArrivalIDs.isEmpty)
        #expect(store.state.arrivalChecksLeft == 0)
        #expect(store.state.items.map(\.name) == ["report.txt"])
    }

    @Test
    func nothingIsRefetchedWhenTheCopyIsAlreadyListed() async {
        let report = file("report.txt")
        let copy = file("report (2).txt")
        let fetches = LockIsolated(0)
        let clock = TestClock<Duration>()
        let store = store(listing: LockIsolated([report, copy]), fetches: fetches, clock: clock)

        await store.send(.itemsResponse(.success(listed([report, copy]))))
        await store.finish()

        #expect(store.state.awaitedArrivalIDs.isEmpty)
        #expect(store.state.arrivalChecksLeft == 0)
        #expect(fetches.value == 0)
    }
}
