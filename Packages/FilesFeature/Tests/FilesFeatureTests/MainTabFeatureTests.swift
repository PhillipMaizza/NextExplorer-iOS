import ComposableArchitecture
import CoreModels
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct MainTabFeatureTests {
    private let serverURL = URL(string: "https://example.com")!
    private let user = User(id: "1", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [])

    // MARK: Happy path

    @Test
    func tabSelectedUpdatesTheSelectedTab() async {
        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        }

        await store.send(.tabSelected(.favorites)) {
            $0.selectedTab = .favorites
        }
    }

    @Test
    func selectingADirectoryFromFavoritesSwitchesToBrowseAndNavigatesThere() async {
        // Exhaustivity off: the freshly-pushed `BrowseFeature.State` gets a `StackElementID`
        // that isn't reproducible from inside a `receive`-triggered assertion closure (`send`
        // gets special generator snapshotting from TCA, `receive` doesn't) — asserting the
        // resulting path's content is what actually matters here.
        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        }
        store.exhaustivity = .off

        await store.send(.favorites(.delegate(.didSelectDirectory(path: "Photos", title: "Photos"))))
        await store.receive(\.browse.navigateToDirectory)

        #expect(store.state.selectedTab == .browse)
        #expect(store.state.browse.path.map(\.directoryPath) == ["Photos"])
    }

    @Test
    func signOutDelegateFromSettingsIsForwardedUpward() async {
        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        }

        await store.send(.settings(.delegate(.signOutButtonTapped)))
        await store.receive(\.delegate, .signOutButtonTapped)
    }

    // MARK: Edge cases

    @Test
    func selectingTheHomeDirectoryFromFavoritesClearsAnyExistingBrowseStack() async {
        var state = MainTabFeature.State(serverURL: serverURL, user: user)
        state.browse.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Old", title: "Old"))

        let store = TestStore(initialState: state) {
            MainTabFeature()
        }
        store.exhaustivity = .off

        await store.send(.favorites(.delegate(.didSelectDirectory(path: "", title: "Home"))))
        await store.receive(\.browse.navigateToDirectory)

        #expect(store.state.selectedTab == .browse)
        #expect(store.state.browse.path.isEmpty)
    }

    @Test
    func initialStateDefaultsToTheBrowseTab() {
        let state = MainTabFeature.State(serverURL: serverURL, user: user)
        #expect(state.selectedTab == .browse)
    }
}
