import TestUtils
#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Testing

    @MainActor
    @Suite(.isolatedDependencies)
    struct MacDownloadChoiceTests {
        private let serverURL = BrowseTestSupport.serverURL
        private let file = FileItem(
            name: TestFile.aText,
            path: TestFolder.docs,
            dateModified: MockDate.date,
            size: 1,
            kind: TestKind.text
        )
        private let folder = FileItem(
            name: TestFolder.photos,
            path: TestFolder.docs,
            dateModified: MockDate.date,
            size: 0,
            kind: FileItem.directoryKind
        )

        private func store(
            selecting items: [FileItem],
            file chosenFile: URL? = nil,
            folder chosenFolder: URL? = nil
        ) -> TestStoreOf<BrowseFeature> {
            var state = BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: TestFolder.docs,
                title: TestFolder.docs
            )
            state.access = BrowseTestSupport.fullAccess
            state.items = IdentifiedArray(uniqueElements: items)
            state.isSelecting = true
            state.selectedItemIDs = Set(items.map(\.id))
            return TestStore(initialState: state) {
                BrowseFeature()
            } withDependencies: {
                $0.date.now = MockDate.date
                $0.saveLocationPicker.chooseFile = { _ in chosenFile }
                $0.saveLocationPicker.chooseFolder = { chosenFolder }
            }
        }

        @Test("Files and folders together ask how to download, and Cancel queues nothing")
        func aMixedSelectionAsksFirst() async {
            let store = store(selecting: [folder, file])

            await store.send(.bulkDownloadTapped) {
                $0.isSelecting = false
                $0.selectedItemIDs = []
                $0.bulkDownloadChoice = [folder, file]
            }
            await store.send(.bulkDownloadChoiceMade(nil)) {
                $0.bulkDownloadChoice = nil
            }
        }

        @Test("One Archive saves one zip named after the folder, holding the whole selection")
        func oneArchiveSavesOneZip() async {
            let target = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(TestID.name())
            let asked = LockIsolated<String?>(nil)
            let store = store(selecting: [folder, file], file: target)
            store.dependencies.saveLocationPicker.chooseFile = { name in
                asked.setValue(name)
                return target
            }
            let archive = FileItem(
                name: "\(TestFolder.docs).zip",
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 0,
                kind: Constants.zip
            )

            await store.send(.bulkDownloadTapped) {
                $0.isSelecting = false
                $0.selectedItemIDs = []
                $0.bulkDownloadChoice = [folder, file]
            }
            await store.send(.bulkDownloadChoiceMade(.oneArchive)) {
                $0.bulkDownloadChoice = nil
            }
            await store.receive(.delegate(.saveRequested([
                DownloadSaveRequest(item: archive, target: .replacing(target), archiveOf: [folder, file]),
            ])))
            #expect(asked.value == archive.name)
        }

        @Test("Separate Files keeps each file as it is and each folder as a folder, in one picked folder")
        func separateFilesGoIntoThePickedFolder() async {
            let picked = URL(fileURLWithPath: NSTemporaryDirectory())
            let store = store(selecting: [folder, file], folder: picked)

            await store.send(.bulkDownloadTapped) {
                $0.isSelecting = false
                $0.selectedItemIDs = []
                $0.bulkDownloadChoice = [folder, file]
            }
            await store.send(.bulkDownloadChoiceMade(.separateFiles)) {
                $0.bulkDownloadChoice = nil
            }
            await store.receive(.delegate(.saveRequested([
                DownloadSaveRequest(item: folder, target: .into(picked)),
                DownloadSaveRequest(item: file, target: .into(picked)),
            ])))
        }

        @Test("Only files skip the question")
        func onlyFilesSkipTheQuestion() async {
            let picked = URL(fileURLWithPath: NSTemporaryDirectory())
            let other = FileItem(
                name: TestFile.bText,
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 1,
                kind: TestKind.text
            )
            let store = store(selecting: [file, other], folder: picked)

            await store.send(.bulkDownloadTapped) {
                $0.isSelecting = false
                $0.selectedItemIDs = []
            }
            await store.receive(.delegate(.saveRequested([
                DownloadSaveRequest(item: file, target: .into(picked)),
                DownloadSaveRequest(item: other, target: .into(picked)),
            ])))
        }

        @Test("The archive is asked for by its items and their folder, and lands where chosen")
        func theArchiveLandsWhereChosen() async throws {
            let folderURL = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())
            try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
            let target = folderURL.appendingPathComponent("\(TestFolder.docs).zip")
            let asked = LockIsolated<([String], String)?>(nil)
            let client = FilesClient().with {
                $0.downloadArchive = { _, items, basePath, _ in
                    asked.setValue((items.map(\.id), basePath))
                    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name())
                    try Data(Constants.zipBytes.utf8).write(to: temporary)
                    return temporary
                }
            }
            let archive = FileItem(
                name: target.lastPathComponent,
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 0,
                kind: Constants.zip
            )

            let saved = try await MacDownloadSaving.save(
                DownloadSaveRequest(item: archive, target: .replacing(target), archiveOf: [folder, file]),
                serverURL: serverURL,
                filesClient: client
            ) { _ in }

            #expect(saved == target)
            #expect(asked.value?.0 == [folder.id, file.id])
            #expect(asked.value?.1 == TestFolder.docs)
            #expect(try String(contentsOf: target, encoding: .utf8) == Constants.zipBytes)
        }
    }

    private enum Constants {
        static let zip = "zip"
        static let zipBytes = "PK"
    }
#endif
