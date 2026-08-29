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

    /// A staging client whose `stageDocuments` streams `files` back and records what it was
    /// asked to `discard`.
    private nonisolated func staging(
        yielding files: [PickedFile], discarded: LockIsolated<[URL]> = LockIsolated([])
    ) -> UploadStagingClient {
        UploadStagingClient(
            stageDocuments: { _ in
                AsyncStream<PickedFile> { continuation in
                    for file in files { continuation.yield(file) }
                    continuation.finish()
                }
            },
            stagePhotos: { _ in AsyncStream<PickedFile> { $0.finish() } },
            stageCameraCapture: { _ in nil },
            discard: { urls in discarded.withValue { $0.append(contentsOf: urls) } },
            sweepStale: {}
        )
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
    func stagingStreamsFilesInAndUnlocksUploadWhenDone() async {
        let a = file("a.jpg", id: UUID(0), size: 10)
        let b = file("b.txt", id: UUID(1), size: 5)
        let store = TestStore(
            initialState: UploadReviewFeature.State(serverURL: serverURL, startingDestination: "Inbox")
        ) {
            UploadReviewFeature()
        } withDependencies: {
            $0.uploadStaging = staging(yielding: [a, b])
        }
        store.exhaustivity = .off

        await store.send(.stage(.documents([URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.txt")]))) {
            $0.preparingCount = 2
        }
        #expect(store.state.canUpload == false) // still preparing

        await store.receive(\.filePrepared) { $0.files.append(a); $0.preparingCount = 1 }
        await store.receive(\.filePrepared) { $0.files.append(b); $0.preparingCount = 0 }
        await store.receive(\.stagingBatchFinished)
        #expect(store.state.canUpload == true)
        #expect(store.state.totalSize == 15)
    }

    @Test
    func addingMoreWhilePreparingAccumulates() async {
        let a = file("a.jpg", id: UUID(0), size: 10)
        let store = TestStore(
            initialState: UploadReviewFeature.State(
                serverURL: serverURL, files: [a], startingDestination: "Inbox"
            )
        ) {
            UploadReviewFeature()
        } withDependencies: {
            $0.uploadStaging = staging(yielding: [file("b.txt", id: UUID(1), size: 5)])
        }
        store.exhaustivity = .off
        #expect(store.state.canUpload == true)

        await store.send(.stage(.documents([URL(fileURLWithPath: "/tmp/b.txt")]))) {
            $0.preparingCount = 1
        }
        #expect(store.state.canUpload == false) // locked while the new pick materializes

        await store.receive(\.filePrepared)
        await store.receive(\.stagingBatchFinished)
        #expect(store.state.canUpload == true)
        #expect(store.state.totalSize == 15)
    }

    @Test
    func stagingProducingNothingWithNoFilesKeepsTheSheetWithAnError() async {
        let store = TestStore(
            initialState: UploadReviewFeature.State(serverURL: serverURL, startingDestination: "Inbox")
        ) {
            UploadReviewFeature()
        } withDependencies: {
            $0.uploadStaging = staging(yielding: [])
        }
        store.exhaustivity = .off

        await store.send(.stage(.documents([URL(fileURLWithPath: "/tmp/a.jpg")]))) {
            $0.preparingCount = 1
        }
        await store.receive(\.stagingBatchFinished) {
            $0.preparingCount = 0
            $0.stagingFailed = true
        }
        #expect(store.state.canUpload == false)
    }

    @Test
    func closingWithNoFilesCancelsImmediately() async {
        let store = TestStore(
            initialState: UploadReviewFeature.State(serverURL: serverURL, startingDestination: "Inbox")
        ) { UploadReviewFeature() }

        await store.send(.cancelTapped)
        await store.receive(.delegate(.cancelled))
    }

    @Test
    func closingWithStagedFilesRaisesTheDiscardConfirmationThenCancels() async {
        let a = file("a.jpg", id: UUID(0), size: 1)
        let store = TestStore(
            initialState: UploadReviewFeature.State(
                serverURL: serverURL, files: [a], startingDestination: "Inbox"
            )
        ) { UploadReviewFeature() }

        await store.send(.cancelTapped) { $0.isConfirmingCancel = true }
        await store.send(.confirmCancelTapped) { $0.isConfirmingCancel = false }
        await store.receive(.delegate(.cancelled))
    }

    @Test
    func dismissingTheDiscardConfirmationKeepsTheSheet() async {
        let a = file("a.jpg", id: UUID(0), size: 1)
        let store = TestStore(
            initialState: UploadReviewFeature.State(
                serverURL: serverURL, files: [a], startingDestination: "Inbox"
            )
        ) { UploadReviewFeature() }

        await store.send(.cancelTapped) { $0.isConfirmingCancel = true }
        await store.send(.cancelConfirmationDismissed) { $0.isConfirmingCancel = false }
    }

    @Test
    func closingWhilePreparingWithNoFilesStillConfirms() async {
        let store = TestStore(
            initialState: UploadReviewFeature.State(
                serverURL: serverURL, startingDestination: "Inbox", preparingCount: 2
            )
        ) { UploadReviewFeature() }

        await store.send(.cancelTapped) { $0.isConfirmingCancel = true }
    }

    @Test
    func removingTheLastFileCancelsAndDiscardsIt() async {
        let discarded = LockIsolated<[URL]>([])
        let a = file("a.jpg", id: UUID(0), size: 1)
        let store = TestStore(
            initialState: UploadReviewFeature.State(
                serverURL: serverURL, files: [a], startingDestination: "Inbox"
            )
        ) {
            UploadReviewFeature()
        } withDependencies: {
            $0.uploadStaging = staging(yielding: [], discarded: discarded)
        }
        store.exhaustivity = .off

        await store.send(.removeFileTapped(id: UUID(0))) {
            $0.files.remove(id: UUID(0))
        }
        await store.receive(.delegate(.cancelled))
        await store.finish()
        #expect(discarded.value == [a.fileURL])
    }
}
