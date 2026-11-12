import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// A tab action that two screens send the same way, so one test covers both sources.
struct MainTabSource: Sendable, CustomTestStringConvertible {
    let name: String
    let action: MainTabFeature.Action

    var testDescription: String { name }
}

@MainActor
protocol MainTabTestSupport {
}

extension MainTabTestSupport {
    var serverURL: URL { BrowseTestSupport.serverURL }
    var user: User { User(id: "1", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: []) }

    func makeState(_ mutate: (inout MainTabFeature.State) -> Void = { _ in }) -> MainTabFeature.State {
        var state = MainTabFeature.State(serverURL: serverURL, user: user)
        mutate(&state)
        return state
    }

    func makeStore(
        _ state: MainTabFeature.State? = nil,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<MainTabFeature> {
        TestStore(initialState: state ?? makeState()) {
            MainTabFeature()
        } withDependencies: {
            $0.date = .constant(MockDate.date)
            $0.uuid = .incrementing
            configure(&$0)
        }
    }

    /// A finished change in this window is broadcast to the extra Mac windows.
    func broadcastFolders(_ state: inout MainTabFeature.State, _ folders: [String]) {
        #if os(macOS)
            state.folderWindowSync = FolderWindowSync(revision: 1, change: .folders(folders), origin: nil)
        #endif
    }

    typealias Source = MainTabSource
}
