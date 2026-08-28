import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct DestinationPickerFeatureTests {
    private let serverURL = URL(string: "https://example.com")!

    private nonisolated func folder(_ name: String, path: String = "") -> FileItem {
        FileItem(name: name, path: path, dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "directory")
    }

    private nonisolated func file(_ name: String, path: String = "") -> FileItem {
        FileItem(name: name, path: path, dateModified: Date(timeIntervalSince1970: 1), size: 0, kind: "txt")
    }

    private nonisolated func access() -> FileAccess {
        FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true)
    }

    @Test
    func onAppearLoadsFoldersOnlyDroppingFiles() async {
        let store = TestStore(
            initialState: DestinationPickerFeature.State(serverURL: serverURL, items: [file("a.txt", path: "Inbox")])
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [self.folder("Documents"), self.file("readme.txt")], access: self.access(), path: "")
            }
        }

        await store.send(.onAppear) { $0.isLoading = true }
        await store.receive(\.foldersResponse.success) {
            $0.isLoading = false
            $0.currentAccess = self.access()
            $0.folders = [self.folder("Documents")]
        }
    }

    @Test
    func uploadModeConfirmStaysDisabledUntilTheFolderReportsUploadAccess() {
        let atRoot = DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: "")
        #expect(atRoot.purpose == .upload)
        #expect(atRoot.canConfirm == false)

        var inFolder = DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: "Documents")
        #expect(inFolder.directoryPath == "Documents")
        #expect(inFolder.canConfirm == false) // access not loaded yet

        inFolder.currentAccess = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true)
        #expect(inFolder.canConfirm == true)

        inFolder.currentAccess = FileAccess(canRead: true, canWrite: true, canUpload: false, canDelete: true, canShare: false, canDownload: true)
        #expect(inFolder.canConfirm == false)
    }

    @Test
    func uploadModeConfirmEmitsTheChosenDestination() async {
        var state = DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: "Documents")
        state.directoryPath = "Documents/Reports"
        state.currentAccess = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true)

        let store = TestStore(initialState: state) { DestinationPickerFeature() }

        await store.send(.confirmTapped)
        await store.receive(.delegate(.confirmed(destination: "Documents/Reports")))
    }

    @Test
    func folderTappedDrillsIntoTheChild() async {
        let store = TestStore(
            initialState: DestinationPickerFeature.State(serverURL: serverURL, items: [file("a.txt", path: "Inbox")])
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, path in
                BrowseResult(
                    items: path == "Documents" ? [self.folder("Work", path: "Documents")] : [self.folder("Documents")],
                    access: self.access(), path: path
                )
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.foldersResponse.success)
        await store.send(.folderTapped(folder("Documents"))) {
            $0.directoryPath = "Documents"
        }
        await store.receive(\.foldersResponse.success) {
            $0.folders = [self.folder("Work", path: "Documents")]
        }
    }

    @Test
    func breadcrumbTappedJumpsStraightToThatPath() async {
        var state = DestinationPickerFeature.State(serverURL: serverURL, items: [file("a.txt", path: "Inbox")])
        state.directoryPath = "Documents/Work"

        let store = TestStore(initialState: state) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in BrowseResult(items: [], access: self.access(), path: "") }
        }
        store.exhaustivity = .off

        await store.send(.breadcrumbTapped(path: "Documents")) {
            $0.directoryPath = "Documents"
        }
        await store.receive(\.foldersResponse.success)
    }

    @Test
    func loadFailureSurfacesAReadableErrorAndRetryReloads() async {
        let store = TestStore(
            initialState: DestinationPickerFeature.State(serverURL: serverURL, items: [file("a.txt", path: "Inbox")])
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.filesClient.browse = { _, _ in throw FilesClientError.server(statusCode: 500) }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.foldersResponse.failure) {
            $0.isLoading = false
            $0.errorMessage = L10n.Browse.destinationPickerLoadFailed
        }
        await store.send(.retryTapped) { $0.isLoading = true }
        await store.receive(\.foldersResponse.failure)
    }

    @Test
    func confirmTappedEmitsTheChosenDestination() async {
        var state = DestinationPickerFeature.State(serverURL: serverURL, items: [file("a.txt", path: "Inbox")])
        state.directoryPath = "Documents"

        let store = TestStore(initialState: state) { DestinationPickerFeature() }

        await store.send(.confirmTapped)
        await store.receive(.delegate(.confirmed(destination: "Documents")))
    }

    @Test
    func confirmIsBlockedIntoTheItemsOwnParentAndIntoItself() {
        var parent = DestinationPickerFeature.State(serverURL: serverURL, items: [file("a.txt", path: "Inbox")])
        parent.directoryPath = "Inbox"
        #expect(parent.canConfirm == false)

        var intoItself = DestinationPickerFeature.State(serverURL: serverURL, items: [folder("Photos", path: "Media")])
        intoItself.directoryPath = "Media/Photos/2024"
        #expect(intoItself.canConfirm == false)

        var ok = DestinationPickerFeature.State(serverURL: serverURL, items: [file("a.txt", path: "Inbox")])
        ok.directoryPath = "Documents"
        #expect(ok.canConfirm == true)
    }

    @Test
    func rootIsNeverAValidDestination() {
        let state = DestinationPickerFeature.State(serverURL: serverURL, items: [file("a.txt", path: "")])
        #expect(state.directoryPath == "")
        #expect(state.canConfirm == false)
    }

    @Test
    func opensInTheFolderTheItemsAlreadyLiveIn() {
        let state = DestinationPickerFeature.State(
            serverURL: serverURL, items: [file("a.txt", path: "Documents/Reports")]
        )
        #expect(state.directoryPath == "Documents/Reports")
        // Confirming right here would be a no-op move into the item's own parent.
        #expect(state.canConfirm == false)
    }

    @Test
    func searchRunsRecursivelyScopedToCurrentFolderAndClearsOnDrillDown() async {
        let clock = TestClock()
        let searchScope = LockIsolated<String?>(nil)
        let store = TestStore(
            initialState: DestinationPickerFeature.State(serverURL: serverURL, items: [file("a.txt", path: "Media")])
        ) {
            DestinationPickerFeature()
        } withDependencies: {
            $0.continuousClock = clock
            $0.filesClient.browse = { _, _ in
                BrowseResult(items: [self.folder("Photos", path: "Media")], access: self.access(), path: "Media")
            }
            $0.filesClient.search = { _, path, _, _ in
                searchScope.setValue(path)
                return [
                    SearchResultItem(name: "Summer", path: "Media/Photos/2024", kind: "dir"),
                    SearchResultItem(name: "notes.txt", path: "Media/Photos", kind: "txt"),
                ]
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.foldersResponse.success)

        await store.send(.searchQueryChanged("sum")) {
            $0.searchQuery = "sum"
            $0.isSearching = true
        }
        await clock.advance(by: .milliseconds(250))
        await store.receive(\.searchResultsResponse.success) {
            $0.isSearching = false
            $0.searchResults = [SearchResultItem(name: "Summer", path: "Media/Photos/2024", kind: "dir")]
        }
        #expect(searchScope.value == "Media")

        await store.send(.searchResultTapped(SearchResultItem(name: "Summer", path: "Media/Photos/2024", kind: "dir"))) {
            $0.directoryPath = "Media/Photos/2024/Summer"
            $0.searchQuery = ""
            $0.searchResults = nil
        }
    }
}
