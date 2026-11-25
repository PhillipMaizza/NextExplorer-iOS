import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct FavoritesInfoTests: FavoritesTestSupport {
    private let documents = FileItem(
        name: TestFolder.documents,
        path: "",
        dateModified: MockDate.date,
        size: 0,
        kind: FileItem.directoryKind
    )
    private let photos = FileItem(
        name: TestFolder.photos,
        path: "",
        dateModified: MockDate.date,
        size: 0,
        kind: FileItem.directoryKind
    )
    private let usage = StorageUsage(path: TestFolder.documents, size: 40, free: 60, total: 100)

    private nonisolated func metadata(of path: String) -> FileMetadata {
        FileMetadata(
            path: path,
            name: path,
            kind: FileItem.directoryKind,
            size: 0,
            dateModified: MockDate.date,
            dateCreated: MockDate.date
        )
    }

    private func store(
        _ state: FavoritesFeature.State,
        usageGate: AsyncGate = AsyncGate(),
        metadata: @escaping @Sendable (String) throws -> FileMetadata
    ) -> TestStoreOf<FavoritesFeature> {
        let usage = usage
        return TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.date = .constant(MockDate.date)
            $0.filesClient.fetchMetadata = { _, path in try metadata(path) }
            $0.filesClient.fetchUsage = { _, _ in
                try await usageGate.wait()
                return usage
            }
            $0.filesClient.removeFavorite = { _, _ in }
        }
    }

    private func state(selecting ids: Set<Favorite.ID> = []) -> FavoritesFeature.State {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.favorites = [
            makeFavorite(id: "1", path: TestFolder.documents),
            makeFavorite(id: "2", path: TestFolder.photos, position: 1),
        ]
        state.tableSelection = ids
        return state
    }

    @Test("Get Info on a favorite loads its folder's details and disk, and again closes it")
    func getInfoLoadsTheFolderAndClosesAgain() async {
        let usageGate = AsyncGate()
        let store = store(state(selecting: ["1"]), usageGate: usageGate) { metadata(of: $0) }

        await store.send(.infoSelectionTapped) {
            $0.infoItem = documents
            $0.infoPhase = .loading
        }
        await store.receive(\.infoMetadataResponse) {
            $0.infoPhase = .loaded
            $0.infoMetadata = metadata(of: TestFolder.documents)
        }
        usageGate.open()
        await store.receive(\.infoUsageResponse) {
            $0.infoUsage = usage
        }
        await store.send(.infoSelectionTapped) {
            $0.infoItem = nil
            $0.infoMetadata = nil
            $0.infoUsage = nil
            $0.infoPhase = .idle
        }
    }

    @Test("Get Info opens nothing without exactly one selected favorite")
    func getInfoNeedsOneSelectedFavorite() async {
        await store(state()) { metadata(of: $0) }.send(.infoSelectionTapped)
        await store(state(selecting: ["1", "2"])) { metadata(of: $0) }.send(.infoSelectionTapped)
    }

    @Test("A failed load shows the error, with no disk figures kept")
    func aFailedLoadShowsTheError() async {
        let usageGate = AsyncGate()
        let store = store(state()) { _ in throw FilesClientError.offline }
        store.dependencies.filesClient.fetchUsage = { _, _ in
            try await usageGate.wait()
            throw FilesClientError.offline
        }

        await store.send(.infoTapped(makeFavorite(id: "1", path: TestFolder.documents))) {
            $0.infoItem = documents
            $0.infoPhase = .loading
        }
        await store.receive(\.infoMetadataResponse) {
            $0.infoPhase = .failed(FilesClientError.offline.userMessage)
        }
        usageGate.open()
        await store.receive(\.infoUsageResponse)
    }

    @Test("The open inspector follows a new single selection and ignores a multiple one")
    func theOpenInspectorFollowsTheSelection() async {
        var initial = state(selecting: ["1"])
        initial.infoItem = documents
        initial.infoMetadata = metadata(of: TestFolder.documents)
        initial.infoPhase = .loaded
        let usageGate = AsyncGate()
        let store = store(initial, usageGate: usageGate) { metadata(of: $0) }

        await store.send(.tableSelectionChanged(["1", "2"])) {
            $0.tableSelection = ["1", "2"]
        }
        await store.send(.tableSelectionChanged(["2"])) {
            $0.tableSelection = ["2"]
            $0.infoItem = photos
            $0.infoMetadata = nil
            $0.infoPhase = .loading
        }
        await store.receive(\.infoMetadataResponse) {
            $0.infoPhase = .loaded
            $0.infoMetadata = metadata(of: TestFolder.photos)
        }
        usageGate.open()
        await store.receive(\.infoUsageResponse) {
            $0.infoUsage = usage
        }
    }

    @Test("Removing the favorite the inspector shows closes it")
    func removingTheShownFavoriteClosesTheInspector() async {
        let favorite = makeFavorite(id: "1", path: TestFolder.documents)
        var initial = state(selecting: ["1"])
        initial.infoItem = documents
        initial.infoMetadata = metadata(of: TestFolder.documents)
        initial.infoPhase = .loaded
        let store = store(initial) { metadata(of: $0) }

        await store.send(.removeTapped(favorite))
        await store.receive(\.removeResponse) {
            $0.favorites.remove(id: favorite.id)
            $0.infoItem = nil
            $0.infoMetadata = nil
            $0.infoPhase = .idle
        }
    }
}
