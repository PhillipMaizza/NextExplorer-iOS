import TestUtils
#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    @testable import FilesFeature
    import Foundation
    import Localization
    import Testing
    import TestUtils

    @Suite(.isolatedDependencies)
    @MainActor
    struct MacDirectUploadTests {
        private let serverURL = URL(string: TestHost.exampleURLString)!

        private func state(directoryPath: String) -> BrowseFeature.State {
            BrowseFeature.State(serverURL: serverURL, directoryPath: directoryPath, title: TestFolder.docs)
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
            let files = [picked(TestFile.aPhoto, id: UUID(0)), picked(TestFile.bText, id: UUID(1))]
            let store = TestStore(initialState: state(directoryPath: TestFolder.documents)) {
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
        func nothingStagedShowsTheStagingError() async {
            let store = TestStore(initialState: state(directoryPath: TestFolder.documents)) {
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
