#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    @testable import FilesFeature
    import Foundation
    import Localization
    import Testing

    @MainActor
    struct MacDirectUploadTests {
        private let serverURL = URL(string: "https://example.com")!

        private func state(directoryPath: String) -> BrowseFeature.State {
            BrowseFeature.State(serverURL: serverURL, directoryPath: directoryPath, title: "Docs")
        }

        private nonisolated func picked(_ name: String, id: UUID) -> PickedFile {
            PickedFile(id: id, fileURL: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, size: 10)
        }

        private func staging(_ files: [PickedFile]) -> UploadStagingClient {
            UploadStagingClient(
                stageDocuments: { _ in
                    AsyncStream { continuation in
                        for file in files {
                            continuation.yield(file)
                        }
                        continuation.finish()
                    }
                },
                stagePhotos: { _ in AsyncStream { $0.finish() } },
                stageCameraCapture: { _ in nil },
                discard: { _ in },
                sweepStale: {}
            )
        }

        @Test
        func droppedFilesUploadToTheFolderOnScreenWithoutTheReviewSheet() async {
            let files = [picked("a.jpg", id: UUID(0)), picked("b.txt", id: UUID(1))]
            let store = TestStore(initialState: state(directoryPath: "Documents")) {
                BrowseFeature()
            } withDependencies: {
                $0.uploadStaging = staging(files)
            }

            await store.send(.beginUpload(.documents([URL(fileURLWithPath: "/tmp/a.jpg"), URL(fileURLWithPath: "/tmp/b.txt")])))
            await store.receive(\.directUploadStaged)
            await store.receive(\.delegate)
            #expect(store.state.uploadReview == nil)
        }

        @Test
        func filesDroppedOnAFolderRowUploadIntoThatFolder() async {
            let files = [picked("a.jpg", id: UUID(0))]
            var initial = state(directoryPath: "Documents")
            initial.access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)
            let folder = FileItem(name: "Trip", path: "Documents", dateModified: Date(), size: 0, kind: "directory")
            let store = TestStore(initialState: initial) {
                BrowseFeature()
            } withDependencies: {
                $0.uploadStaging = staging(files)
            }

            await store.send(.filesDroppedOnFolder([URL(fileURLWithPath: "/tmp/a.jpg")], folder: folder))
            await store.receive(\.directUploadStaged)
            await store.receive(.delegate(.uploadRequested([
                PendingUpload(id: UUID(0), fileURL: URL(fileURLWithPath: "/tmp/a.jpg"), fileName: "a.jpg", destination: "Documents/Trip"),
            ])))
        }

        @Test
        func filesDroppedOnAFolderWithoutUploadRightsAreIgnored() async {
            var initial = state(directoryPath: "Documents")
            initial.access = FileAccess(canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: false, canDownload: true)
            let folder = FileItem(name: "Trip", path: "Documents", dateModified: Date(), size: 0, kind: "directory")
            let store = TestStore(initialState: initial) {
                BrowseFeature()
            }

            await store.send(.filesDroppedOnFolder([URL(fileURLWithPath: "/tmp/a.jpg")], folder: folder))
        }

        @Test
        func nothingStagedShowsTheStagingError() async {
            let store = TestStore(initialState: state(directoryPath: "Documents")) {
                BrowseFeature()
            } withDependencies: {
                $0.uploadStaging = staging([])
            }

            await store.send(.beginUpload(.documents([URL(fileURLWithPath: "/tmp/gone.jpg")])))
            await store.receive(\.directUploadStaged) {
                $0.fileActionErrorMessage = L10n.Uploads.stagingFailed
            }
        }
    }
#endif
