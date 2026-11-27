import TestUtils
#if os(iOS)
    import ComposableArchitecture
    import CoreModels
    @testable import FilesFeature
    import Foundation
    import Testing

    @MainActor
    @Suite(.isolatedDependencies)
    struct VersionsNavigationTests {
        private let file = FileItem(
            name: TestFile.aText,
            path: TestFolder.docs,
            dateModified: MockDate.date,
            size: 1,
            kind: TestKind.text
        )

        private func store(isVersionsEnabled: Bool) -> TestStoreOf<BrowseFeature> {
            var state = BrowseFeature.State(
                serverURL: BrowseTestSupport.serverURL,
                directoryPath: TestFolder.docs,
                title: TestFolder.docs
            )
            state.isVersionsEnabled = isVersionsEnabled
            state.infoItem = file
            return TestStore(initialState: state) { BrowseFeature() }
        }

        @Test("Versions opens the page for a file and closes Get Info, and Back clears it")
        func versionsOpenAndClose() async {
            let store = store(isVersionsEnabled: true)

            await store.send(.versionsTapped(file)) {
                $0.versionsItem = file
                $0.infoItem = nil
            }
            await store.send(.versionsClosed) { $0.versionsItem = nil }
        }

        @Test("Nothing opens when the server keeps no versions, or for a folder")
        func versionsNeedsAFileAndTheServer() async {
            await store(isVersionsEnabled: false).send(.versionsTapped(file))
            let folder = FileItem(
                name: TestFolder.photos,
                path: TestFolder.docs,
                dateModified: MockDate.date,
                size: 0,
                kind: FileItem.directoryKind
            )
            await store(isVersionsEnabled: true).send(.versionsTapped(folder))
        }
    }
#endif
