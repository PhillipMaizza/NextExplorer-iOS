#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Testing

    @MainActor
    struct MacDownloadTests {
        private let serverURL = URL(string: "https://example.com")!
        private let access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)

        private func temporaryFolder() throws -> URL {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        private func cachedFile(_ name: String, contents: String, in folder: URL) throws -> URL {
            let url = folder.appendingPathComponent(name)
            try Data(contents.utf8).write(to: url)
            return url
        }

        @Test
        func cancellingTheSavePanelEndsTheDownloadWithoutAnError() async {
            let item = FileItem(name: "report.pdf", path: "Docs", dateModified: Date(), size: 10, kind: "pdf")
            let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")) {
                BrowseFeature()
            } withDependencies: {
                $0.saveLocationPicker.chooseFile = { _ in nil }
                $0.filesClient.downloadRawFile = { _, _ in
                    Issue.record("Nothing is downloaded once the save panel is cancelled")
                    throw CancellationError()
                }
            }

            await store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: false)) {
                $0.isPerformingFileAction = true
            }
            await store.receive(\.downloadCancelled) {
                $0.isPerformingFileAction = false
            }
        }

        @Test
        func aFileIsCopiedToTheChosenLocation() async throws {
            let item = FileItem(name: "report.txt", path: "Docs", dateModified: Date(), size: 5, kind: "txt")
            let cache = try temporaryFolder()
            let target = try temporaryFolder().appendingPathComponent("Saved report.txt")
            let cached = try cachedFile("report.txt", contents: "hello", in: cache)

            let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "Docs", title: "Docs")) {
                BrowseFeature()
            } withDependencies: {
                $0.saveLocationPicker.chooseFile = { _ in target }
                $0.filesClient.downloadRawFile = { _, _ in cached }
            }
            store.exhaustivity = .off

            await store.send(.downloadTapped(item, .documents, removeArchiveAfterDownload: false))
            await store.receive(\.downloadResponse.success) {
                $0.lastSavedDownloadURL = target
            }
            #expect(try String(contentsOf: target, encoding: .utf8) == "hello")
        }

        @Test
        func aFolderIsRecreatedAsARealFolderTree() async throws {
            let folder = FileItem(name: "Trip", path: "", dateModified: Date(), size: 0, kind: "directory")
            let photo = FileItem(name: "a.jpg", path: "Trip", dateModified: Date(), size: 1, kind: "jpg")
            let nested = FileItem(name: "Day1", path: "Trip", dateModified: Date(), size: 0, kind: "directory")
            let note = FileItem(name: "note.txt", path: "Trip/Day1", dateModified: Date(), size: 1, kind: "txt")
            let cache = try temporaryFolder()
            let photoData = try cachedFile("a.jpg", contents: "photo", in: cache)
            let noteData = try cachedFile("note.txt", contents: "note", in: cache)
            let target = try temporaryFolder().appendingPathComponent("Trip")
            let access = access

            let store = TestStore(initialState: BrowseFeature.State(serverURL: serverURL, directoryPath: "", title: "Home")) {
                BrowseFeature()
            } withDependencies: {
                $0.saveLocationPicker.chooseFile = { _ in target }
                $0.filesClient.browse = { _, path in
                    switch path {
                    case "Trip": BrowseResult(items: [photo, nested], access: access, path: path)
                    case "Trip/Day1": BrowseResult(items: [note], access: access, path: path)
                    default: BrowseResult(items: [], access: access, path: path)
                    }
                }
                $0.filesClient.downloadRawFile = { _, item in item.name == "a.jpg" ? photoData : noteData }
            }
            store.exhaustivity = .off

            await store.send(.downloadTapped(folder, .documents, removeArchiveAfterDownload: false))
            await store.receive(\.downloadResponse.success)
            #expect(try String(contentsOf: target.appendingPathComponent("a.jpg"), encoding: .utf8) == "photo")
            #expect(try String(contentsOf: target.appendingPathComponent("Day1/note.txt"), encoding: .utf8) == "note")
        }
    }
#endif
