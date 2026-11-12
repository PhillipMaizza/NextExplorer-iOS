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
    func everyMenuRowIsNamedAfterItsOwnSection() {
        let titles = SettingsMenuEntry.allCases.map(\.title)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == titles.count)
        #expect(SettingsMenuEntry.allCases.filter(\.isAdminOnly) == [.administration, .users])
    }
}

extension SettingsPagesTests {
    @Test
    func offlineEarnsAPageOnlyOnceSomethingIsDownloaded() {
        var state = SettingsFeature.State(serverURL: URL(string: "https://example.com")!, user: user)
        state.offlineSize = 0
        #expect(!state.isOfflineOnItsOwnPage)
        state.$offlineProgress.withLock { $0.phase = .preparing }
        #expect(state.isOfflineOnItsOwnPage, "a run in progress shows on the page")
        state.$offlineProgress.withLock { $0.phase = .idle }
        state.offlineSize = 1024
        #expect(state.isOfflineOnItsOwnPage)
    }
}
