import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// A search hit opens outside the listing the offline marks come from, so it is marked kept or
/// pinned when it opens, and its preview offers the removal instead of keeping it again.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseSearchHitOfflineTests {
    /// The file the hit opens as.
    private let opened = FileItem(
        name: TestFile.clip,
        path: TestFolder.media,
        dateModified: MockDate.date,
        size: 0,
        kind: TestKind.video
    )
    private let hit = SearchResultItem(name: TestFile.clip, path: TestFolder.media, kind: SearchResultItem.fileKind)

    private func store(pinning roots: [OfflinePinnedRoot]) -> TestStoreOf<BrowseFeature> {
        let offline = OfflineFileStore.inMemory()
        offline.setPinnedRoots(roots)
        return BrowseFixtures.store { $0.offlineFileStore = offline }
    }

    @Test("A file result inside a pinned folder opens marked as kept, so its preview offers the removal")
    func searchResultTappedInsideAPinnedFolderMarksItKept() async {
        let store = store(pinning: [OfflinePinnedRoot(path: TestFolder.media, isDirectory: true)])

        await store.send(.searchResultTapped(hit)) {
            $0.isPreviewOutsideListing = true
            $0.offlineItemIDs = [opened.id]
        }
        await store.receive(.rowTapped(opened)) {
            $0.previewItem = opened
        }
    }

    @Test("A file result pinned on its own opens marked as pinned")
    func searchResultTappedOnAPinnedFileMarksItPinned() async {
        let store = store(pinning: [OfflinePinnedRoot(path: opened.id, isDirectory: false)])

        await store.send(.searchResultTapped(hit)) {
            $0.isPreviewOutsideListing = true
            $0.offlinePinnedItemIDs = [opened.id]
            $0.offlineItemIDs = [opened.id]
        }
        await store.receive(.rowTapped(opened)) {
            $0.previewItem = opened
        }
    }

    @Test("A file result a pinned folder only shares a name prefix with stays unmarked")
    func searchResultTappedBesideAPinnedFolderStaysUnmarked() async {
        let store = store(pinning: [OfflinePinnedRoot(path: String(TestFolder.media.dropLast()), isDirectory: true)])

        await store.send(.searchResultTapped(hit)) {
            $0.isPreviewOutsideListing = true
        }
        await store.receive(.rowTapped(opened)) {
            $0.previewItem = opened
        }
    }

    @Test("Working the listing's marks out again keeps the open hit's own marks")
    func aRecomputeKeepsTheOpenHitsMarks() async {
        var state = BrowseFixtures.loadedState(TestFolder.docs)
        state.isPreviewOutsideListing = true
        state.previewItem = opened
        state.offlineItemIDs = [opened.id]
        state.offlinePinnedItemIDs = [opened.id]
        let store = BrowseFixtures.store(state)

        await store.send(.offlineAvailabilityComputed(all: [], pinned: []))
    }

    @Test("Once the hit's preview is closed, a recompute drops its marks")
    func aRecomputeAfterThePreviewDropsTheHitsMarks() async {
        var state = BrowseFixtures.loadedState(TestFolder.docs)
        state.offlineItemIDs = [opened.id]
        let store = BrowseFixtures.store(state)

        await store.send(.offlineAvailabilityComputed(all: [], pinned: [])) {
            $0.offlineItemIDs = []
        }
    }
}
