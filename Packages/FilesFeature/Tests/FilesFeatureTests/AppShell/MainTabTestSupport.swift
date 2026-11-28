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

    var testDescription: String {
        name
    }
}

@MainActor
protocol MainTabTestSupport {}

extension MainTabTestSupport {
    var serverURL: URL {
        BrowseTestSupport.serverURL
    }

    var user: User {
        User.janeDoeFixture
    }

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

    typealias Source = MainTabSource
}

enum GoToPathFixture {
    static func metadata(_ path: String, kind: String) -> FileMetadata {
        FileMetadata(
            path: path,
            name: (path as NSString).lastPathComponent,
            kind: kind,
            size: .zero,
            dateModified: MockDate.date,
            dateCreated: MockDate.date
        )
    }

    static func folder(_ path: String) -> FileMetadata {
        metadata(path, kind: "directory")
    }

    static func file(_ path: String) -> FileMetadata {
        metadata(path, kind: "pdf")
    }
}
