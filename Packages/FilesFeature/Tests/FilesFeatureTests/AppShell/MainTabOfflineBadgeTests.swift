import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The dot on Offline: a finished run that stored files while another section was on screen shows
/// it, and opening Offline, however it is reached, clears it.
@Suite(.isolatedDependencies)
@MainActor
struct MainTabOfflineBadgeTests: MainTabTestSupport {
    private func downloadingState(on tab: MainTabFeature.Tab, filesDone: Int) -> MainTabFeature.State {
        makeState {
            $0.selectedTab = tab
            $0.$offlineProgress.withLock {
                $0.phase = .downloading
                $0.filesTotal = 2
                $0.filesDone = filesDone
            }
        }
    }

    private func finish(_ store: TestStoreOf<MainTabFeature>, showsDot: Bool) async {
        await store.send(.offline(.completed)) {
            $0.$offlineProgress.withLock { $0.phase = .completed }
            $0.hasUnseenOfflineFiles = showsDot
        }
        await store.receive(\.offlineManage.onAppear)
        await store.receive(\.offlineManage.usagesLoaded)
    }

    @Test("A run that kept files while another section was open puts a dot on Offline")
    func aFinishedRunElsewhereShowsTheDot() async {
        let store = makeStore(downloadingState(on: .browse, filesDone: 2))

        await finish(store, showsDot: true)
    }

    @Test("A run finished while Offline is open shows no dot")
    func aFinishedRunOnOfflineShowsNoDot() async {
        let store = makeStore(downloadingState(on: .downloads, filesDone: 2))

        await finish(store, showsDot: false)
    }

    @Test("A run that stored nothing new shows no dot")
    func aRunWithNothingNewShowsNoDot() async {
        let store = makeStore(downloadingState(on: .browse, filesDone: 0))

        await finish(store, showsDot: false)
    }

    @Test("Opening Offline clears the dot")
    func openingOfflineClearsTheDot() async {
        var state = downloadingState(on: .browse, filesDone: 2)
        state.hasUnseenOfflineFiles = true
        let store = makeStore(state)

        await store.send(.tabSelected(.downloads)) {
            $0.selectedTab = .downloads
            $0.hasUnseenOfflineFiles = false
        }
        await store.receive(\.offlineManage.onAppear)
        await store.receive(\.offlineManage.usagesLoaded)
    }

    @Test("Another section keeps the dot")
    func anotherSectionKeepsTheDot() async {
        var state = downloadingState(on: .browse, filesDone: 2)
        state.hasUnseenOfflineFiles = true
        let store = makeStore(state)

        await store.send(.tabSelected(.favorites)) {
            $0.selectedTab = .favorites
        }
    }
}
