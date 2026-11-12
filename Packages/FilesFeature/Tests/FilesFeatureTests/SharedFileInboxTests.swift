import ComposableArchitecture
import CoreModels
@testable import FilesFeature
import Foundation
import Localization
import ShareUploads
import Testing
import TestUtils

/// Files opened in the app from another app's share sheet: the inbox drains into an upload review
/// on the Browse tab's topmost screen.
@Suite(.isolatedDependencies)
@MainActor
struct SharedFileInboxTests {
    private typealias Review = UploadReviewFeature.State

    private let serverURL = URL(fileURLWithPath: "/")
    private let user = User(id: "1", username: "jdoe", email: nil, roles: [])
    private let scan = URL(fileURLWithPath: "/tmp/Scan.pdf")
    private let receipt = URL(fileURLWithPath: "/tmp/Receipt.jpg")

    private nonisolated static func picked(_ name: String) -> PickedFile {
        PickedFile(id: TestID.uuid(), fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, size: 10)
    }

    private nonisolated static func staging(_ files: [PickedFile]) -> UploadStagingClient {
        UploadStagingClient(
            stageDocuments: { _ in
                AsyncStream<PickedFile> { continuation in
                    for file in files {
                        continuation.yield(file)
                    }
                    continuation.finish()
                }
            },
            stagePhotos: { _ in AsyncStream<PickedFile> { $0.finish() } },
            stageCameraCapture: { _ in nil },
            discard: { _ in },
            sweepStale: {}
        )
    }

    private func browseStore(
        directoryPath: String = "Documents",
        title: String = "Documents",
        state configure: (inout BrowseFeature.State) -> Void = { _ in },
        dependencies: (inout DependencyValues) -> Void
    ) -> TestStoreOf<BrowseFeature> {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: directoryPath, title: title)
        configure(&state)
        return TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            dependencies(&$0)
        }
    }

    /// Receives a batch of one file staged into the open review: counted as preparing, landing, then drained.
    private func receiveStaging(_ store: TestStoreOf<BrowseFeature>, _ file: PickedFile) async {
        await store.receive(\.uploadReview.presented.stage) { $0.uploadReview?.preparingCount = 1 }
        await store.receive(\.uploadReview.presented.filePrepared) {
            $0.uploadReview?.files = [file]
            $0.uploadReview?.preparingCount = 0
        }
        await store.receive(\.uploadReview.presented.stagingBatchFinished)
    }

    // MARK: Happy path

    @Test
    func sharedFilesDrainIntoAnUploadReviewOnTheBrowseTab() async {
        let file = Self.picked("Scan.pdf")
        var state = MainTabFeature.State(serverURL: serverURL, user: user)
        state.selectedTab = .settings
        state.$sharedFileInbox.withLock { $0 = [scan] }
        let store = TestStore(initialState: state) {
            MainTabFeature()
        } withDependencies: {
            $0.uploadStaging = Self.staging([file])
        }

        await store.send(.sharedFilesArrived) {
            $0.selectedTab = .browse
            $0.$sharedFileInbox.withLock { $0 = [] }
        }
        await store.receive(\.browse.receiveSharedFiles)
        await store.receive(\.browse.root.receiveSharedFiles)
        // Finder or Files hands over no folder, so they go to the review sheet.
        await store.receive(\.browse.root.reviewSharedFiles) {
            $0.browse.root.uploadReview = Review(serverURL: serverURL, startingDestination: "")
        }
        await store.receive(\.browse.root.uploadReview.presented.stage) {
            $0.browse.root.uploadReview?.preparingCount = 1
        }
        await store.receive(\.browse.root.uploadReview.presented.filePrepared) {
            $0.browse.root.uploadReview?.files = [file]
            $0.browse.root.uploadReview?.preparingCount = 0
        }
        await store.receive(\.browse.root.uploadReview.presented.stagingBatchFinished)
    }

    @Test
    func sharedFilesGoToTheTopmostPushedScreen() async {
        let file = Self.picked("Scan.pdf")
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Documents", title: "Documents"))
        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        } withDependencies: {
            $0.uploadStaging = Self.staging([file])
        }

        await store.send(.receiveSharedFiles([scan]))
        await store.receive(\.path[id: 0].receiveSharedFiles)
        await store.receive(\.path[id: 0].reviewSharedFiles) {
            $0.path[id: 0]?.uploadReview = Review(serverURL: serverURL, startingDestination: "Documents")
        }
        await store.receive(\.path[id: 0].uploadReview.presented.stage) {
            $0.path[id: 0]?.uploadReview?.preparingCount = 1
        }
        await store.receive(\.path[id: 0].uploadReview.presented.filePrepared) {
            $0.path[id: 0]?.uploadReview?.files = [file]
            $0.path[id: 0]?.uploadReview?.preparingCount = 0
        }
        await store.receive(\.path[id: 0].uploadReview.presented.stagingBatchFinished)
        #expect(store.state.root.uploadReview == nil)
    }

    @Test
    func moreSharedFilesJoinTheReviewAlreadyOpen() async {
        let file = Self.picked("Receipt.jpg")
        let store = browseStore(
            state: { $0.uploadReview = Review(serverURL: serverURL, startingDestination: "Documents") },
            dependencies: { $0.uploadStaging = Self.staging([file]) }
        )

        await store.send(.receiveSharedFiles([receipt]))
        await receiveStaging(store, file)
    }

    // MARK: Edge cases

    @Test
    func anEmptyInboxDoesNothing() async {
        let store = TestStore(initialState: MainTabFeature.State(serverURL: serverURL, user: user)) {
            MainTabFeature()
        }

        await store.send(.sharedFilesArrived)
    }

    @Test
    func anOpenPreviewClosesBeforeTheReviewOpens() async {
        let file = Self.picked("Scan.pdf")
        let store = browseStore(
            directoryPath: "",
            title: "Browse",
            state: { $0.previewItem = FileItem(name: "Notes.txt", path: "", dateModified: MockDate.date, size: 1, kind: "txt") },
            dependencies: { $0.uploadStaging = Self.staging([file]) }
        )

        await store.send(.receiveSharedFiles([scan]))
        await store.receive(\.previewDismissed) { $0.previewItem = nil }
        await store.receive(\.reviewSharedFiles) {
            $0.uploadReview = Review(serverURL: serverURL, startingDestination: "")
        }
        await receiveStaging(store, file)
    }

    // MARK: Settings > Shared Files

    @Test
    func theReviewStartsInTheDefaultFolder() async {
        let file = Self.picked("Scan.pdf")
        let store = browseStore {
            $0.uploadStaging = Self.staging([file])
            $0.uploadDefaults = .inMemory(["account": UploadDefaults(folderPath: "Inbox/Scans")], activeAccountID: "account")
        }

        await store.send(.receiveSharedFiles([scan]))
        await store.receive(\.reviewSharedFiles) {
            $0.uploadReview = Review(serverURL: serverURL, startingDestination: "Inbox/Scans")
        }
        await receiveStaging(store, file)
    }

    @Test
    func uploadWithoutAskingSkipsTheReview() async {
        let file = Self.picked("Scan.pdf")
        let store = browseStore {
            $0.uploadStaging = Self.staging([file])
            $0.uploadDefaults = .inMemory(
                ["account": UploadDefaults(folderPath: "Inbox/Scans", shouldUploadWithoutAsking: true)],
                activeAccountID: "account"
            )
        }

        await store.send(.receiveSharedFiles([scan]))
        await store.receive(\.directUploadStaged)
        await store.receive(.delegate(.uploadRequested([
            PendingUpload(id: file.id, fileURL: file.fileURL, fileName: "Scan.pdf", destination: "Inbox/Scans"),
        ])))
        #expect(store.state.uploadReview == nil)
    }

    @Test
    func uploadWithoutAskingReportsAnErrorWhenNothingCouldBeStaged() async {
        let store = browseStore {
            $0.uploadStaging = Self.staging([])
            $0.uploadDefaults = .inMemory(
                ["account": UploadDefaults(folderPath: "Inbox/Scans", shouldUploadWithoutAsking: true)],
                activeAccountID: "account"
            )
        }

        await store.send(.receiveSharedFiles([scan]))
        await store.receive(\.directUploadStaged) {
            $0.fileActionErrorMessage = L10n.Uploads.stagingFailed
        }
        #expect(store.state.uploadReview == nil)
    }

    @Test
    func anotherAccountsDefaultFolderIsNeverUsed() async {
        let file = Self.picked("Scan.pdf")
        let store = browseStore {
            $0.uploadStaging = Self.staging([file])
            $0.uploadDefaults = .inMemory(
                ["someone else": UploadDefaults(folderPath: "Theirs", shouldUploadWithoutAsking: true)],
                activeAccountID: "me"
            )
        }

        await store.send(.receiveSharedFiles([scan]))
        await store.receive(\.reviewSharedFiles) {
            $0.uploadReview = Review(serverURL: serverURL, startingDestination: "Documents")
        }
        await receiveStaging(store, file)
    }
}
