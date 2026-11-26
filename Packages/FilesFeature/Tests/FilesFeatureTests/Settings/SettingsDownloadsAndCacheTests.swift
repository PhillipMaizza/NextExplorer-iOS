import ClientCertificateFeature
import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import NetworkClient
import ShareUploads
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct SettingsDownloadsAndCacheTests: SettingsFeatureTestSupport {
    private func download(_ name: String, size: Int64) -> LocalDownload {
        LocalDownload(
            url: URL(fileURLWithPath: "/tmp/\(name)"),
            fileName: name,
            size: size,
            modifiedDate: MockDate.date
        )
    }

    @Test
    func removeAllDownloadsConfirmedDeletesEveryDownloadOfThisAccountAndDelegatesUpward() async {
        var state = makeState()
        state.removeAllDownloadsPhase = .confirming
        state.downloadsSize = 30
        state.$downloadScope.withLock { $0 = Constants.accountA }
        let downloads = [
            download(TestFile.aPDF, size: 10),
            download(TestFile.bPhoto, size: 20),
        ]
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
            $0.removeAllDownloadsPhase = .running
        }
        await store.receive(\.removeAllDownloadsResponse) {
            $0.removeAllDownloadsPhase = .idle
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
        state.removeAllDownloadsPhase = .confirming
        let downloads = [
            download(TestFile.aPDF, size: 10),
            download(TestFile.bPhoto, size: 20),
        ]
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
            $0.removeAllDownloadsPhase = .running
        }
        await store.receive(\.removeAllDownloadsResponse) {
            $0.removeAllDownloadsPhase = .idle
            $0.hasDownloads = false
        }
        await store.receive(\.delegate, .allDownloadsRemoved)

        #expect(attempted.value == [URL(fileURLWithPath: "/tmp/a.pdf"), URL(fileURLWithPath: "/tmp/b.jpg")])
    }

    @Test
    func clearCacheConfirmedClearsOnlyTheActiveAccountAndResetsTheSize() async {
        var state = makeState()
        state.clearCachePhase = .confirming
        state.cacheSize = 4096
        let previewClears = LockIsolated<[String]>([])
        let uploadThumbnailClears = LockIsolated<[String]>([])
        let store = TestStore(initialState: state) {
            SettingsFeature()
        } withDependencies: {
            $0.cacheScope = CacheScopeSource(current: { Constants.accountA })
            $0.localThumbnailStore.clearScope = { scope in uploadThumbnailClears.withValue { $0.append(scope) } }
            $0.previewCacheStore.clearAccount = { scope in previewClears.withValue { $0.append(scope) } }
        }

        await store.send(.clearCacheConfirmed) {
            $0.clearCachePhase = .running
        }
        await store.receive(\.clearCacheResponse) {
            $0.clearCachePhase = .idle
            $0.cacheSize = 0
        }

        #expect(previewClears.value == [Constants.accountA])
        #expect(
            uploadThumbnailClears.value == [Constants.accountA],
            "the thumbnails seeded for shared files are cache too"
        )
    }

    @Test
    func theCacheSizeCountsThePreviewsTheSavedCopiesAndTheSeededThumbnails() {
        var uploadThumbnails = LocalThumbnailStore.testValue
        uploadThumbnails.totalSizeBytes = { Constants.uploadThumbnailBytes }

        let size = SettingsFeature.cacheSizeBytes(
            scope: Constants.accountA,
            preview: PreviewCacheStore(size: { _ in Constants.previewBytes }, clear: {}, clearAccount: { _ in }),
            directories: .inMemory(),
            lists: .inMemory(),
            uploadThumbnails: uploadThumbnails
        )

        #expect(size == 1536)
    }

    @Test
    func theCacheSizeCountsOnlyTheAskingAccount() {
        var uploadThumbnails = LocalThumbnailStore.testValue
        uploadThumbnails.totalSizeBytes = {
            CacheAccountScope.current == Constants.accountA ? Constants.uploadThumbnailBytes : Constants.previewBytes
        }
        let preview = PreviewCacheStore(
            size: { $0 == Constants.accountA ? Constants.previewBytes : Constants.uploadThumbnailBytes },
            clear: {},
            clearAccount: { _ in }
        )

        let size = CacheAccountScope.withPinned(Constants.accountB) {
            SettingsFeature.cacheSizeBytes(
                scope: Constants.accountA,
                preview: preview,
                directories: .inMemory(),
                lists: .inMemory(),
                uploadThumbnails: uploadThumbnails
            )
        }

        #expect(size == 1536)
    }
}

private enum Constants {
    static let accountA = "account-a"
    static let accountB = "account-b"
    static let previewBytes: Int64 = 1024
    static let uploadThumbnailBytes: Int64 = 512
}
