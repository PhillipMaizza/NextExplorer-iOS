import TestUtils
#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Localization
    import NetworkClient
    import Testing

    @MainActor
    @Suite(.isolatedDependencies)
    struct MacDownloadTests {
        private let serverURL = BrowseTestSupport.serverURL
        private let access = BrowseTestSupport.fullAccess

        private func temporaryFolder() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name(), isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        /// What `downloadItem` hands back: a fresh temporary file the caller moves away.
        private nonisolated static func downloadedFile(_ contents: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())
            try Data(contents.utf8).write(to: url)
            return url
        }

        @Test("Cancelling the save panel queues nothing")
        func cancellingTheSavePanelQueuesNothing() async {
            let item = FileItem(
                name: TestFile.report,
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 10,
                kind: TestKind.pdf
            )
            let suggested = LockIsolated<[String]>([])
            let store = TestStore(initialState: BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: TestFolder.docs,
                title: TestFolder.docs
            )) {
                BrowseFeature()
            } withDependencies: {
                $0.saveLocationPicker.chooseFile = { name in
                    suggested.withValue { $0.append(name) }
                    return nil
                }
            }

            await store.send(.downloadTapped(item))
            await store.finish()

            #expect(suggested.value == [TestFile.report])
        }

        @Test("A chosen place goes to the download queue without blocking file actions")
        func aChosenPlaceGoesToTheDownloadQueueWithoutBlockingFileActions() async throws {
            let item = FileItem(
                name: TestFile.report,
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 10,
                kind: TestKind.pdf
            )
            let target = try temporaryFolder().appendingPathComponent("Saved report.pdf")
            let store = TestStore(initialState: BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: TestFolder.docs,
                title: TestFolder.docs
            )) {
                BrowseFeature()
            } withDependencies: {
                $0.saveLocationPicker.chooseFile = { _ in target }
            }

            await store.send(.downloadTapped(item))
            await store.receive(.delegate(.saveRequested([DownloadSaveRequest(
                item: item,
                target: .replacing(target)
            )])))
        }

        @Test("Several items go into the picked folder")
        func severalItemsGoIntoThePickedFolder() async throws {
            let first = FileItem(
                name: TestFile.aText,
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 1,
                kind: TestKind.text
            )
            let second = FileItem(
                name: TestFile.bText,
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 1,
                kind: TestKind.text
            )
            let folder = try temporaryFolder()
            var state = BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: TestFolder.docs,
                title: TestFolder.docs
            )
            state.items = [first, second]
            state.isSelecting = true
            state.selectedItemIDs = [first.id, second.id]
            let store = TestStore(initialState: state) {
                BrowseFeature()
            } withDependencies: {
                $0.saveLocationPicker.chooseFolder = { folder }
            }

            await store.send(.bulkDownloadTapped) {
                $0.isSelecting = false
                $0.selectedItemIDs = []
            }
            await store.receive(.delegate(.saveRequested([
                DownloadSaveRequest(item: first, target: .into(folder)),
                DownloadSaveRequest(item: second, target: .into(folder)),
            ])))
        }

        @Test("A file lands at the chosen place, replacing what was there")
        func aFileLandsAtTheChosenPlaceReplacingWhatWasThere() async throws {
            let item = FileItem(
                name: "report.txt",
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 5,
                kind: TestKind.text
            )
            let target = try temporaryFolder().appendingPathComponent("Saved report.txt")
            try Data(TestValue.outdated.utf8).write(to: target)
            let client = FilesClient().with { $0.downloadItem = { _, _, _ in try Self.downloadedFile("hello") } }

            let saved = try await MacDownloadSaving.save(
                DownloadSaveRequest(item: item, target: .replacing(target)), serverURL: serverURL, filesClient: client
            ) { _ in }

            #expect(saved == target)
            #expect(try String(contentsOf: target, encoding: .utf8) == "hello")
        }

        @Test("Saving into a folder never overwrites and never escapes it")
        func intoAFolderNeverOverwritesAndNeverEscapesIt() async throws {
            let folder = try temporaryFolder()
            try Data("mine".utf8).write(to: folder.appendingPathComponent(TestFile.aText))
            let clashing = FileItem(
                name: TestFile.aText,
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 1,
                kind: TestKind.text
            )
            let hostile = FileItem(
                name: "../../escape.txt",
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 1,
                kind: TestKind.text
            )
            let client = FilesClient().with { $0.downloadItem = { _, _, _ in try Self.downloadedFile("new") } }

            let renamed = try await MacDownloadSaving.save(
                DownloadSaveRequest(item: clashing, target: .into(folder)), serverURL: serverURL, filesClient: client
            ) { _ in }
            let contained = try await MacDownloadSaving.save(
                DownloadSaveRequest(item: hostile, target: .into(folder)), serverURL: serverURL, filesClient: client
            ) { _ in }

            #expect(renamed.lastPathComponent == "a 2.txt")
            #expect(try String(contentsOf: folder.appendingPathComponent(TestFile.aText), encoding: .utf8) == "mine")
            #expect(contained.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
            #expect(contained.lastPathComponent == "escape.txt")
        }

        @Test("A folder is recreated as a real folder tree with byte progress")
        func aFolderIsRecreatedAsARealFolderTreeWithByteProgress() async throws {
            let folder = FileItem(
                name: "Trip",
                path: "",
                dateModified: MockDate.date,
                size: 0,
                kind: FileItem.directoryKind
            )
            let photo = FileItem(
                name: TestFile.aPhoto,
                path: "Trip",
                dateModified: MockDate.date,
                size: 6,
                kind: TestKind.photo
            )
            let nested = FileItem(
                name: "Day1",
                path: "Trip",
                dateModified: MockDate.date,
                size: 0,
                kind: FileItem.directoryKind
            )
            let note = FileItem(
                name: "note.txt",
                path: "Trip/Day1",
                dateModified: MockDate.date,
                size: 4,
                kind: TestKind.text
            )
            let target = try temporaryFolder().appendingPathComponent("Trip")
            let access = access
            let client = FilesClient().with {
                $0.browse = { _, path in
                    switch path {
                    case "Trip": BrowseResult(items: [photo, nested], access: access, path: path)
                    case "Trip/Day1": BrowseResult(items: [note], access: access, path: path)
                    default: BrowseResult(items: [], access: access, path: path)
                    }
                }
                $0
                    .downloadItem = { _, item, _ in
                        try Self.downloadedFile(item.name == TestFile.aPhoto ? "photo" : "note")
                    }
            }
            let reported = LockIsolated<[TransferProgress]>([])

            _ = try await MacDownloadSaving.save(
                DownloadSaveRequest(item: folder, target: .replacing(target)), serverURL: serverURL, filesClient: client
            ) { update in reported.withValue { $0.append(update) } }

            #expect(try String(contentsOf: target.appendingPathComponent(TestFile.aPhoto), encoding: .utf8) == "photo")
            #expect(try String(contentsOf: target.appendingPathComponent("Day1/note.txt"), encoding: .utf8) == "note")
            #expect(reported.value.last == TransferProgress(receivedBytes: 10, expectedBytes: 10))
        }

        @Test("A failed folder save keeps the folder already there")
        func aFailedFolderSaveKeepsTheFolderAlreadyThere() async throws {
            let folder = FileItem(
                name: "Trip",
                path: "",
                dateModified: MockDate.date,
                size: 0,
                kind: FileItem.directoryKind
            )
            let photo = FileItem(
                name: TestFile.aPhoto,
                path: "Trip",
                dateModified: MockDate.date,
                size: 1,
                kind: TestKind.photo
            )
            let target = try temporaryFolder().appendingPathComponent("Trip")
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            let kept = target.appendingPathComponent("keep.txt")
            try Data("keep".utf8).write(to: kept)
            let access = access
            let client = FilesClient().with {
                $0.browse = { _, path in BrowseResult(items: [photo], access: access, path: path) }
                $0.downloadItem = { _, _, _ in throw URLError(.networkConnectionLost) }
            }

            await #expect(throws: (any Error).self) {
                try await MacDownloadSaving.save(
                    DownloadSaveRequest(item: folder, target: .replacing(target)), serverURL: self.serverURL,
                    filesClient: client
                ) { _ in }
            }
            #expect(try String(contentsOf: kept, encoding: .utf8) == "keep")
        }

        @Test("An unreadable subfolder fails the save instead of leaving files out")
        func anUnreadableSubfolderFailsTheSaveInsteadOfLeavingFilesOut() async throws {
            let folder = FileItem(
                name: "Trip",
                path: "",
                dateModified: MockDate.date,
                size: 0,
                kind: FileItem.directoryKind
            )
            let nested = FileItem(
                name: "Locked",
                path: "Trip",
                dateModified: MockDate.date,
                size: 0,
                kind: FileItem.directoryKind
            )
            let target = try temporaryFolder().appendingPathComponent("Trip")
            let access = access
            let client = FilesClient().with {
                $0.browse = { _, path in
                    guard path == "Trip" else { throw FilesClientError.forbidden(message: nil) }
                    return BrowseResult(items: [nested], access: access, path: path)
                }
            }

            await #expect(throws: (any Error).self) {
                try await MacDownloadSaving.save(
                    DownloadSaveRequest(item: folder, target: .replacing(target)), serverURL: self.serverURL,
                    filesClient: client
                ) { _ in }
            }
            #expect(!FileManager.default.fileExists(atPath: target.path))
        }

        @Test("The queue saves in Finder, reports byte progress and remembers where the file landed")
        func theQueueSavesInFinderAndRemembersWhere() async throws {
            let item = FileItem(
                name: "report.txt",
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 5,
                kind: TestKind.text
            )
            let target = try temporaryFolder().appendingPathComponent("report.txt")
            let jobID = UUID(0)
            let store = TestStore(initialState: DownloadQueueFeature.State(serverURL: serverURL)) {
                DownloadQueueFeature()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.date = .constant(MockDate.date)
                $0.filesClient.flushDownloadConnections = {}
                $0.filesClient.downloadItem = { _, _, onProgress in
                    onProgress(TransferProgress(receivedBytes: 5, expectedBytes: 5))
                    return try Self.downloadedFile("hello")
                }
            }

            await store.send(.enqueueSaves([DownloadSaveRequest(item: item, target: .replacing(target))])) {
                $0.jobs = [DownloadQueueFeature.DownloadJob(
                    id: jobID,
                    item: item,
                    status: .queued,
                    saveTarget: .replacing(target)
                )]
            }
            await store.receive(\.startNextIfIdle) {
                $0.jobs[id: jobID]?.status = .downloading
                $0.jobs[id: jobID]?.startedAt = MockDate.date
            }
            await store.receive(\.progress) {
                $0.jobs[id: jobID]?.receivedBytes = 5
                $0.jobs[id: jobID]?.expectedBytes = 5
            }
            await store.receive(\.downloadResponse) {
                $0.jobs[id: jobID]?.status = .completed
                $0.jobs[id: jobID]?.savedURL = target
            }
            await store.receive(.delegate(.itemSaved))
            await store.receive(.delegate(.queueFinished(DownloadQueueFeature.FinishSummary(
                savedCount: 1,
                failedCount: 0,
                lastSavedURL: target
            ))))

            #expect(try String(contentsOf: target, encoding: .utf8) == "hello")
        }

        @Test("A disk failure during a save reads as a local problem, not a network one")
        func aDiskFailureDuringASaveReadsAsALocalProblem() async throws {
            let item = FileItem(
                name: TestFile.aText,
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 4,
                kind: TestKind.text
            )
            let blocker = try temporaryFolder().appendingPathComponent("blocker")
            try Data("not a folder".utf8).write(to: blocker)
            let client = FilesClient().with { $0.downloadItem = { _, _, _ in try Self.downloadedFile("data") } }

            await #expect {
                try await MacDownloadSaving.save(
                    DownloadSaveRequest(item: item, target: .replacing(blocker.appendingPathComponent(TestFile.aText))),
                    serverURL: self.serverURL, filesClient: client
                ) { _ in }
            } throws: { error in
                guard case .decoding = error as? FilesClientError else { return false }
                return true
            }
        }

        @Test("A saved folder keeps its own name in the queue, a zip download gets the zip name")
        func aSavedFolderKeepsItsOwnNameInTheQueue() {
            let folder = FileItem(
                name: "Trip",
                path: "",
                dateModified: MockDate.date,
                size: 0,
                kind: FileItem.directoryKind
            )
            let save = DownloadQueueFeature.DownloadJob(
                id: UUID(0),
                item: folder,
                status: .queued,
                saveTarget: .into(URL(fileURLWithPath: "/tmp"))
            )
            let zip = DownloadQueueFeature.DownloadJob(id: UUID(1), item: folder, status: .queued)

            #expect(save.fileName == "Trip")
            #expect(zip.fileName == "Trip.zip")
        }

        @Test("Space refuses archives and large files unless saved offline")
        func spaceRefusesArchivesAndLargeFilesUnlessSavedOffline() {
            let archive = FileItem(name: "backup.7z", path: "", dateModified: MockDate.date, size: 10, kind: "7z")
            let movie = FileItem(
                name: "movie.mp4",
                path: "",
                dateModified: MockDate.date,
                size: MacQuickLookPolicy.byteLimit + 1,
                kind: TestKind.video
            )
            let photo = FileItem(
                name: TestFile.aPhoto,
                path: "",
                dateModified: MockDate.date,
                size: 1_000,
                kind: TestKind.photo
            )

            #expect(MacQuickLookPolicy.refusal(for: archive, isSavedOffline: false) == L10n.Browse.quickLookUnavailable)
            #expect(MacQuickLookPolicy.refusal(for: movie, isSavedOffline: false) == L10n.Browse.quickLookTooLarge)
            #expect(MacQuickLookPolicy.refusal(for: movie, isSavedOffline: true) == nil)
            #expect(MacQuickLookPolicy.refusal(for: photo, isSavedOffline: false) == nil)
        }
    }

#endif
