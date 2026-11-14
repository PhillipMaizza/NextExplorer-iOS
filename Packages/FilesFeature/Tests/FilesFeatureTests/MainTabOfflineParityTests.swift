import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

private enum Fixture {
    static let docs = BrowseFixtures.folder(TestFolder.docs)
    static let photo = BrowseFixtures.file(TestFile.aPhoto, in: TestFolder.docs)
    static let report = BrowseFixtures.file(TestFile.report, in: TestFolder.docs)
    static let offlineFolder = "/offline"
}

/// Making something available offline does the same work wherever it is asked from: the same files are
/// kept and the same folder listings are saved, so a context menu pin browses offline like a Settings one.
@Suite(.isolatedDependencies)
@MainActor
struct MainTabOfflineParityTests: MainTabTestSupport {
    /// The app shell keeping into `offline`, every download reporting the file it fetched.
    private func store(
        offline: OfflineFileStore,
        onDownload: @escaping @Sendable (FileItem) -> Void,
        configure: @escaping (inout DependencyValues) -> Void = { _ in }
    ) -> StoreOf<MainTabFeature> {
        Store(initialState: makeState()) {
            MainTabFeature()
        } withDependencies: {
            $0.date = .constant(MockDate.date)
            $0.uuid = .incrementing
            $0.offlineFileStore = offline
            $0.filesClient.offlineDownloadFile = { _, item, onProgress in
                onDownload(item)
                onProgress(1)
                return URL(fileURLWithPath: Fixture.offlineFolder).appendingPathComponent(item.id)
            }
            configure(&$0)
        }
    }

    @Test(
        "A folder pinned from any screen keeps the same files and listing",
        arguments: [
            Source(name: "Browse context menu", action: .browse(.delegate(.offlinePinRequested([Fixture.docs])))),
            Source(name: "Favorites", action: .favorites(.delegate(.offlinePinRequested([Fixture.docs])))),
            Source(name: "Settings", action: .settings(.delegate(.startOfflineDownload([Fixture.docs])))),
            Source(name: "Offline tab", action: .downloads(.delegate(.offlinePinRequested([Fixture.docs])))),
        ]
    )
    func everyScreenKeepsTheSameFolder(_ source: Source) async {
        let offline = OfflineFileStore.inMemory()
        let downloaded = LockIsolated<[String]>([])
        let store = store(offline: offline, onDownload: { item in downloaded.withValue { $0.append(item.id) } }) {
            $0.filesClient.browse = { _, path in
                BrowseResult(items: [Fixture.photo, Fixture.report], access: BrowseTestSupport.fullAccess, path: path)
            }
        }

        await store.send(source.action).finish()

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: TestFolder.docs, isDirectory: true)])
        #expect(Set(downloaded.value) == [Fixture.photo.id, Fixture.report.id])
        #expect(offline.listing(TestFolder.docs)?.items == [Fixture.photo, Fixture.report])
    }

    @Test(
        "A file pinned from the context menu or Settings is downloaded the same way",
        arguments: [
            Source(name: "Browse context menu", action: .browse(.delegate(.offlinePinRequested([Fixture.photo])))),
            Source(name: "Settings", action: .settings(.delegate(.startOfflineDownload([Fixture.photo])))),
        ]
    )
    func aFileIsKeptTheSameWay(_ source: Source) async {
        let offline = OfflineFileStore.inMemory()
        let downloaded = LockIsolated<[FileItem]>([])
        let store = store(offline: offline, onDownload: { item in downloaded.withValue { $0.append(item) } })

        await store.send(source.action).finish()

        #expect(offline.pinnedRoots() == [OfflinePinnedRoot(path: Fixture.photo.id, isDirectory: false)])
        #expect(downloaded.value == [Fixture.photo], "The listed file, with its real date and size, is kept")
    }
}
