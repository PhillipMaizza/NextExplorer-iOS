#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DependenciesTestSupport
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Localization
    import NetworkClient
    import Testing

    @MainActor
    @Suite(.dependencies)
    struct MacDownloadTests {
        private let serverURL = URL(string: "https://example.com")!
        private let access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)

        private func temporaryFolder() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        /// What `downloadItem` hands back: a fresh temporary file the caller moves away.
        private nonisolated static func downloadedFile(_ contents: String) throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try Data(contents.utf8).write(to: url)
            return url
        }

        @Test
        func cancellingTheSavePanelQueuesNothing() async {
            let item = FileItem(name: "report.pdf", path: "Docs", dateModified: Date(), size: 10, kind: "pdf")
            let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")) {
                BrowseFeature()
            } withDependencies: {
                $0.saveLocationPicker.chooseFile = { _ in nil }
            }

            await store.send(.downloadTapped(item))
            await store.finish()
        }

        @Test
        func aChosenPlaceGoesToTheDownloadQueueWithoutBlockingFileActions() async throws {
            let item = FileItem(name: "report.pdf", path: "Docs", dateModified: Date(), size: 10, kind: "pdf")
            let target = try temporaryFolder().appendingPathComponent("Saved report.pdf")
            let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")) {
                BrowseFeature()
            } withDependencies: {
                $0.saveLocationPicker.chooseFile = { _ in target }
            }

            await store.send(.downloadTapped(item))
            await store.receive(.delegate(.saveRequested([DownloadSaveRequest(item: item, target: .replacing(target))])))
        }

        @Test
        func severalItemsGoIntoThePickedFolder() async throws {
            let first = FileItem(name: "a.txt", path: "Docs", dateModified: Date(), size: 1, kind: "txt")
            let second = FileItem(name: "b.txt", path: "Docs", dateModified: Date(), size: 1, kind: "txt")
            let folder = try temporaryFolder()
            var state = BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")
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

        @Test
        func aFileLandsAtTheChosenPlaceReplacingWhatWasThere() async throws {
            let item = FileItem(name: "report.txt", path: "Docs", dateModified: Date(), size: 5, kind: "txt")
            let target = try temporaryFolder().appendingPathComponent("Saved report.txt")
            try Data("old".utf8).write(to: target)
            let client = FilesClient().with { $0.downloadItem = { _, _, _ in try Self.downloadedFile("hello") } }

            let saved = try await MacDownloadSaving.save(
                DownloadSaveRequest(item: item, target: .replacing(target)), serverURL: serverURL, filesClient: client
            ) { _ in }

            #expect(saved == target)
            #expect(try String(contentsOf: target, encoding: .utf8) == "hello")
        }

        @Test
        func intoAFolderNeverOverwritesAndNeverEscapesIt() async throws {
            let folder = try temporaryFolder()
            try Data("mine".utf8).write(to: folder.appendingPathComponent("a.txt"))
            let clashing = FileItem(name: "a.txt", path: "Docs", dateModified: Date(), size: 1, kind: "txt")
            let hostile = FileItem(name: "../../escape.txt", path: "Docs", dateModified: Date(), size: 1, kind: "txt")
            let client = FilesClient().with { $0.downloadItem = { _, _, _ in try Self.downloadedFile("new") } }

            let renamed = try await MacDownloadSaving.save(
                DownloadSaveRequest(item: clashing, target: .into(folder)), serverURL: serverURL, filesClient: client
            ) { _ in }
            let contained = try await MacDownloadSaving.save(
                DownloadSaveRequest(item: hostile, target: .into(folder)), serverURL: serverURL, filesClient: client
            ) { _ in }

            #expect(renamed.lastPathComponent == "a 2.txt")
            #expect(try String(contentsOf: folder.appendingPathComponent("a.txt"), encoding: .utf8) == "mine")
            #expect(contained.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
            #expect(contained.lastPathComponent == "escape.txt")
        }

        @Test
        func aFolderIsRecreatedAsARealFolderTreeWithByteProgress() async throws {
            let folder = FileItem(name: "Trip", path: "", dateModified: Date(), size: 0, kind: "directory")
            let photo = FileItem(name: "a.jpg", path: "Trip", dateModified: Date(), size: 6, kind: "jpg")
            let nested = FileItem(name: "Day1", path: "Trip", dateModified: Date(), size: 0, kind: "directory")
            let note = FileItem(name: "note.txt", path: "Trip/Day1", dateModified: Date(), size: 4, kind: "txt")
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
                $0.downloadItem = { _, item, _ in try Self.downloadedFile(item.name == "a.jpg" ? "photo" : "note") }
            }
            let reported = LockIsolated<[TransferProgress]>([])

            _ = try await MacDownloadSaving.save(
                DownloadSaveRequest(item: folder, target: .replacing(target)), serverURL: serverURL, filesClient: client
            ) { update in reported.withValue { $0.append(update) } }

            #expect(try String(contentsOf: target.appendingPathComponent("a.jpg"), encoding: .utf8) == "photo")
            #expect(try String(contentsOf: target.appendingPathComponent("Day1/note.txt"), encoding: .utf8) == "note")
            #expect(reported.value.last == TransferProgress(receivedBytes: 10, expectedBytes: 10))
        }

        @Test
        func aFailedFolderSaveKeepsTheFolderAlreadyThere() async throws {
            let folder = FileItem(name: "Trip", path: "", dateModified: Date(), size: 0, kind: "directory")
            let photo = FileItem(name: "a.jpg", path: "Trip", dateModified: Date(), size: 1, kind: "jpg")
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
                    DownloadSaveRequest(item: folder, target: .replacing(target)), serverURL: self.serverURL, filesClient: client
                ) { _ in }
            }
            #expect(try String(contentsOf: kept, encoding: .utf8) == "keep")
        }

        @Test
        func anUnreadableSubfolderFailsTheSaveInsteadOfLeavingFilesOut() async throws {
            let folder = FileItem(name: "Trip", path: "", dateModified: Date(), size: 0, kind: "directory")
            let nested = FileItem(name: "Locked", path: "Trip", dateModified: Date(), size: 0, kind: "directory")
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
                    DownloadSaveRequest(item: folder, target: .replacing(target)), serverURL: self.serverURL, filesClient: client
                ) { _ in }
            }
            #expect(!FileManager.default.fileExists(atPath: target.path))
        }

        @Test
        func theQueueSavesInFinderAndRemembersWhere() async throws {
            let item = FileItem(name: "report.txt", path: "Docs", dateModified: Date(), size: 5, kind: "txt")
            let target = try temporaryFolder().appendingPathComponent("report.txt")
            let jobID = UUID(0)
            let store = TestStore(initialState: DownloadQueueFeature.State(serverURL: serverURL)) {
                DownloadQueueFeature()
            } withDependencies: {
                $0.uuid = .incrementing
                $0.date.now = Date(timeIntervalSince1970: 0)
                $0.filesClient.flushDownloadConnections = {}
                $0.filesClient.downloadItem = { _, _, _ in try Self.downloadedFile("hello") }
            }
            store.exhaustivity = .off

            await store.send(.enqueueSaves([DownloadSaveRequest(item: item, target: .replacing(target))]))
            await store.receive(\.downloadResponse)
            await store.receive(.delegate(.itemSaved))
            await store.receive(.delegate(.queueFinished(DownloadQueueFeature.FinishSummary(savedCount: 1, failedCount: 0, lastSavedURL: target))))
            #expect(store.state.jobs[id: jobID]?.savedURL == target)
            #expect(store.state.jobs[id: jobID]?.fileName == "report.txt")
            #expect(try String(contentsOf: target, encoding: .utf8) == "hello")
        }

        @Test
        func aSavedFolderKeepsItsOwnNameInTheQueue() {
            let folder = FileItem(name: "Trip", path: "", dateModified: Date(), size: 0, kind: "directory")
            let save = DownloadQueueFeature.DownloadJob(id: UUID(0), item: folder, status: .queued, saveTarget: .into(URL(fileURLWithPath: "/tmp")))
            let zip = DownloadQueueFeature.DownloadJob(id: UUID(1), item: folder, status: .queued)

            #expect(save.fileName == "Trip")
            #expect(zip.fileName == "Trip.zip")
        }

        @Test
        func spaceRefusesArchivesAndLargeFilesUnlessSavedOffline() {
            let archive = FileItem(name: "backup.7z", path: "", dateModified: Date(), size: 10, kind: "7z")
            let movie = FileItem(name: "movie.mp4", path: "", dateModified: Date(), size: MacQuickLookPolicy.byteLimit + 1, kind: "mp4")
            let photo = FileItem(name: "a.jpg", path: "", dateModified: Date(), size: 1_000, kind: "jpg")

            #expect(MacQuickLookPolicy.refusal(for: archive, isSavedOffline: false) == L10n.Browse.quickLookUnavailable)
            #expect(MacQuickLookPolicy.refusal(for: movie, isSavedOffline: false) == L10n.Browse.quickLookTooLarge)
            #expect(MacQuickLookPolicy.refusal(for: movie, isSavedOffline: true) == nil)
            #expect(MacQuickLookPolicy.refusal(for: photo, isSavedOffline: false) == nil)
        }
    }

    private extension FilesClient {
        func with(_ change: (inout FilesClient) -> Void) -> FilesClient {
            var copy = self
            change(&copy)
            return copy
        }
    }
#endif
