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
struct SettingsDownloadsAndCacheTests: SettingsFeatureTestSupport {
    private func download(_ name: String, location: DownloadLocation, size: Int64) -> LocalDownload {
        LocalDownload(url: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, location: location, size: size, modifiedDate: MockDate.date)
    }

    @Test
    func removeAllDownloadsConfirmedDeletesEveryDownloadOfThisAccountAndDelegatesUpward() async {
        var state = makeState()
        state.removeAllDownloadsConfirmationIsPresented = true
        state.downloadsSize = 30
        state.$downloadScope.withLock { $0 = Constants.accountA }
        let downloads = [download(TestFile.aPDF, location: .documents, size: 10), download(TestFile.bPhoto, location: .cache, size: 20)]
        let listedScopes = LockIsolated<[String]>([])
        let deletedURLs = LockIsolated<[URL]>([])
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { scope in
                listedScopes.withValue { $0.append(scope) }
                return downloads
            }
            $0.localDownloadStore.delete = { url in deletedURLs.withValue { $0.append(url) } }
        }

        await store.send(.removeAllDownloadsConfirmed) {
            $0.removeAllDownloadsConfirmationIsPresented = false
            $0.isRemovingAllDownloads = true
        }
        await store.receive(\.removeAllDownloadsResponse) {
            $0.isRemovingAllDownloads = false
            $0.hasDownloads = false
            $0.downloadsSize = 0
        }
        await store.receive(\.delegate, .allDownloadsRemoved)

        #expect(listedScopes.value == [Constants.accountA])
        #expect(deletedURLs.value == [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.jpg")])
    }

    @Test
    func removeAllDownloadsConfirmedIsBestEffortWhenOneFileFailsToDelete() async {
        var state = makeState()
        state.removeAllDownloadsConfirmationIsPresented = true
        let downloads = [download(TestFile.aPDF, location: .documents, size: 10), download(TestFile.bPhoto, location: .cache, size: 20)]
        let attempted = LockIsolated<[URL]>([])
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.localDownloadStore.list = { _ in downloads }
            $0.localDownloadStore.delete = { url in
                attempted.withValue { $0.append(url) }
                if url.lastPathComponent == TestFile.aPDF {
                    throw FilesClientError.network("permission denied")
                }
            }
        }

        await store.send(.removeAllDownloadsConfirmed) {
            $0.removeAllDownloadsConfirmationIsPresented = false
            $0.isRemovingAllDownloads = true
        }
        await store.receive(\.removeAllDownloadsResponse) {
            $0.isRemovingAllDownloads = false
            $0.hasDownloads = false
        }
        await store.receive(\.delegate, .allDownloadsRemoved)

        #expect(attempted.value == [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.jpg")])
    }

    @Test(arguments: [false, true])
    func clearCacheConfirmedClearsTheCacheAndResetsTheSizeEvenWhenClearingFails(clearFails: Bool) async {
        var state = makeState()
        state.clearCacheConfirmationIsPresented = true
        state.cacheSize = 4096
        let clears = LockIsolated(0)
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.previewCacheStore.clear = {
                clears.withValue { $0 += 1 }
                if clearFails {
                    throw FilesClientError.network("permission denied")
                }
            }
        }

        await store.send(.clearCacheConfirmed) {
            $0.clearCacheConfirmationIsPresented = false
            $0.isClearingCache = true
        }
        await store.receive(\.clearCacheResponse) {
            $0.isClearingCache = false
            $0.cacheSize = 0
        }

        #expect(clears.value == 1)
    }
}

private enum Constants {
    static let accountA = "account-a"
}
