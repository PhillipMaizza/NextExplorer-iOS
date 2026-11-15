import ComposableArchitecture
import CoreModels
@testable import ShareExtensionFeature
import ShareUploads
import Testing
import TestUtils

/// Renaming the shared files before they upload. Nested in `ShareUploadFeatureTests` so it inherits
/// `.serialized` with every other share upload suite.
extension ShareUploadFeatureTests {
    @MainActor
    @Suite(.isolatedDependencies)
    struct ShareUploadNamingTests: ShareUploadHarness {
        private enum Constants {
            static let reportBase = "report"
            static let reportExtension = "pdf"
            static let photoBase = "IMG_0042"
            static let newName = "Quarterly report"
            static let paddedNewName = "  Quarterly report  "
            static let separatorName = "2026/report"
            static let reservedName = ".."
        }

        private var sharedNames: [SharedItemName] {
            [
                SharedItemName(base: Constants.reportBase, fileExtension: Constants.reportExtension),
                SharedItemName(base: Constants.photoBase),
            ]
        }

        private var editableNames: [EditableItemName] {
            sharedNames.map(EditableItemName.init)
        }

        /// A ready sheet over two named files whose staging pass records the renames it was given.
        private func readyStore(renames: LockIsolated<[[Int: String]]>) async -> Store {
            let store = store(count: 2, defaults: UploadDefaults(folderPath: TestFolder.photos))
            let names = sharedNames
            store.dependencies.sharedItems.names = { names }
            store.dependencies.sharedItems.prepare = { _, _, _, passed, _ in
                renames.withValue { $0.append(passed) }
                return PreparationReport(stagedCount: 2, failures: [])
            }
            await store.send(.onAppear) {
                $0.itemCount = 2
                $0.names = editableNames
            }
            await store.receive(\.accountsLoaded) { $0.accounts = [credentials] }
            await store.receive(\.sessionLoaded) {
                $0.credentials = credentials
                $0.destination = TestFolder.photos
                $0.phase = .checking
            }
            await store.receive(\.connectionChecked) { $0.phase = .ready }
            return store
        }

        @Test
        func anEditedNameUploadsUnderItsNewNameAndTheOthersKeepTheirs() async {
            let renames = LockIsolated<[[Int: String]]>([])
            let store = await readyStore(renames: renames)
            await store.send(.nameChanged(index: 0, Constants.paddedNewName)) {
                $0.names[0].text = Constants.paddedNewName
            }
            await uploadCleanly(store, count: 2)
            await store.send(.viewDisappeared)
            #expect(renames.value == [[0: Constants.newName]])
        }

        @Test
        func namesLeftAsTheyCameAreNotRenamed() async {
            let renames = LockIsolated<[[Int: String]]>([])
            let store = await readyStore(renames: renames)
            await uploadCleanly(store, count: 2)
            await store.send(.viewDisappeared)
            #expect(renames.value == [[:]])
        }

        @Test(arguments: [Constants.separatorName, Constants.reservedName, ""])
        func aNameTheServerWouldRefuseHoldsTheUploadBack(name: String) async {
            let renames = LockIsolated<[[Int: String]]>([])
            let store = await readyStore(renames: renames)
            await store.send(.nameChanged(index: 1, name)) { $0.names[1].text = name }
            #expect(!store.state.canUpload)
            await store.send(.uploadTapped)
            #expect(renames.value.isEmpty)
        }

        @Test
        func namesCannotChangeOnceTheFilesArePreparing() async {
            let renames = LockIsolated<[[Int: String]]>([])
            let store = await readyStore(renames: renames)
            await uploadCleanly(store, count: 2)
            await store.send(.nameChanged(index: 0, Constants.newName))
            await store.send(.viewDisappeared)
        }

        @Test
        func theFieldsStayHiddenOnTheWayToAnUploadThatStartsOnItsOwn() {
            var state = ShareUploadFeature.State()
            state.names = editableNames
            state.phase = .checking
            #expect(state.shouldShowNames)
            state.shouldUploadWithoutAsking = true
            #expect(!state.shouldShowNames)
        }

        @Test
        func aProblemNamesWhatIsWrong() {
            var name = EditableItemName(SharedItemName(base: Constants.reportBase))
            name.text = Constants.separatorName
            #expect(name.problem == .separators)
            name.text = Constants.reservedName
            #expect(name.problem == .reserved)
            name.text = ""
            #expect(name.problem == nil)
        }
    }
}
