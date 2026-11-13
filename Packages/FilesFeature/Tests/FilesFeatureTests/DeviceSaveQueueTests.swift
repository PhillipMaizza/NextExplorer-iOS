#if os(iOS)
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Localization
    import Testing
    import TestUtils

    /// Save to Device on iPhone and iPad: pictures and videos go to Photos, every other file is staged
    /// for the Save to Files panel, and the app keeps nothing.
    @MainActor
    @Suite(.isolatedDependencies)
    struct DeviceSaveQueueTests {
        private enum Constants {
            static let stagedFolder = "/staged/"
            static let photoName = "beach.jpg"
            static let videoName = "clip.mov"
            static let documentName = "report.pdf"
            static let otherDocumentName = "notes.txt"
        }

        private typealias Job = DownloadQueueFeature.DownloadJob
        private typealias Summary = DownloadQueueFeature.FinishSummary

        private let serverURL = URL(fileURLWithPath: "/")

        private nonisolated func file(_ name: String) -> FileItem {
            FileItem(
                name: name,
                path: TestFolder.files,
                dateModified: MockDate.date,
                size: 10,
                kind: (name as NSString).pathExtension
            )
        }

        private nonisolated func staged(_ name: String) -> URL {
            URL(fileURLWithPath: Constants.stagedFolder + name)
        }

        private nonisolated func temporaryFile() -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())
            FileManager.default.createFile(atPath: url.path, contents: Data("x".utf8))
            return url
        }

        private func makeStore(
            state: DownloadQueueFeature.State? = nil,
            photos: @escaping @Sendable (URL, Bool) async throws -> Void = { _, _ in },
            discarded: LockIsolated<[URL]> = LockIsolated([])
        ) -> TestStoreOf<DownloadQueueFeature> {
            TestStore(initialState: state ?? DownloadQueueFeature.State(serverURL: serverURL)) {
                DownloadQueueFeature()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.date = .constant(MockDate.date)
                $0.filesClient.flushDownloadConnections = {}
                $0.filesClient.downloadItem = { _, _, _ in temporaryFile() }
                $0.deviceSaver = DeviceSaver(
                    saveToPhotos: photos,
                    stage: { _, name in URL(fileURLWithPath: Constants.stagedFolder + name) },
                    discard: { urls in discarded.withValue { $0 += urls } }
                )
            }
        }

        private func receiveStart(_ store: TestStoreOf<DownloadQueueFeature>, id: Int) async {
            await store.receive(\.startNextIfIdle) {
                $0.jobs[id: UUID(id)]?.status = .downloading
                $0.jobs[id: UUID(id)]?.startedAt = MockDate.date
            }
        }

        @Test
        func aPictureGoesToPhotosAndTheAppKeepsNothing() async {
            let added = LockIsolated<[String]>([])
            let discarded = LockIsolated<[URL]>([])
            let store = makeStore(
                photos: { url, isVideo in added.withValue { $0.append("\(url.lastPathComponent) \(isVideo)") } },
                discarded: discarded
            )

            await store.send(.enqueue([file(Constants.photoName)])) {
                $0.jobs = [Job(id: UUID(0), item: file(Constants.photoName), status: .queued)]
            }
            await receiveStart(store, id: 0)
            await store.receive(\.downloadResponse) { $0.jobs[id: UUID(0)]?.status = .completed }
            await store.receive(.delegate(.itemSaved))
            var summary = Summary(savedCount: 1, failedCount: 0)
            summary.photosCount = 1
            await store.receive(.delegate(.queueFinished(summary)))

            #expect(added.value == ["\(Constants.photoName) false"])
            #expect(discarded.value == [staged(Constants.photoName)])
            #expect(store.state.jobs[id: UUID(0)]?.savedURL == nil)
        }

        @Test
        func aVideoGoesToPhotosAsAVideo() async {
            let added = LockIsolated<[String]>([])
            let store = makeStore(photos: { url, isVideo in
                added.withValue { $0.append("\(url.lastPathComponent) \(isVideo)") }
            })

            await store.send(.enqueue([file(Constants.videoName)])) {
                $0.jobs = [Job(id: UUID(0), item: file(Constants.videoName), status: .queued)]
            }
            await receiveStart(store, id: 0)
            await store.receive(\.downloadResponse) { $0.jobs[id: UUID(0)]?.status = .completed }
            await store.receive(.delegate(.itemSaved))
            var summary = Summary(savedCount: 1, failedCount: 0)
            summary.photosCount = 1
            await store.receive(.delegate(.queueFinished(summary)))

            #expect(added.value == ["\(Constants.videoName) true"])
        }

        @Test
        func aDocumentStaysStagedForTheSaveToFilesPanel() async {
            let discarded = LockIsolated<[URL]>([])
            let store = makeStore(
                photos: { _, _ in Issue.record("A document must not go to Photos") },
                discarded: discarded
            )

            await store.send(.enqueue([file(Constants.documentName)])) {
                $0.jobs = [Job(id: UUID(0), item: file(Constants.documentName), status: .queued)]
            }
            await receiveStart(store, id: 0)
            await store.receive(\.downloadResponse) {
                $0.jobs[id: UUID(0)]?.status = .completed
                $0.jobs[id: UUID(0)]?.savedURL = staged(Constants.documentName)
            }
            await store.receive(.delegate(.itemSaved))
            var summary = Summary(savedCount: 1, failedCount: 0)
            summary.exportURLs = [staged(Constants.documentName)]
            await store.receive(.delegate(.queueFinished(summary)))

            #expect(discarded.value.isEmpty)
        }

        @Test
        func aMixedBatchSplitsBetweenPhotosAndTheExportPanel() async {
            let store = makeStore()

            await store.send(.enqueue([file(Constants.photoName), file(Constants.otherDocumentName)])) {
                $0.jobs = [
                    Job(id: UUID(0), item: file(Constants.photoName), status: .queued),
                    Job(id: UUID(1), item: file(Constants.otherDocumentName), status: .queued),
                ]
            }
            await receiveStart(store, id: 0)
            await store.receive(\.downloadResponse) { $0.jobs[id: UUID(0)]?.status = .completed }
            await store.receive(.delegate(.itemSaved))
            await receiveStart(store, id: 1)
            await store.receive(\.downloadResponse) {
                $0.jobs[id: UUID(1)]?.status = .completed
                $0.jobs[id: UUID(1)]?.savedURL = staged(Constants.otherDocumentName)
            }
            await store.receive(.delegate(.itemSaved))
            var summary = Summary(savedCount: 2, failedCount: 0)
            summary.photosCount = 1
            summary.exportURLs = [staged(Constants.otherDocumentName)]
            await store.receive(.delegate(.queueFinished(summary)))
        }

        @Test
        func deniedPhotosAccessFailsTheItemWithAnActionableMessageAndDropsTheStagedCopy() async {
            let discarded = LockIsolated<[URL]>([])
            let store = makeStore(photos: { _, _ in throw DeviceSaveError.photosAccessDenied }, discarded: discarded)

            await store.send(.enqueue([file(Constants.photoName)])) {
                $0.jobs = [Job(id: UUID(0), item: file(Constants.photoName), status: .queued)]
            }
            await receiveStart(store, id: 0)
            await store.receive(\.downloadResponse) {
                $0.jobs[id: UUID(0)]?.status = .failed(L10n.DownloadQueue.photosAccessDenied)
            }
            await store.receive(.delegate(.queueFinished(Summary(savedCount: 0, failedCount: 1))))

            #expect(discarded.value == [staged(Constants.photoName)])
        }

        @Test
        func aPhotosFailureReportsItsOwnMessage() async {
            let store = makeStore(photos: { _, _ in throw DeviceSaveError.photosSaveFailed })

            await store.send(.enqueue([file(Constants.photoName)])) {
                $0.jobs = [Job(id: UUID(0), item: file(Constants.photoName), status: .queued)]
            }
            await receiveStart(store, id: 0)
            await store.receive(\.downloadResponse) {
                $0.jobs[id: UUID(0)]?.status = .failed(L10n.DownloadQueue.photosSaveFailed)
            }
            await store.receive(.delegate(.queueFinished(Summary(savedCount: 0, failedCount: 1))))
        }

        @Test
        func aFolderIsNotQueued() async {
            let store = makeStore()
            let folder = FileItem(
                name: TestFolder.photos,
                path: TestFolder.files,
                dateModified: MockDate.date,
                size: 0,
                kind: FileItem.directoryKind
            )

            await store.send(.enqueue([folder]))
            #expect(store.state.jobs.isEmpty)
        }

        @Test
        func cancellingDropsTheStagedCopiesOfFinishedDocuments() async {
            let discarded = LockIsolated<[URL]>([])
            var finished = Job(id: UUID(0), item: file(Constants.documentName), status: .completed)
            finished.savedURL = staged(Constants.documentName)
            var state = DownloadQueueFeature.State(serverURL: serverURL)
            state.jobs = [finished]
            let store = makeStore(state: state, discarded: discarded)

            await store.send(.cancelAllTapped) { $0.jobs = [] }

            #expect(discarded.value == [staged(Constants.documentName)])
        }
    }
#endif
