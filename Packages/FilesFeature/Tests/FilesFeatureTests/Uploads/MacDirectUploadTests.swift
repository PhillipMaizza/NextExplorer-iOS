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

            await store.send(.beginUpload(.documents([
                URL(fileURLWithPath: "/tmp/a.jpg"),
                URL(fileURLWithPath: "/tmp/b.txt"),
            ])))
            await store.receive(\.directUploadStaged)
            await store.receive(\.delegate)
            #expect(store.state.uploadReview == nil)
        }

        @Test("A dropped folder gets a folder of its own, as on the web: never merged into one of the same name")
        func droppedFolderUploadsIntoAReservedFolder() async {
            let trip = TestFolder.documents
            let files = [
                picked("\(trip)/a.jpg", id: UUID(0)),
                picked("\(trip)/Day 1/b.jpg", id: UUID(1)),
                picked(TestFile.bText, id: UUID(2)),
            ]
            let reserved = LockIsolated<[[String]]>([])
            let store = TestStore(initialState: state(directoryPath: TestFolder.inbox)) {
                BrowseFeature()
            } withDependencies: {
                $0.uploadStaging = staging(files)
                $0.filesClient.reserveFolderUpload = { _, destination, folder in
                    reserved.withValue { $0.append([destination, folder]) }
                    return "\(folder) (1)"
                }
            }

            await store.send(.beginUpload(.documents([URL(fileURLWithPath: "/tmp/\(trip)")])))
            await store.receive(\.directUploadStaged)
            let names = ["\(trip) (1)/a.jpg", "\(trip) (1)/Day 1/b.jpg", TestFile.bText]
            await store.receive(.delegate(.uploadRequested(zip(files, names).map { file, name in
                PendingUpload(
                    id: file.id,
                    fileURL: file.fileURL,
                    fileName: name,
                    destination: TestFolder.inbox,
                    size: 10
                )
            })))
            #expect(reserved.value == [[TestFolder.inbox, trip]])
        }

        @Test("The upload keeps every file, renamed under the reserved folder, and loose files as they are")
        func reservedFolderRenamesOnlyThatFolder() {
            let file = picked("\(TestFolder.documents)/Day 1/b.jpg", id: UUID(0))
            let loose = picked(TestFile.bText, id: UUID(1))
            let reserved = [TestFolder.documents: "\(TestFolder.documents) (1)"]
            #expect(UploadedFolder.renamed(file, reserved: reserved)
                .fileName == "\(TestFolder.documents) (1)/Day 1/b.jpg")
            #expect(UploadedFolder.renamed(loose, reserved: reserved) == loose)
            #expect(UploadedFolder.root(of: TestFile.bText) == nil)
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
