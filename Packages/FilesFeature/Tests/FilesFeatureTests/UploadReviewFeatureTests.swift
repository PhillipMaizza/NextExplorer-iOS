import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import FolderPickerFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct UploadReviewFeatureTests {
    private typealias Store = TestStoreOf<UploadReviewFeature>
    private typealias State = UploadReviewFeature.State

    private let serverURL = SettingsTestSupport.serverURL
    private let discarded = LockIsolated<[URL]>([])
    private let stagedDocuments = LockIsolated<[[URL]]>([])
    private let stagedCameraURLs = LockIsolated<[URL]>([])

    private nonisolated func file(_ name: String, id: Int, size: Int64) -> PickedFile {
        PickedFile(id: UUID(id), fileURL: URL(fileURLWithPath: "/staging/\(name)"), fileName: name, size: size)
    }

    private func state(files: [PickedFile] = [], destination: String = TestFolder.inbox, preparingCount: Int = 0) -> State {
        State(serverURL: serverURL, files: files, startingDestination: destination, preparingCount: preparingCount)
    }

    /// A staging client whose document staging streams `documents` back in order, whose camera
    /// staging answers `camera`, and which records what it was asked to stage and discard.
    private func makeStore(
        _ state: State,
        documents: [PickedFile] = [],
        camera: PickedFile? = nil
    ) -> Store {
        let discarded = discarded
        let stagedDocuments = stagedDocuments
        let stagedCameraURLs = stagedCameraURLs
        return TestStore(initialState: state) {
            UploadReviewFeature()
        } withDependencies: {
            $0.uploadStaging = UploadStagingClient(
                stageDocuments: { urls in
                    stagedDocuments.withValue { $0.append(urls) }
                    return AsyncStream<PickedFile> { continuation in
                        for file in documents {
                            continuation.yield(file)
                        }
                        continuation.finish()
                    }
                },
                stagePhotos: { _ in AsyncStream<PickedFile> { $0.finish() } },
                stageCameraCapture: { url in
                    stagedCameraURLs.withValue { $0.append(url) }
                    return camera
                },
                discard: { urls in discarded.withValue { $0.append(contentsOf: urls) } },
                sweepStale: {}
            )
        }
    }

    // MARK: Totals and the upload gate

    struct GateCase: Sendable {
        let fileSizes: [Int64]
        let destination: String
        let preparingCount: Int
        let canUpload: Bool
        let totalSize: Int64
        let totalCount: Int
    }

    @Test(
        "Upload needs files, a destination, and nothing still preparing",
        arguments: [
            GateCase(fileSizes: [100, 25], destination: TestFolder.documents, preparingCount: 0, canUpload: true, totalSize: 125, totalCount: 2),
            GateCase(fileSizes: [100, 25], destination: "", preparingCount: 0, canUpload: false, totalSize: 125, totalCount: 2),
            GateCase(fileSizes: [100], destination: TestFolder.documents, preparingCount: 1, canUpload: false, totalSize: 100, totalCount: 2),
            GateCase(fileSizes: [], destination: TestFolder.documents, preparingCount: 0, canUpload: false, totalSize: 0, totalCount: 0),
            GateCase(fileSizes: [], destination: TestFolder.documents, preparingCount: 3, canUpload: false, totalSize: 0, totalCount: 3),
        ]
    )
    func totalsAndUploadGate(_ testCase: GateCase) {
        let files = testCase.fileSizes.enumerated().map { file("f\($0.offset)", id: $0.offset, size: $0.element) }
        let sheet = state(files: files, destination: testCase.destination, preparingCount: testCase.preparingCount)

        #expect(sheet.canUpload == testCase.canUpload)
        #expect(sheet.totalSize == testCase.totalSize)
        #expect(sheet.totalCount == testCase.totalCount)
        #expect(sheet.hasDestination == !testCase.destination.isEmpty)
    }

    // MARK: Destination

    @Test
    func pickingAFolderSetsTheDestinationAndPopsThePicker() async {
        let store = makeStore(state(files: [file(TestFile.aPhoto, id: 0, size: 1)], destination: ""))

        await store.send(.pathTapped) {
            $0.folderPicker = DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: "")
        }
        await store.send(.folderPicker(.presented(.delegate(.confirmed(destination: "Documents/Trips"))))) {
            $0.destination = "Documents/Trips"
            $0.folderPicker = nil
        }
        #expect(store.state.canUpload)
    }

    @Test
    func cancellingTheFolderPickerKeepsTheDestination() async {
        let store = makeStore(state(files: [file(TestFile.aPhoto, id: 0, size: 1)], destination: TestFolder.inbox))

        await store.send(.pathTapped) {
            $0.folderPicker = DestinationPickerFeature.State(serverURL: serverURL, uploadStartingAt: TestFolder.inbox)
        }
        await store.send(.folderPicker(.presented(.delegate(.cancelled)))) { $0.folderPicker = nil }
        #expect(store.state.destination == TestFolder.inbox)
    }

    // MARK: Upload

    @Test
    func uploadConfirmsWithFilesAndDestination() async {
        let files = [file(TestFile.aPhoto, id: 0, size: 1), file(TestFile.bText, id: 1, size: 2)]
        let store = makeStore(state(files: files, destination: TestFolder.inbox))

        await store.send(.uploadTapped)
        await store.receive(.delegate(.confirmed(files: files, destination: TestFolder.inbox)))
    }

    @Test(
        "Upload does nothing without a destination or while files are still preparing",
        arguments: [("", 0), (TestFolder.inbox, 1)]
    )
    func uploadIsGuarded(destination: String, preparingCount: Int) async {
        let store = makeStore(state(files: [file(TestFile.aPhoto, id: 0, size: 1)], destination: destination, preparingCount: preparingCount))

        await store.send(.uploadTapped)
    }

    // MARK: Staging

    @Test
    func stagingStreamsFilesInAndUnlocksUploadWhenDone() async {
        let a = file(TestFile.aPhoto, id: 0, size: 10)
        let b = file(TestFile.bText, id: 1, size: 5)
        let urls = [URL(fileURLWithPath: "/picked/a.jpg"), URL(fileURLWithPath: "/picked/b.txt")]
        let store = makeStore(state(), documents: [a, b])

        await store.send(.stage(.documents(urls))) { $0.preparingCount = 2 }
        #expect(!store.state.canUpload)

        await store.receive(\.filePrepared) {
            $0.files = [a]
            $0.preparingCount = 1
        }
        await store.receive(\.filePrepared) {
            $0.files = [a, b]
            $0.preparingCount = 0
        }
        await store.receive(.stagingBatchFinished(requested: 2, staged: 2))
        #expect(store.state.canUpload)
        #expect(store.state.totalSize == 15)
        #expect(stagedDocuments.value == [urls])
    }

    @Test
    func addingMoreWhilePreparingAccumulates() async {
        let a = file(TestFile.aPhoto, id: 0, size: 10)
        let b = file(TestFile.bText, id: 1, size: 5)
        let store = makeStore(state(files: [a]), documents: [b])
        #expect(store.state.canUpload)

        await store.send(.stage(.documents([URL(fileURLWithPath: "/picked/b.txt")]))) { $0.preparingCount = 1 }
        #expect(!store.state.canUpload)

        await store.receive(\.filePrepared) {
            $0.files = [a, b]
            $0.preparingCount = 0
        }
        await store.receive(.stagingBatchFinished(requested: 1, staged: 1))
        #expect(store.state.canUpload)
        #expect(store.state.totalSize == 15)
    }

    @Test
    func aCameraCaptureIsStagedAsOneFile() async {
        let capture = file("capture.jpg", id: 0, size: 7)
        let url = URL(fileURLWithPath: "/camera/capture.jpg")
        let store = makeStore(state(), camera: capture)

        await store.send(.stage(.camera(url))) { $0.preparingCount = 1 }
        await store.receive(\.filePrepared) {
            $0.files = [capture]
            $0.preparingCount = 0
        }
        await store.receive(.stagingBatchFinished(requested: 1, staged: 1))
        #expect(stagedCameraURLs.value == [url])
    }

    @Test
    func aCameraCaptureThatCannotBeStagedKeepsTheSheetWithAnError() async {
        let store = makeStore(state(), camera: nil)

        await store.send(.stage(.camera(URL(fileURLWithPath: "/camera/capture.jpg")))) { $0.preparingCount = 1 }
        await store.receive(.stagingBatchFinished(requested: 1, staged: 0)) {
            $0.preparingCount = 0
            $0.skippedCount = 1
            $0.stagingFailed = true
        }
    }

    @Test
    func stagingNothingWithNoFilesKeepsTheSheetWithAnError() async {
        let store = makeStore(state(), documents: [])

        await store.send(.stage(.documents([URL(fileURLWithPath: "/picked/a.jpg")]))) { $0.preparingCount = 1 }
        await store.receive(.stagingBatchFinished(requested: 1, staged: 0)) {
            $0.preparingCount = 0
            $0.skippedCount = 1
            $0.stagingFailed = true
        }
        #expect(!store.state.canUpload)
    }

    @Test
    func aPartiallyStagedBatchCountsTheSkippedFilesAndStillUnlocksUpload() async {
        let a = file(TestFile.aPhoto, id: 0, size: 10)
        let b = file(TestFile.bText, id: 1, size: 5)
        let urls = (0 ..< 3).map { URL(fileURLWithPath: "/picked/\($0)") }
        let store = makeStore(state(), documents: [a, b])

        await store.send(.stage(.documents(urls))) { $0.preparingCount = 3 }
        await store.receive(\.filePrepared) {
            $0.files = [a]
            $0.preparingCount = 2
        }
        await store.receive(\.filePrepared) {
            $0.files = [a, b]
            $0.preparingCount = 1
        }
        await store.receive(.stagingBatchFinished(requested: 3, staged: 2)) {
            $0.skippedCount = 1
            $0.preparingCount = 0
        }
        #expect(store.state.canUpload)
        #expect(!store.state.stagingFailed)
    }

    @Test
    func aFailedBatchOnTopOfExistingFilesKeepsThemWithoutAnError() async {
        let a = file(TestFile.aPhoto, id: 0, size: 10)
        let store = makeStore(state(files: [a]), documents: [])

        await store.send(.stage(.documents([URL(fileURLWithPath: "/picked/b.txt")]))) { $0.preparingCount = 1 }
        await store.receive(.stagingBatchFinished(requested: 1, staged: 0)) {
            $0.preparingCount = 0
            $0.skippedCount = 1
        }
        #expect(store.state.files == [a])
        #expect(!store.state.stagingFailed)
    }

    @Test
    func aNewPickClearsAPreviousStagingError() async {
        var failed = state()
        failed.stagingFailed = true
        let a = file(TestFile.aPhoto, id: 0, size: 10)
        let store = makeStore(failed, documents: [a])

        await store.send(.stage(.documents([URL(fileURLWithPath: "/picked/a.jpg")]))) {
            $0.stagingFailed = false
            $0.preparingCount = 1
        }
        await store.receive(\.filePrepared) {
            $0.files = [a]
            $0.preparingCount = 0
        }
        await store.receive(.stagingBatchFinished(requested: 1, staged: 1))
    }

    @Test
    func pickingNothingDoesNothing() async {
        let store = makeStore(state())

        await store.send(.stage(.documents([])))
        #expect(stagedDocuments.value.isEmpty)
    }

    // MARK: Closing

    @Test
    func closingWithNoFilesCancelsImmediately() async {
        let store = makeStore(state())

        await store.send(.cancelTapped)
        await store.receive(.delegate(.cancelled))
    }

    @Test
    func closingWithStagedFilesRaisesTheDiscardConfirmationThenCancels() async {
        let store = makeStore(state(files: [file(TestFile.aPhoto, id: 0, size: 1)]))

        await store.send(.cancelTapped) { $0.isConfirmingCancel = true }
        await store.send(.confirmCancelTapped) { $0.isConfirmingCancel = false }
        await store.receive(.delegate(.cancelled))
    }

    @Test
    func dismissingTheDiscardConfirmationKeepsTheSheet() async {
        let store = makeStore(state(files: [file(TestFile.aPhoto, id: 0, size: 1)]))

        await store.send(.cancelTapped) { $0.isConfirmingCancel = true }
        await store.send(.cancelConfirmationDismissed) { $0.isConfirmingCancel = false }
    }

    @Test
    func closingWhilePreparingWithNoFilesStillConfirms() async {
        let store = makeStore(state(preparingCount: 2))

        await store.send(.cancelTapped) { $0.isConfirmingCancel = true }
    }

    // MARK: Removing files

    @Test
    func removingTheLastFileCancelsAndDiscardsIt() async {
        let a = file(TestFile.aPhoto, id: 0, size: 1)
        let store = makeStore(state(files: [a]))

        await store.send(.removeFileTapped(id: UUID(0))) { $0.files = [] }
        await store.receive(.delegate(.cancelled))
        await store.finish()
        #expect(discarded.value == [a.fileURL])
    }

    @Test
    func removingOneOfSeveralFilesDiscardsOnlyThatOneAndKeepsTheSheet() async {
        let a = file(TestFile.aPhoto, id: 0, size: 1)
        let b = file(TestFile.bPhoto, id: 1, size: 2)
        let store = makeStore(state(files: [a, b]))

        await store.send(.removeFileTapped(id: UUID(0))) { $0.files = [b] }
        await store.finish()
        #expect(discarded.value == [a.fileURL])
    }

    @Test
    func removingTheLastFileWhileMoreArePreparingKeepsTheSheetOpen() async {
        let a = file(TestFile.aPhoto, id: 0, size: 1)
        let store = makeStore(state(files: [a], preparingCount: 1))

        await store.send(.removeFileTapped(id: UUID(0))) { $0.files = [] }
        await store.finish()
        #expect(discarded.value == [a.fileURL])
    }

    @Test
    func removingAnUnknownFileChangesNothingAndDiscardsNothing() async {
        let store = makeStore(state(files: [file(TestFile.aPhoto, id: 0, size: 1)]))

        await store.send(.removeFileTapped(id: UUID(5)))
        await store.finish()
        #expect(discarded.value.isEmpty)
    }
}
