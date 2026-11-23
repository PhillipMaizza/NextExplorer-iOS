import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
@testable import FolderPickerFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct DestinationPickerPersonalSpaceTests: DestinationPickerTestHelpers {
    private func rootStore(isPersonalEnabled: Bool) -> TestStoreOf<DestinationPickerFeature> {
        TestStore(
            initialState: DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: TestFolder.documents)
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                BrowseResult(items: [folder(TestFolder.photos, path: path)], access: access(), path: path)
            }
            $0.filesClient.serverFeatures = { _ in ServerFeatures(isPersonalEnabled: isPersonalEnabled) }
        }
    }

    @Test("Going up to the root lists My Files first when the server has personal folders")
    func theRootListsMyFilesFirst() async {
        let store = rootStore(isPersonalEnabled: true)

        await store.send(.breadcrumbTapped(path: "")) {
            $0.directoryPath = ""
            $0.phase = .loading
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: [folder(TestFolder.photos)]) }
        await store.receive(\.personalSpaceAvailable) {
            $0.folders.insert(DestinationPickerFeature.personalSpaceFolder, at: 0)
        }
        #expect(store.state.folders.first?.id == PersonalSpace.rootPath)
    }

    @Test("Without personal folders the root lists only the volumes")
    func theRootWithoutPersonalFolders() async {
        let store = rootStore(isPersonalEnabled: false)

        await store.send(.breadcrumbTapped(path: "")) {
            $0.directoryPath = ""
            $0.phase = .loading
        }
        await store.receive(\.foldersResponse.success) { finishLoad(&$0, folders: [folder(TestFolder.photos)]) }
    }

    @Test("A failed root listing gets no My Files, so Try Again shows the spinner")
    func aFailedRootListingGetsNoMyFiles() async {
        var state = DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: "")
        state.phase = .failed(L10n.Browse.destinationPickerLoadFailed)
        let store = TestStore(initialState: state) { DestinationPickerFeature() }

        await store.send(.personalSpaceAvailable)
        #expect(store.state.folders.isEmpty)
    }

    @Test("A short term finds My Files by the name it shows")
    func aShortTermMatchesTheShownName() {
        var state = DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: "")
        state.folders = [DestinationPickerFeature.personalSpaceFolder, folder(TestFolder.photos)]
        state.searchQuery = String(L10n.Browse.myFiles.prefix(1))

        #expect(state.displayedFolders.map(\.id) == [PersonalSpace.rootPath])
    }
}
