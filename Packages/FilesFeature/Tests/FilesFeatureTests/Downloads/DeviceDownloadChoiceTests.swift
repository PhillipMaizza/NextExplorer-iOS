import TestUtils
#if os(iOS)
    import ComposableArchitecture
    import CoreModels
    @testable import FilesFeature
    import Foundation
    import Testing

    @MainActor
    @Suite(.isolatedDependencies)
    struct DeviceDownloadChoiceTests {
        private enum Constants {
            static let zip = "zip"
        }

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

        private func store(selecting items: [FileItem]) -> TestStoreOf<BrowseFeature> {
            var state = BrowseFeature.State(
                serverURL: BrowseTestSupport.serverURL,
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
            }
        }

        @Test("Files and folders together ask how to save, and Cancel saves nothing")
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
            let store = store(selecting: [folder, file])
            let archive = FileItem(
                name: "\(TestFolder.docs).\(Constants.zip)",
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
            await store.send(.bulkDownloadSaved(.oneArchive, to: .files)) {
                $0.bulkDownloadChoice = nil
            }
            await store.receive(.delegate(.saveRequested([DownloadSaveRequest(
                item: archive,
                target: .device(.files),
                archiveOf: [folder, file]
            )])))
        }

        @Test("Separate Files to the share sheet saves each item on its own")
        func separateFilesGoToTheShareSheet() async {
            let store = store(selecting: [folder, file])

            await store.send(.bulkDownloadTapped) {
                $0.isSelecting = false
                $0.selectedItemIDs = []
                $0.bulkDownloadChoice = [folder, file]
            }
            await store.send(.bulkDownloadSaved(.separateFiles, to: .share)) {
                $0.bulkDownloadChoice = nil
            }
            await store.receive(.delegate(.saveRequested([
                DownloadSaveRequest(item: folder, target: .device(.share)),
                DownloadSaveRequest(item: file, target: .device(.share)),
            ])))
        }

        @Test("Only folders skip the question and each comes as its own zip")
        func onlyFoldersSaveSeparately() async {
            let store = store(selecting: [folder])

            await store.send(.bulkDownloadTapped) {
                $0.isSelecting = false
                $0.selectedItemIDs = []
            }
            await store.receive(.delegate(.saveRequested([DownloadSaveRequest(item: folder, target: .device(.files))])))
        }

        @Test("A folder saved to the device is named as the zip it comes down as")
        func aFolderJobIsNamedAsAZip() {
            var job = DownloadQueueFeature.DownloadJob(
                id: UUID(0),
                item: folder,
                status: .queued,
                saveTarget: .device(.share)
            )
            #expect(job.fileName == "\(TestFolder.photos).\(Constants.zip)")
            #expect(job.deviceDestination == .share)
            job.saveTarget = nil
            #expect(job.deviceDestination == .files)
        }
    }
#endif
