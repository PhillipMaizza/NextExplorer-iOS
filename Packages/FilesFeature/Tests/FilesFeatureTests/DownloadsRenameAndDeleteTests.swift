import ComposableArchitecture
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// Renaming and bulk deleting local downloads, plus how a refresh failure is shown.
@Suite(.isolatedDependencies)
@MainActor
struct DownloadsRenameAndDeleteTests {
    private enum Constants {
        static let oldName = "old.pdf"
        static let newName = "new.pdf"
        static let folderPath = "/tmp/Downloads/"
        static let scope = "https://files.example.com|alice"
    }

    private func download(_ name: String) -> LocalDownload {
        LocalDownload(
            url: URL(fileURLWithPath: "\(Constants.folderPath)\(name)"),
            fileName: name,
            location: .documents,
            size: 10,
            modifiedDate: MockDate.date
        )
    }

    private func state(downloads: [LocalDownload], renameItem: LocalDownload? = nil) -> DownloadsFeature.State {
        var state = DownloadsFeature.State()
        state.downloads = IdentifiedArray(uniqueElements: downloads)
        state.renameItem = renameItem
        return state
    }

    // MARK: rename

    @Test
    func renameTappedOpensTheRenamePromptAndCancelClosesIt() async {
        let item = download(Constants.oldName)
        let store = TestStore(initialState: state(downloads: [item])) { DownloadsFeature() }

        await store.send(.renameTapped(item)) { $0.renameItem = item }
        await store.send(.renameCancelled) { $0.renameItem = nil }
    }

    @Test
    func confirmingARenameTrimsTheNameRenamesOnDiskAndReloadsTheAccountsList() async {
        let item = download(Constants.oldName)
        let renamed = download(Constants.newName)
        let renames = LockIsolated<[String]>([])
        let listedScopes = LockIsolated<[String]>([])
        var initial = state(downloads: [item], renameItem: item)
        initial.$downloadScope.withLock { $0 = Constants.scope }
        let store = TestStore(initialState: initial) {
            DownloadsFeature()
        } withDependencies: {
            $0.localDownloadStore.rename = { url, name in
                renames.withValue { $0.append("\(url.lastPathComponent)>\(name)") }
                return renamed.url
            }
            $0.localDownloadStore.list = { scope in
                listedScopes.withValue { $0.append(scope) }
                return [renamed]
            }
        }

        await store.send(.renameConfirmed("  \(Constants.newName)\n"))
        await store.receive(\.renameResponse.success) {
            $0.renameItem = nil
            $0.downloads = [renamed]
        }

        #expect(renames.value == ["\(Constants.oldName)>\(Constants.newName)"])
        #expect(listedScopes.value == [Constants.scope])
    }

    @Test(arguments: ["", "   \n", Constants.oldName, "  \(Constants.oldName) "])
    func aBlankOrUnchangedNameJustClosesThePromptWithoutTouchingTheDisk(_ name: String) async {
        let item = download(Constants.oldName)
        let store = TestStore(initialState: state(downloads: [item], renameItem: item)) { DownloadsFeature() }

        await store.send(.renameConfirmed(name)) { $0.renameItem = nil }
    }

    @Test
    func confirmingWithNoRenameTargetDoesNothing() async {
        let store = TestStore(initialState: state(downloads: [download(Constants.oldName)])) { DownloadsFeature() }

        await store.send(.renameConfirmed(Constants.newName))
    }

    struct FailureCase: Sendable {
        let error: any Error
        let expected: FilesClientError
    }

    nonisolated static let renameFailures = [
        FailureCase(error: CocoaError(.fileWriteFileExists), expected: .serverMessage(statusCode: 0, message: L10n.Downloads.errorNameExists)),
        FailureCase(error: CocoaError(.fileWriteInvalidFileName), expected: .serverMessage(statusCode: 0, message: L10n.Downloads.errorInvalidName)),
        FailureCase(error: CocoaError(.fileNoSuchFile), expected: .serverMessage(statusCode: 0, message: L10n.Downloads.errorMissing)),
        FailureCase(error: CocoaError(.fileReadNoSuchFile), expected: .serverMessage(statusCode: 0, message: L10n.Downloads.errorMissing)),
        FailureCase(error: CocoaError(.fileWriteOutOfSpace), expected: .serverMessage(statusCode: 0, message: L10n.Downloads.errorGeneric)),
        FailureCase(error: URLError(.badURL), expected: .serverMessage(statusCode: 0, message: L10n.Downloads.errorGeneric)),
        FailureCase(error: FilesClientError.offline, expected: .offline),
    ]

    @Test(arguments: renameFailures)
    func aFailedRenameClosesThePromptAndShowsTheSpecificReason(_ testCase: FailureCase) async {
        let item = download(Constants.oldName)
        let error = testCase.error
        let store = TestStore(initialState: state(downloads: [item], renameItem: item)) {
            DownloadsFeature()
        } withDependencies: {
            $0.localDownloadStore.rename = { _, _ in throw error }
        }

        await store.send(.renameConfirmed(Constants.newName))
        await store.receive(\.renameResponse.failure) {
            $0.renameItem = nil
            $0.actionErrorMessage = testCase.expected.userMessage
        }

        #expect(store.state.downloads == [item])
    }

    // MARK: bulk delete

    @Test
    func bulkDeleteNeedsASelectionBeforeItAsksForConfirmation() async {
        let store = TestStore(initialState: state(downloads: [download(Constants.oldName)])) { DownloadsFeature() }

        await store.send(.bulkDeleteTapped)
    }

    @Test
    func bulkDeleteAsksForConfirmationAndCancelDismissesItKeepingTheSelection() async {
        let item = download(Constants.oldName)
        var initial = state(downloads: [item])
        initial.selectedDownloadIDs = [item.id]
        let store = TestStore(initialState: initial) { DownloadsFeature() }

        await store.send(.bulkDeleteTapped) { $0.bulkDeleteConfirmationIsPresented = true }
        await store.send(.bulkDeleteCancelled) { $0.bulkDeleteConfirmationIsPresented = false }

        #expect(store.state.selectedDownloadIDs == [item.id])
    }

    @Test
    func confirmedBulkDeleteRemovesOnlyTheFilesThatWereActuallyDeleted() async {
        let first = download(Constants.oldName)
        let stuck = download("locked.pdf")
        let last = download(Constants.newName)
        var initial = state(downloads: [first, stuck, last])
        initial.isSelecting = true
        initial.selectedDownloadIDs = [first.id, stuck.id, last.id]
        initial.bulkDeleteConfirmationIsPresented = true
        let deleted = LockIsolated<[URL]>([])
        let store = TestStore(initialState: initial) {
            DownloadsFeature()
        } withDependencies: {
            $0.localDownloadStore.delete = { url in
                deleted.withValue { $0.append(url) }
                if url == stuck.url {
                    throw CocoaError(.fileWriteNoPermission)
                }
            }
        }

        await store.send(.bulkDeleteConfirmed) { $0.bulkDeleteConfirmationIsPresented = false }
        await store.receive(\.bulkDeleteResponse) {
            $0.downloads = [stuck]
            $0.isSelecting = false
            $0.selectedDownloadIDs = []
        }

        #expect(deleted.value == [first.url, stuck.url, last.url])
    }

    @Test
    func confirmingBulkDeleteWithNothingSelectedOnlyDismissesTheDialog() async {
        var initial = state(downloads: [download(Constants.oldName)])
        initial.bulkDeleteConfirmationIsPresented = true
        let store = TestStore(initialState: initial) { DownloadsFeature() }

        await store.send(.bulkDeleteConfirmed) { $0.bulkDeleteConfirmationIsPresented = false }
    }

    // MARK: refresh failures

    @Test
    func aFailedRefreshOfAnEmptyListIsAFullScreenError() async {
        let store = TestStore(initialState: state(downloads: [])) { DownloadsFeature() }

        await store.send(.downloadsResponse(.failure(.offline))) { $0.phase = .failed(FilesClientError.offline.userMessage) }
    }

    @Test
    func aFailedRefreshOverAPopulatedListKeepsTheListAndToasts() async {
        let item = download(Constants.oldName)
        let store = TestStore(initialState: state(downloads: [item])) { DownloadsFeature() }

        await store.send(.downloadsResponse(.failure(.offline))) {
            $0.phase = .loaded
            $0.actionErrorMessage = FilesClientError.offline.userMessage
        }

        #expect(store.state.downloads == [item])
    }
}
