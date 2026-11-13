import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct FavoritesNavigationTests: FavoritesTestSupport {
    @Test
    func openFolderDelegateFromAPushedScreenPushesAnotherLevel() async {
        let subfolder = FileItem(
            name: "2020",
            path: TestFolder.photos,
            dateModified: MockDate.date,
            size: 0,
            kind: FileItem.directoryKind
        )
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(
            serverURL: serverURL,
            directoryPath: TestFolder.photos,
            title: TestFolder.photos
        ))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.openFolder(subfolder))))) {
            $0.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/2020", title: "2020"))
        }
    }

    @Test
    func openPathDelegateFromAPushedScreenForwardsToNavigateToDirectory() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(
            serverURL: serverURL,
            directoryPath: TestFolder.photos,
            title: TestFolder.photos
        ))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        // An empty path, because a pushed screen's stack id comes from a generator that a `receive`
        // assertion cannot rewind. What the stack holds after a jump to a real path is covered by
        // navigateToDirectoryReplacesThePathStackWithASingleLevel.
        await store.send(.path(.element(id: 0, action: .delegate(.openPath(path: "", title: "Home")))))
        await store.receive(\.navigateToDirectory) { $0.path = StackState() }
    }

    @Test
    func favoritesChangedFromAPushedScreenBubblesUpAsADelegate() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(
            serverURL: serverURL,
            directoryPath: TestFolder.photos,
            title: TestFolder.photos
        ))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.favoritesChanged))))
        await store.receive(.delegate(.favoritesChanged))
    }

    @Test
    func openDownloadsTappedFromAPushedScreenBubblesUpAsADelegate() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(
            serverURL: serverURL,
            directoryPath: TestFolder.photos,
            title: TestFolder.photos
        ))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.openDownloadsTapped))))
        await store.receive(.delegate(.openDownloadsTapped))
    }

    @Test
    func goToSharedTabFromAPushedScreenBubblesUpAsADelegate() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(
            serverURL: serverURL,
            directoryPath: TestFolder.photos,
            title: TestFolder.photos
        ))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.path(.element(id: 0, action: .delegate(.goToSharedTab))))
        await store.receive(.delegate(.goToSharedTab))
    }

    @Test
    func navigateToDirectoryReplacesThePathStackWithASingleLevel() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Old", title: "Old"))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.navigateToDirectory(path: "Music", title: "Music")) {
            $0.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: "Music", title: "Music")])
        }
    }

    @Test
    func navigateToDirectoryWithAnEmptyPathJustClearsTheStack() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Old", title: "Old"))

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        }

        await store.send(.navigateToDirectory(path: "", title: "Home")) {
            $0.path = StackState()
        }
    }

    @Test
    func syncPathStackRefreshesEveryPushedSubfolder() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(
            serverURL: serverURL,
            directoryPath: TestFolder.photos,
            title: TestFolder.photos
        ))
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/2020", title: "2020"))
        let pathIDs = state.path.ids
        let refreshed = FileItem(name: "New.txt", path: "", dateModified: MockDate.date, size: 0, kind: TestKind.text)
        let access = FileAccess(
            canRead: true,
            canWrite: false,
            canUpload: false,
            canDelete: false,
            canShare: false,
            canDownload: true
        )
        let firstGate = AsyncGate()
        let secondGate = AsyncGate()
        let browsed = LockIsolated<[String]>([])

        let store = TestStore(initialState: state) {
            FavoritesFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                browsed.withValue { $0.append(path) }
                try await (path == TestFolder.photos ? firstGate : secondGate).wait()
                return BrowseResult(items: [refreshed], access: access, path: path)
            }
            $0.filesClient.favorites = { _ in throw FilesClientError.offline }
        }

        await store.send(.syncPathStack)
        await store.receive(\.path[id: pathIDs[0]].refreshButtonTapped) {
            $0.path[id: pathIDs[0]]?.phase = .loading
        }
        await store.receive(\.path[id: pathIDs[1]].refreshButtonTapped) {
            $0.path[id: pathIDs[1]]?.phase = .loading
        }
        // Each screen's answer is released in turn so its follow up actions arrive in a fixed order.
        for (index, gate) in [firstGate, secondGate].enumerated() {
            gate.open()
            await store.receive(\.path[id: pathIDs[index]].itemsResponse.success) {
                $0.path[id: pathIDs[index]]?.phase = .loaded
                $0.path[id: pathIDs[index]]?.items = [refreshed]
                $0.path[id: pathIDs[index]]?.access = access
            }
            await store.receive(\.path[id: pathIDs[index]].offlineAvailabilityComputed)
        }
        await store.finish()

        #expect(Set(browsed.value) == [TestFolder.photos, "Photos/2020"])
    }

    @Test
    func syncPathStackWithNoPushedScreensDoesNothing() async {
        let store = TestStore(initialState: FavoritesFeature.State(serverURL: serverURL)) {
            FavoritesFeature()
        }

        await store.send(.syncPathStack)
    }

    @Test
    func enclosingFolderFromAFavoritesOwnFolderReturnsToTheListAndForwardReopensIt() async {
        var state = FavoritesFeature.State(serverURL: serverURL)
        let folder = BrowseFeature.State(
            serverURL: serverURL,
            directoryPath: "Docs/Work",
            title: FilesFeatureTestValue.workFolder
        )
        state.path.append(folder)
        let store = TestStore(initialState: state) { FavoritesFeature() }

        await store.send(.goToEnclosingFolder) {
            $0.path.removeLast()
            $0.forwardStack = [folder]
        }
        await store.send(.goForward) {
            $0.forwardStack = []
            $0.path.append(folder)
        }
    }
}
