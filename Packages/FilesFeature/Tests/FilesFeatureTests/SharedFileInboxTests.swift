import ComposableArchitecture
import CoreModels
import DependenciesTestSupport
@testable import FilesFeature
import Foundation
import Testing

/// Files opened in the app from another app's share sheet: the inbox drains into an upload review
/// on the Browse tab's topmost screen.
@Suite(.dependencies)
@MainActor
struct SharedFileInboxTests {
    private let serverURL = URL(string: "https://example.com")!
    private let user = User(id: "1", username: "jdoe", email: nil, roles: [])
    private let scan = URL(fileURLWithPath: "/tmp/Scan.pdf")
    private let receipt = URL(fileURLWithPath: "/tmp/Receipt.jpg")

    private nonisolated static func staging(_ names: [String]) -> UploadStagingClient {
        UploadStagingClient(
            stageDocuments: { _ in
                AsyncStream<PickedFile> { continuation in
                    for name in names {
                        continuation.yield(PickedFile(id: UUID(), fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, size: 10))
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

    // MARK: Happy path

    @Test
    func sharedFilesDrainIntoAnUploadReviewOnTheBrowseTab() async {
        var state = MainTabFeature.State(serverURL: serverURL, user: user)
        state.selectedTab = .settings
        state.$sharedFileInbox.withLock { $0 = [scan] }
        let store = TestStore(initialState: state) {
            MainTabFeature()
        } withDependencies: {
            $0.uploadStaging = Self.staging(["Scan.pdf"])
        }
        store.exhaustivity = .off

        await store.send(.sharedFilesArrived) {
            $0.selectedTab = .browse
            $0.$sharedFileInbox.withLock { $0 = [] }
        }
        await store.receive(\.browse.receiveSharedFiles)
        await store.receive(\.browse.root.receiveSharedFiles)
        await store.receive(\.browse.root.beginUpload)
        await store.receive(\.browse.root.uploadReview.presented.stagingBatchFinished)
        #expect(store.state.browse.root.uploadReview?.files.map(\.fileName) == ["Scan.pdf"])
    }

    @Test
    func sharedFilesGoToTheTopmostPushedScreen() async {
        var state = BrowseTabFeature.State(serverURL: serverURL)
        state.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Documents", title: "Documents"))
        let store = TestStore(initialState: state) {
            BrowseTabFeature()
        } withDependencies: {
            $0.uploadStaging = Self.staging(["Scan.pdf"])
        }
        store.exhaustivity = .off

        await store.send(.receiveSharedFiles([scan]))
        await store.receive(\.path[id: 0].receiveSharedFiles)
        await store.receive(\.path[id: 0].uploadReview.presented.stagingBatchFinished)
        #expect(store.state.root.uploadReview == nil)
        #expect(store.state.path[id: 0]?.uploadReview?.destination == "Documents")
    }

    @Test
    func moreSharedFilesJoinTheReviewAlreadyOpen() async {
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Documents", title: "Documents")
        state.uploadReview = UploadReviewFeature.State(serverURL: serverURL, startingDestination: "Documents")
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.uploadStaging = Self.staging(["Receipt.jpg"])
        }
        store.exhaustivity = .off

        await store.send(.receiveSharedFiles([receipt]))
        await store.receive(\.uploadReview.presented.stage)
        await store.receive(\.uploadReview.presented.stagingBatchFinished)
        #expect(store.state.uploadReview?.files.map(\.fileName) == ["Receipt.jpg"])
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
        var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Browse")
        state.previewItem = FileItem(name: "Notes.txt", path: "", dateModified: Date(), size: 1, kind: "txt")
        let store = TestStore(initialState: state) {
            BrowseFeature()
        } withDependencies: {
            $0.uploadStaging = Self.staging(["Scan.pdf"])
        }
        store.exhaustivity = .off

        await store.send(.receiveSharedFiles([scan]))
        await store.receive(\.previewDismissed) {
            $0.previewItem = nil
        }
        await store.receive(\.beginUpload)
        #expect(store.state.uploadReview != nil)
    }
}
