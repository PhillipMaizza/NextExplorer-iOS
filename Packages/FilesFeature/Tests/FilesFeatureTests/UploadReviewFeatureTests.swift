import ComposableArchitecture
import CoreModels
import Foundation
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct UploadReviewFeatureTests {
    private let serverURL = URL(string: "https://example.com")!

    private nonisolated func file(_ name: String, id: UUID, size: Int64) -> PickedFile {
        PickedFile(id: id, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, size: size)
    }

    @Test
    func totalsAndUploadGate() {
        var state = UploadReviewFeature.State(
            serverURL: serverURL,
            files: [file("a.jpg", id: UUID(0), size: 100), file("b.txt", id: UUID(1), size: 25)],
            startingDestination: ""
        )
        #expect(state.totalSize == 125)
        #expect(state.canUpload == false) // no destination yet

        state.destination = "Documents"
        #expect(state.canUpload == true)
    }

    @Test
    func pickingAFolderSetsTheDestinationAndPopsThePicker() async {
        let store = TestStore(
            initialState: UploadReviewFeature.State(
                serverURL: serverURL, files: [file("a.jpg", id: UUID(0), size: 1)], startingDestination: ""
            )
        ) {
            UploadReviewFeature()
        }
        store.exhaustivity = .off

        await store.send(.pathTapped) {
            $0.folderPicker = DestinationPickerFeature.State(serverURL: self.serverURL, uploadStartingAt: "")
        }
        await store.send(.folderPicker(.presented(.delegate(.confirmed(destination: "Documents/Trips"))))) {
            $0.destination = "Documents/Trips"
            $0.folderPicker = nil
        }
    }

    @Test
    func uploadConfirmsWithFilesAndDestination() async {
        let files = [file("a.jpg", id: UUID(0), size: 1), file("b.txt", id: UUID(1), size: 2)]
        let store = TestStore(
            initialState: UploadReviewFeature.State(serverURL: serverURL, files: files, startingDestination: "Inbox")
        ) { UploadReviewFeature() }

        await store.send(.uploadTapped)
        await store.receive(.delegate(.confirmed(files: files, destination: "Inbox")))
    }

    @Test
    func removingTheLastFileCancels() async {
        let store = TestStore(
            initialState: UploadReviewFeature.State(
                serverURL: serverURL, files: [file("a.jpg", id: UUID(0), size: 1)], startingDestination: "Inbox"
            )
        ) {
            UploadReviewFeature()
        }

        await store.send(.removeFileTapped(id: UUID(0))) {
            $0.files.remove(id: UUID(0))
        }
        await store.receive(.delegate(.cancelled))
    }
}
