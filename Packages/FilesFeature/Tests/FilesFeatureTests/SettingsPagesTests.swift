import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct SettingsPagesTests {
    private let user = User(id: "1", username: "jdoe", email: "jane@example.com", displayName: "Jane", roles: [])

    @Test
    func theOpenPagesLiveInTheReducerSoTheyOutliveTheView() async {
        let store = TestStore(initialState: SettingsFeature.State(serverURL: URL(string: "https://example.com")!, user: user)) {
            SettingsFeature()
        }

        await store.send(.pagesChanged([.offline])) {
            $0.pages = [.offline]
        }
        await store.send(.pagesChanged([])) {
            $0.pages = []
        }
    }

    @Test
    func everyPageIsNamedAfterItsSection() {
        #expect(SettingsPage.allCases.map(\.title).allSatisfy { !$0.isEmpty })
        #expect(Set(SettingsPage.allCases.map(\.title)).count == SettingsPage.allCases.count)
    }
}
