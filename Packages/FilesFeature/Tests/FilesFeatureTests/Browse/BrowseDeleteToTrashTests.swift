import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct BrowseDeleteToTrashTests {
    private enum Constants {
        static let retentionDays = 30
        static let tooLargeSize: Int64 = 3_000_000_000
        static let budget: Int64 = 2_000_000_000
        static let folderPath = "Docs"
    }

    private let photo = BrowseFixtures.file(TestFile.vacationPhoto, in: Constants.folderPath)
    private let notes = BrowseFixtures.file(TestFile.aText, in: Constants.folderPath)

    private var allToTrash: DeleteImpact {
        DeleteImpact(shareCount: 1, trash: .init(isEnabled: true, retentionDays: Constants.retentionDays, items: [
            .init(path: photo.id, goesToTrash: true, shareCount: 1),
        ]))
    }

    private var mixed: DeleteImpact {
        DeleteImpact(shareCount: 0, trash: .init(isEnabled: true, retentionDays: Constants.retentionDays, items: [
            .init(path: photo.id, goesToTrash: true),
            .init(path: notes.id, goesToTrash: false, reason: .otherDevice),
        ]))
    }

    // MARK: Confirmation copy

    @Test("A plan that sends the item to the trash says how long the trash keeps it and how its links behave")
    func copyForTheTrash() {
        let message = BrowseDeleteCopy.message(.loaded(allToTrash))

        #expect(message == [
            L10n.Trash.deleteMessage(Constants.retentionDays),
            L10n.Trash.deleteLinkedShares(1),
        ].joined(separator: "\n\n"))
    }

    @Test("A mixed plan counts what skips the trash and says why")
    func copyForAMixedPlan() {
        let message = BrowseDeleteCopy.message(.loaded(mixed))

        #expect(message == [
            L10n.Trash.deleteMessage(Constants.retentionDays),
            L10n.Trash.deleteSomePermanent(1),
            L10n.Trash.reasonOtherDevice,
        ].joined(separator: "\n\n"))
    }

    @Test("Without a trash plan, while checking or after a failed check, the copy warns it cannot be undone")
    func copyWithoutATrash() {
        #expect(BrowseDeleteCopy.message(.checking) == L10n.Browse.deleteMessage)
        #expect(BrowseDeleteCopy.message(.loaded(DeleteImpact(shareCount: 0))) == L10n.Browse.deleteMessage)
        #expect(BrowseDeleteCopy.message(.unavailable)
            == L10n.Browse.deleteMessage + "\n\n" + L10n.Browse.deleteLinkedSharesUnavailable)
    }

    @Test("A switched off trash adds no reason line: the warning already says it is for good")
    func copyWithTheTrashOff() {
        let impact = DeleteImpact(
            shareCount: 0,
            trash: .init(isEnabled: false, retentionDays: Constants.retentionDays, items: [
                .init(path: photo.id, goesToTrash: false, reason: .disabled),
            ])
        )
        #expect(BrowseDeleteCopy.message(.loaded(impact)) == L10n.Browse.deleteMessage)
    }

    // MARK: Delete

    @Test("Moving to the trash removes the row, writes the listing through and announces the trash")
    func moveToTrash() async throws {
        let cache = DirectoryCacheStore.inMemory()
        var state = BrowseFixtures.loadedState(Constants.folderPath, items: [photo, notes])
        state.deleteConfirmationItem = photo
        state.deleteImpactCheck = .loaded(allToTrash)
        let asked = LockIsolated<[Bool]>([])
        let store = BrowseFixtures.store(state) {
            $0.directoryCacheStore = cache
            $0.filesClient.deleteItems = { _, _, permanent, _ in
                asked.withValue { $0.append(permanent) }
                return DeleteOutcome(items: [.init(path: "Docs/photo", status: .trashed)])
            }
        }

        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationItem = nil
            $0.deleteImpactCheck = .idle
            $0.isPerformingFileAction = true
        }
        await store.receive(\.deleteResponse.success) {
            $0.isPerformingFileAction = false
            $0.items = [notes]
            $0.trashNotice = .init(count: 1, sequence: 1)
        }
        #expect(asked.value == [false])
        let cached = try #require(cache.read(serverURL: BrowseTestSupport.serverURL, path: Constants.folderPath))
        #expect(cached.items.map(\.name) == [TestFile.aText])
    }

    @Test("Delete Permanently asks the server for a permanent delete")
    func deletePermanently() async {
        var state = BrowseFixtures.state(items: [photo])
        state.deleteConfirmationItem = photo
        let asked = LockIsolated<[Bool]>([])
        let store = BrowseFixtures.store(state) {
            $0.filesClient.deleteItems = { _, _, permanent, _ in
                asked.withValue { $0.append(permanent) }
                return DeleteOutcome(items: [.init(path: "Docs/photo", status: .deleted)])
            }
        }

        await store.send(.deletePermanentlyConfirmed(fromPreview: false)) {
            $0.deleteConfirmationItem = nil
            $0.isPerformingFileAction = true
        }
        await store.receive(\.deleteResponse.success) {
            $0.isPerformingFileAction = false
            $0.items = []
        }
        #expect(asked.value == [true])
    }

    @Test("An item the trash refused stays listed, and agreeing deletes it for good")
    func keptItemThenPermanentDelete() async {
        var state = BrowseFixtures.state(items: [photo, notes])
        state.selectedItemIDs = [photo.id, notes.id]
        state.isSelecting = true
        let calls = LockIsolated<[Bool]>([])
        let answer: @Sendable ([FileItem], Bool) -> DeleteOutcome = { items, permanent in
            calls.withValue { $0.append(permanent) }
            if permanent {
                return DeleteOutcome(items: items.map { .init(path: $0.id, status: .deleted) })
            }
            // Answers come in the order asked: pair them with the request the reducer built.
            return DeleteOutcome(items: items.map {
                $0.id == photo.id
                    ? .init(
                        path: $0.id,
                        status: .kept,
                        reason: .tooLarge,
                        size: Constants.tooLargeSize,
                        budgetBytes: Constants.budget
                    )
                    : .init(path: $0.id, status: .trashed)
            })
        }
        let store = BrowseFixtures.store(state) {
            $0.filesClient.deleteItems = { _, items, permanent, _ in answer(items, permanent) }
        }
        let kept = BrowseFeature.KeptDelete(
            item: photo,
            reason: .tooLarge,
            size: Constants.tooLargeSize,
            budgetBytes: Constants.budget
        )

        await store.send(.bulkDeleteConfirmed) {
            $0.isBulkActionInFlight = true
            $0.bulkDeleteProgress = 0
        }
        await store.receive(\.bulkDeleteResponse.success) {
            $0.isBulkActionInFlight = false
            $0.bulkDeleteProgress = nil
            $0.isSelecting = false
            $0.selectedItemIDs = []
            $0.items = [photo]
            $0.keptDeletes = [kept]
            $0.trashNotice = .init(count: 1, sequence: 1)
        }
        await store.send(.keptDeletePermanentlyConfirmed) {
            $0.keptDeletes = []
            $0.isPerformingFileAction = true
        }
        await store.receive(\.deleteResponse.success) {
            $0.isPerformingFileAction = false
            $0.items = []
        }
        #expect(calls.value == [false, true])
    }

    @Test("Leaving a refused item where it is closes the prompt and keeps the row")
    func keptItemDismissed() async {
        var state = BrowseFixtures.state(items: [photo])
        state.keptDeletes = [.init(item: photo, reason: .otherDevice, size: nil, budgetBytes: nil)]
        let store = BrowseFixtures.store(state)

        await store.send(.keptDeleteDismissed) {
            $0.keptDeletes = []
        }
    }

    @Test("Bulk Delete Permanently sends the permanent flag")
    func bulkDeletePermanently() async {
        var state = BrowseFixtures.state(items: [photo])
        state.selectedItemIDs = [photo.id]
        state.isSelecting = true
        state.bulkDeletePhase = .confirming
        let asked = LockIsolated<[Bool]>([])
        let store = BrowseFixtures.store(state) {
            $0.filesClient.deleteItems = { _, _, permanent, _ in
                asked.withValue { $0.append(permanent) }
                return DeleteOutcome()
            }
        }

        await store.send(.bulkDeletePermanentlyConfirmed) {
            $0.bulkDeletePhase = .idle
            $0.isBulkActionInFlight = true
            $0.bulkDeleteProgress = 0
        }
        await store.receive(\.bulkDeleteResponse.success) {
            $0.isBulkActionInFlight = false
            $0.bulkDeleteProgress = nil
            $0.isSelecting = false
            $0.selectedItemIDs = []
            $0.items = []
        }
        #expect(asked.value == [true])
    }

    @Test("A second trash delete shows its toast again")
    func noticeRepeats() async {
        var state = BrowseFixtures.state(items: [notes])
        state.trashNotice = .init(count: 1, sequence: 4)
        state.deleteConfirmationItem = notes
        let store = BrowseFixtures.store(state) {
            $0.filesClient.deleteItems = { _, items, _, _ in DeleteOutcome(items: items.map { .init(
                path: $0.id,
                status: .trashed
            ) }) }
        }

        await store.send(.deleteConfirmed) {
            $0.deleteConfirmationItem = nil
            $0.isPerformingFileAction = true
        }
        await store.receive(\.deleteResponse.success) {
            $0.isPerformingFileAction = false
            $0.items = []
            $0.trashNotice = .init(count: 1, sequence: 5)
        }
    }

    @Test("The Trash row and Open Trash ask the tab to open the trash")
    func openTrash() async {
        let store = BrowseFixtures.store()

        await store.send(.trashTapped)
        await store.receive(.delegate(.openTrashTapped))
    }

    @Test("Features with a trash section offer the Trash row; an older server does not")
    func trashAvailability() async {
        let store = BrowseFixtures.store {
            $0.jsonCacheStore = .inMemory()
        }

        await store.send(.serverFeaturesResponse(ServerFeatures(trash: TrashAvailability(
            isEnabled: true,
            retentionDays: 30
        )))) {
            $0.isTrashAvailable = true
        }
        await store.send(.serverFeaturesResponse(ServerFeatures())) {
            $0.isTrashAvailable = false
        }
    }
}
