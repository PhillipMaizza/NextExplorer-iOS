import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct MainTabSessionStartTests: MainTabTestSupport {
    @Test("A new session never shows the offline progress a previous account's run left behind")
    func aNewSessionClearsTheOfflineProgressOfThePreviousAccount() async {
        let state = makeState {
            $0.$offlineProgress.withLock {
                $0.phase = .downloading
                $0.currentName = TestFile.report
                $0.filesTotal = 3
            }
        }
        let store = makeStore(state) {
            $0.connectivity = ConnectivityClient(isOnline: { false }, events: { AsyncStream { $0.finish() } })
        }

        await store.send(.observeConnectivity) {
            $0.$offlineProgress.withLock { $0 = OfflineDownloadProgress() }
        }
        await store.receive(\.offline.autoSync)
        #expect(!store.state.isOfflineBarVisible)
    }
}
