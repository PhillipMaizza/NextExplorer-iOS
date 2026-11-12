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
struct MainTabNavigationTests: MainTabTestSupport {
    struct SettingsHandOff: Sendable, CustomTestStringConvertible {
        let fromSettings: SettingsFeature.Action.Delegate
        let upward: MainTabFeature.Action.Delegate

        var testDescription: String { "\(upward)" }
    }

    @Test(
        "Account intents from Settings are forwarded upward untouched",
        arguments: [
            SettingsHandOff(fromSettings: .signOutButtonTapped, upward: .signOutButtonTapped),
            SettingsHandOff(fromSettings: .switchAccount("account-2"), upward: .switchAccount("account-2")),
            SettingsHandOff(fromSettings: .removeAccount("account-3"), upward: .removeAccount("account-3")),
            SettingsHandOff(fromSettings: .addAccountRequested, upward: .addAccountRequested),
        ]
    )
    func settingsDelegatesAreForwardedUpward(_ handOff: SettingsHandOff) async {
        let store = makeStore()

        await store.send(.settings(.delegate(handOff.fromSettings)))
        await store.receive(\.delegate, handOff.upward)
    }

    @Test("Go to Folder opens the trimmed path in Browse and closes the dialog")
    func goToFolderOpensTheTrimmedPathInBrowse() async {
        let store = makeStore(makeState { $0.selectedTab = .shared })

        await store.send(.goToFolderPrompted) {
            $0.isGoToFolderPresented = true
        }
        await store.send(.goToFolderRequested(" /Documents/Reports/ ")) {
            $0.isGoToFolderPresented = false
            $0.selectedTab = .browse
        }
        await store.receive(\.browse.navigateToDirectory) {
            $0.browse.path[id: 0] = BrowseFeature.State(serverURL: serverURL, directoryPath: TestPath.documentsReports, title: "Reports")
            $0.recentFolders = [TestPath.documentsReports]
        }
    }

    @Test("A blank Go to Folder path closes the dialog and goes nowhere")
    func aBlankGoToFolderPathDoesNothing() async {
        let store = makeStore(makeState {
            $0.selectedTab = .settings
            $0.isGoToFolderPresented = true
        })

        await store.send(.goToFolderRequested(" / ")) {
            $0.isGoToFolderPresented = false
        }
    }

    @Test("Dismissing Go to Folder closes the dialog")
    func goToFolderDismissedClosesTheDialog() async {
        let store = makeStore(makeState { $0.isGoToFolderPresented = true })

        await store.send(.goToFolderDismissed) {
            $0.isGoToFolderPresented = false
        }
    }

    struct PathCase: Sendable {
        let typed: String
        let expected: String?
    }

    @Test(
        "A typed folder path loses its slashes and spaces, and nothing left means no folder",
        arguments: [
            PathCase(typed: TestFolder.documents, expected: TestFolder.documents),
            PathCase(typed: " /Documents/Reports/ ", expected: TestPath.documentsReports),
            PathCase(typed: "//Photos//", expected: TestFolder.photos),
            PathCase(typed: "\n/Photos\n", expected: TestFolder.photos),
            PathCase(typed: "My Files/Trip 2026", expected: "My Files/Trip 2026"),
            PathCase(typed: "", expected: nil),
            PathCase(typed: " / ", expected: nil),
            PathCase(typed: "///", expected: nil),
        ]
    )
    func goToFolderPathTrimsWhatTheUserTyped(_ pathCase: PathCase) {
        #expect(MainTabFeature.goToFolderPath(pathCase.typed) == pathCase.expected)
    }

    @Test("Opened folders fill Recent Folders newest first without repeats, and clearing empties it")
    func openedFoldersFillRecentFoldersNewestFirstWithoutRepeats() async {
        let store = makeStore()

        await store.send(.browse(.navigateToDirectory(path: TestFolder.documents, title: TestFolder.documents))) {
            $0.browse.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: TestFolder.documents, title: TestFolder.documents)])
            $0.recentFolders = [TestFolder.documents]
        }
        await store.send(.browse(.navigateToDirectory(path: "Photos/Trip", title: "Trip"))) {
            $0.browse.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos/Trip", title: "Trip")])
            $0.recentFolders = ["Photos/Trip", TestFolder.documents]
        }
        await store.send(.browse(.navigateToDirectory(path: TestFolder.documents, title: TestFolder.documents))) {
            $0.browse.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: TestFolder.documents, title: TestFolder.documents)])
            $0.recentFolders = [TestFolder.documents, "Photos/Trip"]
        }
        await store.send(.recentFoldersCleared) {
            $0.recentFolders = []
        }
    }

    @Test("Recent Folders keep only the newest ten")
    func recentFoldersKeepOnlyTheNewestTen() async {
        let store = makeStore()
        var expected: [String] = []

        for index in 0 ..< 12 {
            let path = "Folder\(index)"
            expected.insert(path, at: 0)
            expected = Array(expected.prefix(10))
            await store.send(.browse(.navigateToDirectory(path: path, title: path))) {
                $0.browse.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: path, title: path)])
                $0.recentFolders = expected
            }
        }

        #expect(store.state.recentFolders == [
            "Folder11", "Folder10", "Folder9", "Folder8", "Folder7", "Folder6", "Folder5", "Folder4", "Folder3", "Folder2",
        ])
    }
}
