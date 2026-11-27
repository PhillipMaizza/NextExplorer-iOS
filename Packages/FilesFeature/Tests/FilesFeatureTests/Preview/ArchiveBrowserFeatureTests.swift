import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import NetworkClient
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct ArchiveBrowserFeatureTests {
    private let archive = FileItem(
        name: FilesFeatureTestValue.bundleName,
        path: TestFolder.files,
        dateModified: MockDate.date,
        size: 0,
        kind: "zip"
    )
    private let photos = ArchiveListingEntry(
        path: TestFolder.photos,
        name: TestFolder.photos,
        isDirectory: true,
        size: nil
    )
    private let notes = ArchiveListingEntry(path: TestFile.notes, name: TestFile.notes, isDirectory: false, size: 71)
    private let photo = ArchiveListingEntry(path: TestFile.photo, name: TestFile.photo, isDirectory: false, size: 10264)
    private let locked = ArchiveListingEntry(
        path: TestFile.report,
        name: TestFile.report,
        isDirectory: false,
        size: 640,
        isEncrypted: true
    )
    private var inPhotos: ArchiveListingEntry {
        ArchiveListingEntry(
            path: "\(TestFolder.photos)/\(TestFile.aPhoto)",
            name: TestFile.aPhoto,
            isDirectory: false,
            size: 2048
        )
    }

    private var root: [ArchiveListingEntry] {
        [photos, notes, photo, locked]
    }

    private func store(
        localFileURL: URL? = nil,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<ArchiveBrowserFeature> {
        TestStore(
            initialState: ArchiveBrowserFeature.State(
                archive: archive,
                serverURL: TestHost.serverURL,
                localFileURL: localFileURL
            )
        ) {
            ArchiveBrowserFeature()
        } withDependencies: {
            $0.filesClient.serverFeatures = { _ in ServerFeatures(archiveExtensions: ["zip", "7z"]) }
            $0.filesClient.listArchive = { [root, inPhotos] _, _, inside in
                ArchiveListing(inside: inside, entries: inside.isEmpty ? root : [inPhotos])
            }
            configure(&$0)
        }
    }

    private func openRoot(_ store: TestStoreOf<ArchiveBrowserFeature>) async {
        await store.send(.task) { $0.phase = .loading }
        await store.receive(\.sourceResolved.success) { $0.source = .server }
        await store.receive(\.levelResponse) {
            $0.levels[""] = root
            $0.phase = .loaded
        }
    }

    @Test("A server that browses this kind of archive lists its top level through the archive route")
    func serverListsTopLevel() async {
        await openRoot(store())
    }

    @Test("A server too old to browse archives downloads the archive and reads it on the Mac")
    func olderServerReadsLocally() async {
        let downloaded = URL(fileURLWithPath: "/tmp/\(FilesFeatureTestValue.bundleName)")
        let store = store {
            $0.filesClient.serverFeatures = { _ in ServerFeatures() }
            $0.filesClient.downloadRawFile = { _, _ in downloaded }
            $0.archiveReader.list = { [root] _, _, inside in ArchiveListing(inside: inside, entries: root) }
        }

        await store.send(.task) { $0.phase = .loading }
        await store.receive(\.sourceResolved.success) { $0.source = .local(downloaded) }
        await store.receive(\.levelResponse) {
            $0.levels[""] = root
            $0.phase = .loaded
        }
    }

    @Test("A folder lists once, and a crumb back to the top shows the level already listed")
    func crumbReusesListedLevel() async {
        let store = store()
        await openRoot(store)

        await store.send(.folderOpened(TestFolder.photos)) {
            $0.path = [TestFolder.photos]
            $0.phase = .loading
        }
        await store.receive(\.levelResponse) {
            $0.levels[TestFolder.photos] = [inPhotos]
            $0.phase = .loaded
        }
        await store.send(.crumbTapped(0)) { $0.path = [] }
        await store.send(.folderOpened(TestFolder.photos)) { $0.path = [TestFolder.photos] }
    }

    @Test("Going back before a folder answers drops the late answer for that folder")
    func backCancelsStaleListing() async {
        let store = store {
            $0.filesClient.listArchive = { [root] _, _, inside in
                if !inside.isEmpty {
                    try await suspendUntilCancelled()
                }
                return ArchiveListing(inside: inside, entries: root)
            }
        }
        await openRoot(store)

        await store.send(.folderOpened(TestFolder.photos)) {
            $0.path = [TestFolder.photos]
            $0.phase = .loading
        }
        await store.send(.backTapped) {
            $0.path = []
            $0.phase = .loaded
        }
    }

    @Test("An encrypted file says so without asking the server for it")
    func encryptedFileRefusesToOpen() async {
        let store = store()
        await openRoot(store)

        await store.send(.fileOpened(locked)) {
            $0.entry = .init(path: TestFile.report, phase: .failed(L10n.Archive.entryEncrypted))
        }
        #expect(!store.state.canExtract)
    }

    @Test("A file opens from only its own bytes, steps to the next file, and Back returns to the folder")
    func fileOpensStepsAndCloses() async throws {
        let scratch = ArchiveBrowserFeature.scratchDirectory(for: archive)
        defer { try? FileManager.default.removeItem(at: scratch) }
        let store = store {
            $0.filesClient.downloadArchiveEntry = { _, _, entryPath in
                let url = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())
                try Data(entryPath.utf8).write(to: url)
                return url
            }
        }
        await openRoot(store)

        await store.send(.fileOpened(notes)) { $0.entry = .init(path: TestFile.notes, phase: .loading) }
        await store.receive(\.entryResponse) {
            $0.entry?.phase = .loaded(scratch.appendingPathComponent(TestFile.notes))
        }
        #expect(try String(contentsOf: scratch.appendingPathComponent(TestFile.notes), encoding: .utf8) == TestFile
            .notes)

        await store.send(.stepped(1))
        await store.receive(\.fileOpened) { $0.entry = .init(path: TestFile.photo, phase: .loading) }
        await store.receive(\.entryResponse) {
            $0.entry?.phase = .loaded(scratch.appendingPathComponent(TestFile.photo))
        }
        await store.send(.backTapped) { $0.entry = nil }
        await store.send(.backTapped)
    }

    @Test("A password protected archive explains itself instead of a status code")
    func passwordProtectedArchive() async {
        let store = store {
            $0.filesClient.listArchive = { _, _, _ in
                throw FilesClientError.server(statusCode: HTTPStatus.conflict.rawValue)
            }
        }

        await store.send(.task) { $0.phase = .loading }
        await store.receive(\.sourceResolved.success) { $0.source = .server }
        await store.receive(\.levelResponse) { $0.phase = .failed(L10n.Archive.passwordProtected) }
    }

    @Test("Extract takes the whole archive at the top, the folder inside it, or the open file")
    func extractPathsFollowWhereYouAre() {
        var state = ArchiveBrowserFeature.State(archive: archive, serverURL: TestHost.serverURL)
        #expect(state.extractPaths == nil)
        state.path = [TestFolder.photos]
        #expect(state.extractPaths == [TestFolder.photos])
        state.entry = .init(path: inPhotos.path, phase: .loading)
        #expect(state.extractPaths == [inPhotos.path])
    }

    @Test("Crumbs name the archive, each folder, and the open file")
    func crumbsNameEveryLevel() {
        var state = ArchiveBrowserFeature.State(archive: archive, serverURL: TestHost.serverURL)
        state.path = [TestFolder.photos]
        state.entry = .init(path: inPhotos.path, phase: .loading)
        #expect(state.crumbs == [FilesFeatureTestValue.bundleName, TestFolder.photos, TestFile.aPhoto])
    }
}
