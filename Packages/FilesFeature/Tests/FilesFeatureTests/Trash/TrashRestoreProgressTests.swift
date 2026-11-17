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
struct TrashRestoreProgressTests {
    private enum Constants {
        static let destination = "Files/Restored"
        static let halfway = 0.5
    }

    private let result = TrashActionResult(items: [.init(key: "t3", status: .restored, name: "notes.txt")])

    private func store(
        configure: (inout DependencyValues) -> Void
    ) -> TestStoreOf<TrashRestoreFeature> {
        TestStore(initialState: TrashRestoreFeature.State(serverURL: TestHost.serverURL)) {
            TrashRestoreFeature()
        } withDependencies: {
            configure(&$0)
        }
    }

    private func pickDestination(_ store: TestStoreOf<TrashRestoreFeature>) async {
        await store.send(.restoreTo(.items(["t3"]), shareCount: 0)) {
            $0.awaitingDestination = .init(target: .items(["t3"]), destination: nil, shareCount: 0)
            $0.destinationPicker = DestinationPickerFeature.State(serverURL: TestHost.serverURL, restoringFrom: "")
        }
        await store.send(.destinationPicker(.presented(.delegate(.confirmed(destination: Constants.destination))))) {
            $0.destinationPicker = nil
            $0.awaitingDestination = nil
            $0.phase = .toFolder(progress: nil)
        }
    }

    @Test("A restore into a folder shows how far the copy is before it reports the result")
    func folderRestoreReportsProgress() async {
        let store = store {
            $0.filesClient.restoreTrash = { _, _, _, _, onProgress in
                onProgress(Constants.halfway)
                return result
            }
        }

        await pickDestination(store)
        await store.receive(\.progressed) { $0.phase = .toFolder(progress: Constants.halfway) }
        await store.receive(\.response.success) {
            $0.phase = .idle
            $0.notice = TrashNotice(text: L10n.Trash.restored(1), isFailure: false, sequence: 1)
        }
        await store.receive(.delegate(.finished))
    }

    @Test("A late progress report after the restore ended changes nothing")
    func progressAfterEndIsIgnored() async {
        await store { _ in }.send(.progressed(Constants.halfway))
    }

    @Test("Cancel stops the copy, keeps nothing on screen and reloads")
    func cancelStops() async {
        let store = store {
            $0.filesClient.restoreTrash = { _, _, _, _, _ in
                try await suspendUntilCancelled()
                return result
            }
        }

        await pickDestination(store)
        await store.send(.cancelTapped) { $0.phase = .idle }
        await store.receive(.delegate(.finished))
    }
}
