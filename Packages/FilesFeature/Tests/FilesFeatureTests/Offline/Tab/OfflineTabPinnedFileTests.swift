import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// Tapping a pinned item in the Offline tab: a folder opens in place, a file opens in a preview from
/// the copy kept on the device, and what that preview asks goes up to the app shell.
@Suite(.isolatedDependencies)
@MainActor
struct OfflineTabPinnedFileTests {
    private enum Constants {
        static let filePath = "Photos/a.jpg"
        static let keptSize: Int64 = 2_048
    }

    /// The pinned photo as the preview opens it: the size and date its copy was kept with.
    private var keptPhoto: FileItem {
        FileItem(
            name: TestFile.aPhoto,
            path: TestFolder.photos,
            dateModified: MockDate.date.addingTimeInterval(-600),
            size: Constants.keptSize,
            kind: TestKind.photo
        )
    }

    private func makeStore(_ state: OfflineTabFeature.State? = nil) -> TestStoreOf<OfflineTabFeature> {
        TestStore(initialState: state ?? OfflineTabFeature.State(serverURL: BrowseTestSupport.serverURL)) {
            OfflineTabFeature()
        } withDependencies: {
            $0.date = .constant(MockDate.date)
            $0.offlineFileStore = .inMemory(copyMetadata: [
                Constants.filePath: OfflineCopyMetadata(
                    dateModified: MockDate.date.addingTimeInterval(-600),
                    size: Constants.keptSize
                ),
            ])
        }
    }

    private func openPhoto(_ store: TestStoreOf<OfflineTabFeature>) async {
        await store.send(.pinnedItemTapped(OfflinePinnedRoot(path: Constants.filePath, isDirectory: false)))
        await store.receive(\.pinnedFileTapped) {
            var host = BrowseFeature.State.previewHost(
                for: keptPhoto,
                serverURL: BrowseTestSupport.serverURL,
                folderTitle: TestFolder.photos
            )
            host.offlineItemIDs = [Constants.filePath]
            host.offlinePinnedItemIDs = [Constants.filePath]
            $0.previewHost = host
        }
        await store.receive(\.previewHost.rowTapped)
    }

    @Test("A pinned file opens in a preview of the copy kept on the device")
    func aPinnedFileOpensItsKeptCopy() async {
        let store = makeStore()

        await openPhoto(store)

        #expect(store.state.previewHost?.previewItem == keptPhoto)
        #expect(store.state.path.isEmpty)
    }

    @Test("A pinned folder opens in place, not in a preview")
    func aPinnedFolderOpensInPlace() async {
        let store = makeStore()

        await store.send(.pinnedItemTapped(OfflinePinnedRoot(path: TestFolder.photos, isDirectory: true)))
        await store.receive(\.openFolderTapped) {
            var screen = BrowseFeature.State(
                serverURL: BrowseTestSupport.serverURL,
                directoryPath: TestFolder.photos,
                title: TestFolder.photos
            )
            screen.isKeptOffline = true
            $0.path[id: 0] = screen
        }
    }

    @Test("Closing the preview returns to the tab")
    func closingThePreviewReturnsToTheTab() async {
        let store = makeStore()
        await openPhoto(store)

        await store.send(.previewHost(.presented(.previewDismissed))) {
            $0.previewHost = nil
        }
    }

    @Test("Seeing the file's share links closes the preview and goes to Shared")
    func viewingSharesGoesToShared() async {
        let store = makeStore()
        await openPhoto(store)

        await store.send(.viewSharesFromPreviewTapped) {
            $0.previewHost = nil
        }
        await store.receive(.delegate(.goToSharedTab))
    }

    @Test("The preview knows its file is pinned, so it offers Remove from Offline")
    func thePreviewKnowsItsFileIsPinned() async {
        let store = makeStore()
        await openPhoto(store)

        #expect(store.state.previewHost?.offlinePinnedItemIDs == [keptPhoto.id])
        #expect(store.state.previewHost?.offlineItemIDs == [keptPhoto.id])
        #expect(store.state.previewHost?.access == nil, "Offered even before any folder access is known")
    }

    @Test("Remove from Offline in the preview asks first, then unpins and returns to the tab")
    func removingFromOfflineClosesThePreview() async {
        let store = makeStore()
        await openPhoto(store)

        await store.send(.previewHost(.presented(.offlineToggleTapped(keptPhoto)))) {
            $0.previewHost?.offlineRemoval = OfflineRemovalRequest(paths: [keptPhoto.id], names: [keptPhoto.name])
        }
        await store.send(.previewHost(.presented(.delegate(.offlineUnpinRequested(path: Constants.filePath))))) {
            $0.previewHost = nil
        }
        await store.receive(.delegate(.offlineUnpinRequested(path: Constants.filePath)))
    }

    @Test("Downloading or saving it from the preview goes up to the shell")
    func previewRequestsGoUp() async {
        let store = makeStore()
        await openPhoto(store)

        await store.send(.previewHost(.presented(.delegate(.downloadRequested([keptPhoto])))))
        await store.receive(.delegate(.downloadRequested([keptPhoto])))
        await store.send(.previewHost(.presented(.delegate(.saveRequested([BrowseFixtures.saveRequest])))))
        await store.receive(.delegate(.saveRequested([BrowseFixtures.saveRequest])))
    }

    @Test("Without a server nothing opens")
    func withoutAServerNothingOpens() async {
        let store = makeStore(OfflineTabFeature.State(serverURL: nil))

        await store.send(.pinnedItemTapped(OfflinePinnedRoot(path: Constants.filePath, isDirectory: false)))
        await store.receive(\.pinnedFileTapped)
    }
}
