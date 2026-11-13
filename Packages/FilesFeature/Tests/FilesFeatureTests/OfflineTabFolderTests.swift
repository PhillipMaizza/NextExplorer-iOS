import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// Opening a pinned folder from the Offline tab, and what the tab forwards from the screens it pushes.
@Suite(.isolatedDependencies)
@MainActor
struct OfflineTabFolderTests {
    private enum Constants {
        static let folderPath = "Docs/Trips"
        static let folderName = "Trips"
        static let childPath = "Docs/Trips/Nested"
        static let childName = "Nested"
    }

    private func makeStore(serverURL: URL? = BrowseTestSupport.serverURL) -> TestStoreOf<OfflineTabFeature> {
        TestStore(initialState: OfflineTabFeature.State(serverURL: serverURL)) {
            OfflineTabFeature()
        }
    }

    private func browseScreen(_ path: String, _ title: String) -> BrowseFeature.State {
        BrowseFeature.State(serverURL: BrowseTestSupport.serverURL, directoryPath: path, title: title)
    }

    @Test
    func tappingAPinnedFolderOpensItAsABrowseScreen() async {
        let store = makeStore()

        await store.send(.openFolderTapped(path: Constants.folderPath)) {
            $0.path.append(browseScreen(Constants.folderPath, Constants.folderName))
        }
    }

    @Test
    func tappingAnotherPinnedFolderReplacesTheOpenOne() async {
        let store = makeStore()

        await store.send(.openFolderTapped(path: Constants.folderPath)) {
            $0.path.append(browseScreen(Constants.folderPath, Constants.folderName))
        }
        await store.send(.openFolderTapped(path: Constants.childPath)) {
            $0.path.removeAll()
            $0.path.append(browseScreen(Constants.childPath, Constants.childName))
        }
    }

    @Test
    func withoutAServerNothingOpens() async {
        let store = makeStore(serverURL: nil)

        await store.send(.openFolderTapped(path: Constants.folderPath))
    }

    @Test
    func drillingIntoASubfolderPushesItOnTop() async {
        var state = OfflineTabFeature.State(serverURL: BrowseTestSupport.serverURL)
        state.path.append(browseScreen(Constants.folderPath, Constants.folderName))
        let store = TestStore(initialState: state) { OfflineTabFeature() }
        let child = BrowseFixtures.folder(Constants.childName, in: Constants.folderPath)

        await store.send(.path(.element(id: 0, action: .delegate(.openFolder(child))))) {
            $0.path.append(browseScreen(Constants.childPath, Constants.childName))
        }
    }

    @Test
    func pinRequestsFromAPushedScreenGoUpToTheShell() async {
        var state = OfflineTabFeature.State(serverURL: BrowseTestSupport.serverURL)
        state.path.append(browseScreen(Constants.folderPath, Constants.folderName))
        let store = TestStore(initialState: state) { OfflineTabFeature() }
        let child = BrowseFixtures.folder(Constants.childName, in: Constants.folderPath)

        await store.send(.path(.element(id: 0, action: .delegate(.offlinePinRequested([child])))))
        await store.receive(.delegate(.offlinePinRequested([child])))
        await store.send(.path(.element(id: 0, action: .delegate(.offlineUnpinRequested(path: Constants.childPath)))))
        await store.receive(.delegate(.offlineUnpinRequested(path: Constants.childPath)))
    }

    struct Request: Sendable, CustomTestStringConvertible {
        let fromScreen: BrowseFeature.Action.Delegate
        let upward: OfflineTabFeature.Action.Delegate

        var testDescription: String {
            "\(upward)"
        }
    }

    @Test(
        "A folder opened from the Offline tab can upload, download, save, star and share like one in Browse",
        arguments: [
            Request(
                fromScreen: .uploadRequested([BrowseFixtures.upload]),
                upward: .uploadRequested([BrowseFixtures.upload])
            ),
            Request(
                fromScreen: .downloadRequested([BrowseFixtures.textFile]),
                upward: .downloadRequested([BrowseFixtures.textFile])
            ),
            Request(
                fromScreen: .saveRequested([BrowseFixtures.saveRequest]),
                upward: .saveRequested([BrowseFixtures.saveRequest])
            ),
            Request(fromScreen: .favoritesChanged, upward: .favoritesChanged),
            Request(fromScreen: .goToSharedTab, upward: .goToSharedTab),
        ]
    )
    func requestsFromAPushedFolderGoUpToTheShell(_ request: Request) async {
        var state = OfflineTabFeature.State(serverURL: BrowseTestSupport.serverURL)
        state.path.append(browseScreen(Constants.folderPath, Constants.folderName))
        let store = TestStore(initialState: state) { OfflineTabFeature() }

        await store.send(.path(.element(id: 0, action: .delegate(request.fromScreen))))
        await store.receive(.delegate(request.upward))
    }

    @Test
    func aChangeInPinsMakesEveryPushedScreenRecomputeItsBadges() async {
        var state = OfflineTabFeature.State(serverURL: BrowseTestSupport.serverURL)
        state.path.append(browseScreen(Constants.folderPath, Constants.folderName))
        state.path.append(browseScreen(Constants.childPath, Constants.childName))
        let store = TestStore(initialState: state) { OfflineTabFeature() }

        await store.send(.offlineAvailabilityChanged)
        await store.receive(\.path[id: 0].computeOfflineAvailability)
        await store.receive(\.path[id: 1].computeOfflineAvailability)
    }
}
