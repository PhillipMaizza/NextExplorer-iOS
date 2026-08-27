import ComposableArchitecture
import FilesClient
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct DownloadsFeatureTests {
    private func makeDownload(fileName: String = "report.pdf", location: DownloadLocation = .documents) -> LocalDownload {
        LocalDownload(
            url: URL(fileURLWithPath: "/tmp/\(location.title)/Downloads/\(fileName)"),
            fileName: fileName,
            location: location,
            size: 1_024,
            modifiedDate: Date()
        )
    }

    // MARK: Happy path

    @Test
    func onAppearLoadsDownloads() async {
        let download = makeDownload()
        let store = TestStore(initialState: DownloadsFeature.State()) {
            DownloadsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { [download] }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.downloadsResponse.success) {
            $0.isLoading = false
            $0.downloads = [download]
        }
    }

    @Test
    func refreshButtonTappedReloadsEvenWhenDownloadsAreAlreadyLoaded() async {
        let existing = makeDownload(fileName: "old.pdf")
        let refreshed = makeDownload(fileName: "new.pdf")
        var state = DownloadsFeature.State()
        state.downloads = [existing]

        let store = TestStore(initialState: state) {
            DownloadsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { [refreshed] }
        }

        await store.send(.refreshButtonTapped) {
            $0.isLoading = true
        }
        await store.receive(\.downloadsResponse.success) {
            $0.isLoading = false
            $0.downloads = [refreshed]
        }
    }

    @Test
    func deleteConfirmedRemovesTheDownloadFromDiskAndFromState() async {
        let download = makeDownload()
        var state = DownloadsFeature.State()
        state.downloads = [download]
        state.deleteConfirmationItem = download

        let deletedURLs = LockIsolated<[URL]>([])
        let store = TestStore(initialState: state) {
            DownloadsFeature()
        } withDependencies: {
            $0.localDownloadStore.delete = { url in deletedURLs.withValue { $0.append(url) } }
        }

        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationItem = nil
        }
        await store.receive(\.deleteResponse.success) {
            $0.downloads = []
        }

        #expect(deletedURLs.value == [download.url])
    }

    @Test
    func deleteTappedSetsTheConfirmationItemAndCancelledClearsIt() async {
        let download = makeDownload()
        let store = TestStore(initialState: DownloadsFeature.State()) {
            DownloadsFeature()
        }

        await store.send(.deleteTapped(download)) {
            $0.deleteConfirmationItem = download
        }
        await store.send(.deleteCancelled) {
            $0.deleteConfirmationItem = nil
        }
    }

    // MARK: Error path

    @Test
    func onAppearSurfacesAListFailureAsAReadableErrorMessage() async {
        let store = TestStore(initialState: DownloadsFeature.State()) {
            DownloadsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { throw FilesClientError.network("disk error") }
        }

        await store.send(.onAppear) {
            $0.isLoading = true
        }
        await store.receive(\.downloadsResponse.failure) {
            $0.isLoading = false
            $0.errorMessage = FilesClientError.network("disk error").userMessage
        }
    }

    @Test
    func deleteConfirmedFailureSurfacesAReadableErrorMessageAndKeepsTheItem() async {
        let download = makeDownload()
        var state = DownloadsFeature.State()
        state.downloads = [download]
        state.deleteConfirmationItem = download

        let store = TestStore(initialState: state) {
            DownloadsFeature()
        } withDependencies: {
            $0.localDownloadStore.delete = { _ in throw FilesClientError.network("permission denied") }
        }

        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationItem = nil
        }
        await store.receive(\.deleteResponse.failure) {
            $0.errorMessage = FilesClientError.network("permission denied").userMessage
        }

        #expect(store.state.downloads == [download])
    }

    // MARK: Edge cases

    @Test
    func onAppearIsANoOpWhileAlreadyLoading() async {
        var state = DownloadsFeature.State()
        state.isLoading = true
        let store = TestStore(initialState: state) {
            DownloadsFeature()
        }

        await store.send(.onAppear)
    }

    @Test
    func onAppearIsANoOpWhenDownloadsAreAlreadyLoaded() async {
        var state = DownloadsFeature.State()
        state.downloads = [makeDownload()]
        let store = TestStore(initialState: state) {
            DownloadsFeature()
        }

        await store.send(.onAppear)
    }

    @Test
    func deleteConfirmedWithNoConfirmationItemDoesNothing() async {
        let store = TestStore(initialState: DownloadsFeature.State()) {
            DownloadsFeature()
        }

        await store.send(.deleteConfirmed)
    }
}
