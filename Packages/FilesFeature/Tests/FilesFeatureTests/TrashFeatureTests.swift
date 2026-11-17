import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import FolderPickerFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct TrashFeatureTests {
    private enum Constants {
        static let retentionDays = 30
        static let destination = "Files/Restored"
    }

    private let report = TrashItem(id: "t1", name: "report.pdf", openPath: "personal/Reports", shareCount: 2)
    private let photos = TrashItem(id: "t2", name: "Photos", isDirectory: true, openPath: "Media")
    private let notes = TrashItem(id: "t3", name: "notes.txt")
    private let gone = TrashItem(id: "t4", name: "gone.txt", isAvailable: false)

    private nonisolated static func listing(_ items: [TrashItem], isEnabled: Bool = true) -> TrashListing {
        TrashListing(isEnabled: isEnabled, retentionDays: Constants.retentionDays, items: items)
    }

    private func loadedState(_ items: [TrashItem]) -> TrashFeature.State {
        var state = TrashFeature.State(serverURL: TestHost.serverURL)
        state.phase = .loaded
        state.items = IdentifiedArray(uniqueElements: items)
        state.retentionDays = Constants.retentionDays
        return state
    }

    private func store(
        _ state: TrashFeature.State? = nil,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<TrashFeature> {
        TestStore(initialState: state ?? TrashFeature.State(serverURL: TestHost.serverURL)) {
            TrashFeature()
        } withDependencies: {
            configure(&$0)
        }
    }

    // MARK: Load

    @Test("Opening the trash lists its items, the retention and whether it is on")
    func load() async {
        let items = [report, photos]
        let store = store { $0.filesClient.fetchTrash = { _ in Self.listing(items, isEnabled: false) } }

        await store.send(.task) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.items = IdentifiedArray(uniqueElements: items)
            $0.isEnabled = false
            $0.retentionDays = Constants.retentionDays
        }
        await store.send(.task)
    }

    @Test("A failed first load says so, offline says it is offline, and Retry loads again")
    func loadFailure() async {
        let attempts = LockIsolated(0)
        let store = store {
            $0.filesClient.fetchTrash = { _ in
                attempts.withValue { $0 += 1 }
                throw attempts.value == 1 ? FilesClientError.server(statusCode: 500) : FilesClientError.offline
            }
        }

        await store.send(.task) { $0.phase = .loading }
        await store.receive(\.loadResponse.failure) { $0.phase = .failed(L10n.Trash.loadFailed) }
        await store.send(.retryTapped) { $0.phase = .loading }
        await store.receive(\.loadResponse.failure) { $0.phase = .failed(FilesClientError.offline.userMessage) }
    }

    @Test("A reload that fails keeps the list and says why")
    func reloadFailureKeepsTheList() async {
        let store = store(loadedState([report])) {
            $0.filesClient.fetchTrash = { _ in throw FilesClientError.sessionExpired }
        }

        await store.send(.refreshPulled)
        await store.receive(\.loadResponse.failure) {
            $0.notice = TrashNotice(text: FilesClientError.sessionExpired.userMessage, isFailure: true, sequence: 1)
        }
    }

    // MARK: Open

    @Test("A folder opens inside the trash; a text file opens read only; an unavailable item does nothing")
    func open() async {
        let store = store(loadedState([photos, notes, gone])) {
            $0.filesClient.fetchTrashText = { _, id, path in
                #expect(id == "t3")
                #expect(path.isEmpty)
                return TrashText(name: "notes.txt", content: "hi")
            }
        }

        await store.send(.itemTapped(photos)) {
            $0.folder = TrashFolderFeature.State(serverURL: TestHost.serverURL, item: photos)
        }
        await store.send(.folder(.dismiss)) { $0.folder = nil }
        await store.send(.itemTapped(notes)) { $0.text = .loading(name: "notes.txt") }
        await store.receive(\.textResponse.success) { $0.text = .loaded(TrashText(name: "notes.txt", content: "hi")) }
        await store.send(.textDismissed) { $0.text = .closed }
        await store.send(.itemTapped(gone))
    }

    @Test("A file the editor would not open is not previewed")
    func binaryFileIsNotPreviewed() async {
        let store = store(loadedState([report]))

        await store.send(.itemTapped(report))
    }

    @Test("Open Original Location hands the folder up, the personal space as My Files")
    func openLocation() async {
        let store = store(loadedState([report, photos]))

        await store.send(.openLocationTapped(report))
        await store.receive(.delegate(.openPath(path: "personal/Reports", title: "Reports")))
        await store.send(.openLocationTapped(photos))
        await store.receive(.delegate(.openPath(path: "Media", title: "Media")))
    }

    // MARK: Restore

    @Test("Restoring an item without share links sends the drop choice, then reloads")
    func restoreWithoutLinks() async {
        let sent = LockIsolated<[ShareLinkChoice]>([])
        let store = store(loadedState([notes])) {
            $0.filesClient.restoreTrash = { _, target, destination, shares, _ in
                #expect(target == .items(["t3"]))
                #expect(destination == nil)
                sent.withValue { $0.append(shares) }
                return TrashActionResult(items: [.init(key: "t3", status: .restored, name: "notes.txt")])
            }
            $0.filesClient.fetchTrash = { _ in Self.listing([]) }
        }

        await store.send(.restoreTapped([notes]))
        await store.receive(\.restore.restore) { $0.restore.phase = .inPlace }
        await store.receive(\.restore.response.success) {
            $0.restore.phase = .idle
            $0.restore.notice = TrashNotice(text: L10n.Trash.restored(1), isFailure: false, sequence: 1)
        }
        await store.receive(.restore(.delegate(.finished)))
        await store.receive(.delegate(.restored))
        await store.receive(\.loadResponse.success) { $0.items = [] }
        #expect(sent.value == [.drop])
    }

    @Test("Restoring an item with share links asks first and sends the answer")
    func restoreAsksAboutLinks() async {
        let store = store(loadedState([report])) {
            $0.filesClient.restoreTrash = { _, _, _, shares, _ in
                #expect(shares == .restore)
                return TrashActionResult(items: [
                    .init(
                        key: "t1",
                        status: .restored,
                        name: "report.pdf",
                        restoredName: "report (1).pdf",
                        isRenamed: true,
                        sharesRestored: 2
                    ),
                ])
            }
            $0.filesClient.fetchTrash = { _ in Self.listing([]) }
        }

        await store.send(.restoreTapped([report]))
        await store.receive(\.restore.restore) {
            $0.restore.awaitingShareChoice = .init(target: .items(["t1"]), destination: nil, shareCount: 2)
        }
        await store.send(.restore(.shareChoiceMade(.restore))) {
            $0.restore.awaitingShareChoice = nil
            $0.restore.phase = .inPlace
        }
        await store.receive(\.restore.response.success) {
            $0.restore.phase = .idle
            $0.restore.notice = TrashNotice(
                text: [
                    L10n.Trash.restored(1),
                    L10n.Trash.renamed("report.pdf", "report (1).pdf"),
                    L10n.Trash.sharesRestored(2),
                ]
                .joined(separator: "\n"),
                isFailure: false,
                sequence: 1
            )
        }
        await store.receive(.restore(.delegate(.finished)))
        await store.receive(.delegate(.restored))
        await store.receive(\.loadResponse.success) { $0.items = [] }
    }

    @Test("Dismissing the share link question restores nothing")
    func shareChoiceDismissed() async {
        var state = loadedState([report])
        state.restore.awaitingShareChoice = .init(target: .items(["t1"]), destination: nil, shareCount: 2)
        let store = store(state)

        await store.send(.restore(.shareChoiceDismissed)) { $0.restore.awaitingShareChoice = nil }
    }

    @Test("Restore To picks a folder, then restores into it and reports a refusal")
    func restoreTo() async {
        let store = store(loadedState([notes])) {
            $0.filesClient.restoreTrash = { _, _, destination, _, _ in
                #expect(destination == Constants.destination)
                return TrashActionResult(items: [.init(key: "t3", status: .destinationForbidden, name: "notes.txt")])
            }
            $0.filesClient.fetchTrash = { _ in Self.listing([notes]) }
        }

        await store.send(.restoreToTapped([notes]))
        await store.receive(\.restore.restoreTo) {
            $0.restore.awaitingDestination = .init(target: .items(["t3"]), destination: nil, shareCount: 0)
            $0.restore.destinationPicker = DestinationPickerFeature.State(
                serverURL: TestHost.serverURL,
                restoringFrom: ""
            )
        }
        await store
            .send(.restore(.destinationPicker(.presented(.delegate(.confirmed(destination: Constants.destination)))))) {
                $0.restore.destinationPicker = nil
                $0.restore.awaitingDestination = nil
                $0.restore.phase = .toFolder(progress: nil)
            }
        await store.receive(\.restore.response.success) {
            $0.restore.phase = .idle
            $0.restore.notice = TrashNotice(
                text: L10n.Trash.notRestored(1) + " " + L10n.Trash.failureDestinationForbidden,
                isFailure: true,
                sequence: 1
            )
        }
        await store.receive(.restore(.delegate(.finished)))
        await store.receive(.delegate(.restored))
        await store.receive(\.loadResponse.success)
    }

    @Test("Cancelling a restore into a folder stops the request and reloads")
    func cancelRestoreTo() async {
        var state = loadedState([notes])
        state.restore.awaitingDestination = .init(target: .items(["t3"]), destination: nil, shareCount: 0)
        state.restore.destinationPicker = DestinationPickerFeature.State(
            serverURL: TestHost.serverURL,
            restoringFrom: ""
        )
        let store = store(state) {
            $0.filesClient.restoreTrash = { _, _, _, _, _ in
                try await suspendUntilCancelled()
                return TrashActionResult(items: [])
            }
            $0.filesClient.fetchTrash = { _ in Self.listing([notes]) }
        }

        await store
            .send(.restore(.destinationPicker(.presented(.delegate(.confirmed(destination: Constants.destination)))))) {
                $0.restore.destinationPicker = nil
                $0.restore.awaitingDestination = nil
                $0.restore.phase = .toFolder(progress: nil)
            }
        await store.send(.restore(.cancelTapped)) {
            $0.restore.phase = .idle
        }
        await store.receive(.restore(.delegate(.finished)))
        await store.receive(.delegate(.restored))
        await store.receive(\.loadResponse.success)
    }

    // MARK: Delete for good

    @Test("Delete Permanently asks, then purges and counts failures")
    func purge() async {
        let store = store(loadedState([report, notes])) {
            $0.filesClient.purgeTrash = { _, ids, forget in
                #expect(ids == ["t1", "t3"])
                #expect(!forget)
                return TrashActionResult(items: [
                    .init(key: "t1", status: .purged, name: "report.pdf"),
                    .init(key: "t3", status: .busy, name: "notes.txt"),
                ])
            }
            $0.filesClient.fetchTrash = { _ in Self.listing([notes]) }
        }

        await store.send(.deletePermanentlyTapped([report, notes])) {
            $0.confirmation = .purge(ids: ["t1", "t3"], forget: false)
            $0.confirmPhase = .confirming
        }
        await store.send(.confirmationConfirmed) { $0.confirmPhase = .running }
        await store.receive(\.purgeResponse.success) {
            $0.confirmPhase = .idle
            $0.confirmation = nil
            $0.notice = TrashNotice(
                text: L10n.Trash.deletedPermanently(1) + "\n" + L10n.Trash.notDeleted(1) + " " + L10n.Trash.failureBusy,
                isFailure: false,
                sequence: 1
            )
        }
        await store.receive(\.loadResponse.success) { $0.items = [notes] }
    }

    @Test("Forget sends the administrator's forget flag")
    func forget() async {
        let store = store(loadedState([gone])) {
            $0.filesClient.purgeTrash = { _, _, forget in
                #expect(forget)
                return TrashActionResult(items: [.init(key: "t4", status: .forgotten, name: "gone.txt")])
            }
            $0.filesClient.fetchTrash = { _ in Self.listing([]) }
        }

        await store.send(.forgetTapped(gone)) {
            $0.confirmation = .purge(ids: ["t4"], forget: true)
            $0.confirmPhase = .confirming
        }
        await store.send(.confirmationConfirmed) { $0.confirmPhase = .running }
        await store.receive(\.purgeResponse.success) {
            $0.confirmPhase = .idle
            $0.confirmation = nil
            $0.notice = TrashNotice(text: L10n.Trash.deletedPermanently(1), isFailure: false, sequence: 1)
        }
        await store.receive(\.loadResponse.success) { $0.items = [] }
    }

    @Test("Empty Trash asks, empties, and says what stayed behind")
    func empty() async {
        let store = store(loadedState([report, notes])) {
            $0.filesClient.emptyTrash = { _ in TrashEmptySummary(purged: 1, unavailable: 1) }
            $0.filesClient.fetchTrash = { _ in Self.listing([]) }
        }

        await store.send(.emptyTrashTapped) {
            $0.confirmation = .empty
            $0.confirmPhase = .confirming
        }
        await store.send(.emptyTrashTapped)
        await store.send(.confirmationConfirmed) { $0.confirmPhase = .running }
        await store.receive(\.emptyResponse.success) {
            $0.confirmPhase = .idle
            $0.confirmation = nil
            $0.notice = TrashNotice(
                text: L10n.Trash.emptied(1) + "\n" + L10n.Trash.leftBehind(1),
                isFailure: false,
                sequence: 1
            )
        }
        await store.receive(\.loadResponse.success) { $0.items = [] }
    }

    @Test("Cancelling the confirmation runs nothing")
    func confirmationDismissed() async {
        let store = store(loadedState([report]))

        await store.send(.deletePermanentlyTapped([report])) {
            $0.confirmation = .purge(ids: ["t1"], forget: false)
            $0.confirmPhase = .confirming
        }
        await store.send(.confirmationDismissed) {
            $0.confirmation = nil
            $0.confirmPhase = .idle
        }
    }

    // MARK: Selection

    @Test("Select mode toggles items, picks all, and a tap selects instead of opening")
    func selection() async {
        let store = store(loadedState([report, photos]))

        await store.send(.selectModeToggled) { $0.isSelecting = true }
        await store.send(.itemTapped(photos))
        await store.receive(\.selectionToggled) { $0.selectedIDs = ["t2"] }
        await store.send(.selectAllTapped) { $0.selectedIDs = ["t1", "t2"] }
        await store.send(.selectAllTapped) { $0.selectedIDs = [] }
        await store.send(.selectModeToggled) { $0.isSelecting = false }
    }
}
