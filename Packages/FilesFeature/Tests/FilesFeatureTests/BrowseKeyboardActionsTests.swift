import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

/// The selection driven actions behind the Mac file table's keyboard and Edit menu commands. They
/// stage, delete, rename and inspect whatever rows the table has selected, without select mode.
@Suite(.isolatedDependencies)
@MainActor
struct BrowseKeyboardActionsTests {
    private let first = BrowseFixtures.file(TestFile.aText, in: TestFolder.docs)
    private let second = BrowseFixtures.file(TestFile.bText, in: TestFolder.docs)
    private let third = BrowseFixtures.file("c.txt", in: TestFolder.docs)

    private func access(canWrite: Bool = true, canDelete: Bool = true) -> FileAccess {
        FileAccess(
            canRead: true,
            canWrite: canWrite,
            canUpload: true,
            canDelete: canDelete,
            canShare: false,
            canDownload: true
        )
    }

    private func makeStore(
        items: [FileItem],
        selected: [FileItem],
        access: FileAccess? = nil,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<BrowseFeature> {
        var state = BrowseFixtures.state(
            TestFolder.docs,
            title: TestFolder.docs,
            items: items,
            access: access ?? self.access()
        )
        state.selectedItemIDs = Set(selected.map(\.id))
        return BrowseFixtures.store(state, configure: configure)
    }

    // MARK: Selection

    @Test("The table selection is tracked without entering select mode")
    func tableSelectionChangedTracksTheSelectionWithoutEnteringSelectMode() async {
        let store = makeStore(items: [first], selected: [])

        await store.send(.tableSelectionChanged([first.id])) {
            $0.selectedItemIDs = [first.id]
        }
    }

    // MARK: Clipboard

    @Test("Copy stages every selected item in listing order")
    func copySelectionStagesEverySelectedItemInListOrder() async {
        let store = makeStore(items: [first, second, third], selected: [third, first])

        await store.send(.copySelectionTapped) {
            $0.$clipboard.withLock { $0 = FileClipboard(items: [first, third], operation: .copy) }
            $0.clipboardStagedMessage = L10n.Browse.clipboardCopiedMany(2)
        }
    }

    @Test("Cut stages the selection as a move")
    func cutSelectionStagesAMove() async {
        let store = makeStore(items: [first], selected: [first])

        await store.send(.cutSelectionTapped) {
            $0.$clipboard.withLock { $0 = FileClipboard(items: [first], operation: .move) }
            $0.clipboardStagedMessage = L10n.Browse.clipboardCutOne(TestFile.aText)
        }
    }

    @Test("Cut is ignored without the right to delete")
    func cutSelectionIsIgnoredWithoutDeletePermission() async {
        let store = makeStore(items: [first], selected: [first], access: access(canDelete: false))

        await store.send(.cutSelectionTapped)
    }

    // MARK: Delete and rename

    @Test("Deleting one selected item asks to delete that item, checking its shares")
    func deleteSelectionOfOneItemRoutesToTheSingleDelete() async {
        let store = makeStore(items: [first], selected: [first]) {
            $0.filesClient.deleteImpact = { _, _ in DeleteImpact(shareCount: 0) }
        }

        await store.send(.deleteSelectionTapped)
        await store.receive(.deleteTapped(first)) {
            $0.deleteConfirmationItem = first
            $0.deleteImpactCheck = .checking
        }
        await store.receive(\.deleteImpactResponse.success) {
            $0.deleteImpactCheck = .loaded(DeleteImpact(shareCount: 0))
        }
    }

    @Test("Deleting several selected items asks to delete them together, checking their shares")
    func deleteSelectionOfSeveralItemsRoutesToTheBulkDelete() async {
        let store = makeStore(items: [first, second], selected: [first, second]) {
            $0.filesClient.deleteImpact = { _, _ in DeleteImpact(shareCount: 0) }
        }

        await store.send(.deleteSelectionTapped)
        await store.receive(.bulkDeleteTapped) {
            $0.bulkDeleteConfirmationIsPresented = true
            $0.deleteImpactCheck = .checking
        }
        await store.receive(\.deleteImpactResponse.success) {
            $0.deleteImpactCheck = .loaded(DeleteImpact(shareCount: 0))
        }
    }

    @Test("Delete is ignored without the right to delete")
    func deleteSelectionIsIgnoredWithoutDeletePermission() async {
        let store = makeStore(items: [first], selected: [first], access: access(canDelete: false))

        await store.send(.deleteSelectionTapped)
    }

    @Test("Rename needs exactly one selected item and the right to write")
    func renameSelectionNeedsExactlyOneItemAndWriteAccess() async {
        let several = makeStore(items: [first, second], selected: [first, second])
        await several.send(.renameSelectionTapped)

        let readOnly = makeStore(items: [first], selected: [first], access: access(canWrite: false))
        await readOnly.send(.renameSelectionTapped)

        let single = makeStore(items: [first], selected: [first])
        await single.send(.renameSelectionTapped)
        await single.receive(.renameTapped(first)) {
            $0.renameSheetItem = first
        }
    }

    // MARK: Inspector

    @Test("Get Info on the item already shown closes the inspector")
    func getInfoOnTheItemAlreadyShownClosesTheInspector() async {
        var state = BrowseFixtures.state(TestFolder.docs, title: TestFolder.docs, items: [first], access: access())
        state.selectedItemIDs = [first.id]
        state.infoItem = first
        let store = BrowseFixtures.store(state)

        await store.send(.infoSelectionTapped)
        await store.receive(\.infoDismissed) {
            $0.infoItem = nil
        }
    }
}
