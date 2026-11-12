import ClientCertificateFeature
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
struct SettingsAppearTests: SettingsFeatureTestSupport {
    // `onAppear` starts about ten effects at once, several of them synchronous reads (downloads,
    // caches, certificate) whose actions arrive in no fixed order, and ordering them would need the
    // process wide serial executor. So each answer it delivers is sent directly instead.

    @Test
    func theDownloadsCheckAnswersSetTheirState() async {
        let store = makeStore()

        await store.send(.hasDownloadsResponse(false)) { $0.hasDownloads = false }
        await store.send(.downloadsSizeResponse(30)) { $0.downloadsSize = 30 }
    }

    @Test
    func theCacheAndOfflineSizeAnswersSetTheirState() async {
        let store = makeStore()

        await store.send(.cacheSizeResponse(4096)) { $0.cacheSize = 4096 }
        await store.send(.offlineSizeResponse(2048)) { $0.offlineSize = 2048 }
    }

    @Test
    func theClientCertificateAnswerShowsOnTheRow() async {
        let store = makeStore()
        let summary = ClientCertificateSummary(subject: TestCertificate.subject)

        await store.send(.clientCertificateStatusLoaded(nil)) { $0.clientCertificateStatus = .empty }
        await store.send(.clientCertificateStatusLoaded(summary)) { $0.clientCertificateStatus = .installed(summary) }
    }

    @Test
    func theLoadedPreferencesReplaceTheSharedOnes() async {
        var state = makeState()
        state.isLoadingPreferences = true
        let store = makeStore(state: state)

        await store.send(.preferencesResponse(.success(UserPreferences(showHiddenFiles: true, showThumbnails: false)))) {
            $0.isLoadingPreferences = false
            $0.$preferences.withLock { $0 = UserPreferences(showHiddenFiles: true, showThumbnails: false) }
        }
    }

    @Test
    func aFailedPreferencesLoadKeepsTheSharedOnes() async {
        var state = makeState()
        state.isLoadingPreferences = true
        let store = makeStore(state: state)

        await store.send(.preferencesResponse(.failure(.sessionExpired))) { $0.isLoadingPreferences = false }

        #expect(store.state.preferences == UserPreferences())
    }

    @Test
    func serverUsageStaysHiddenWhenTheFeatureIsOff() async {
        let volumeReads = LockIsolated(0)
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.volumes = { _ in
                volumeReads.withValue { $0 += 1 }
                return []
            }
        }

        await store.send(.serverFeaturesResponse(ServerFeatures(isVolumeUsageEnabled: false)))

        #expect(!store.state.isVolumeUsageEnabled)
        #expect(store.state.serverUsage.isEmpty)
        #expect(volumeReads.value == 0)
    }

    @Test
    func serverUsageLoadsAVolumeListThenFillsInEachBar() async {
        let homeGate = AsyncGate()
        let media = Volume(name: "media", path: "media")
        let home = Volume(name: "home", path: "home")
        let mediaUsage = StorageUsage(path: "media", size: 40, free: 60, total: 100)
        let homeUsage = StorageUsage(path: "home", size: 0, free: 0, total: 0)
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.volumes = { _ in [media, home] }
            $0.filesClient.fetchUsage = { _, path in
                if path == "home" {
                    try await homeGate.wait()
                    return homeUsage
                }
                return mediaUsage
            }
        }

        await store.send(.serverFeaturesResponse(ServerFeatures(isVolumeUsageEnabled: true))) { $0.isVolumeUsageEnabled = true }
        await store.receive(\.volumesResponse) {
            $0.serverUsage = [
                SettingsFeature.VolumeUsage(volume: media, usage: nil),
                SettingsFeature.VolumeUsage(volume: home, usage: nil),
            ]
        }
        await store.receive(\.serverUsageResponse) { $0.serverUsage[id: "media"]?.usage = mediaUsage }
        homeGate.open()
        await store.receive(\.serverUsageResponse) { $0.serverUsage[id: "home"]?.usage = homeUsage }

        // `home` came back all zeros: still stored, the view decides not to draw a bar.
        #expect(store.state.serverUsage[id: "home"]?.usage?.isMeaningful == false)
        #expect(store.state.serverUsage[id: "media"]?.usage?.used == 40)
    }

    @Test
    func aVolumeWhoseUsageFailsKeepsItsRowWithoutABar() async {
        let media = Volume(name: "media", path: "media")
        let store = TestStore(initialState: makeState()) {
            SettingsFeature()
        } withDependencies: {
            $0.filesClient.volumes = { _ in [media] }
            $0.filesClient.fetchUsage = { _, _ in throw FilesClientError.offline }
        }

        await store.send(.serverFeaturesResponse(ServerFeatures(isVolumeUsageEnabled: true))) { $0.isVolumeUsageEnabled = true }
        await store.receive(\.volumesResponse) { $0.serverUsage = [SettingsFeature.VolumeUsage(volume: media, usage: nil)] }
        await store.receive(\.serverUsageResponse)

        #expect(store.state.serverUsage[id: "media"]?.usage == nil)
    }
}
