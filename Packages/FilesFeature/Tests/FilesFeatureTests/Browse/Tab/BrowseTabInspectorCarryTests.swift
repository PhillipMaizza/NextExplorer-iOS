#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Testing
    import TestUtils

    @Suite(.isolatedDependencies)
    @MainActor
    struct BrowseTabInspectorCarryTests {
        private let serverURL = BrowseTestSupport.serverURL
        private let photos = BrowseFixtures.folder(TestFolder.photos)

        private nonisolated func metadata(of item: FileItem) -> FileMetadata {
            FileMetadata(
                path: item.id,
                name: item.name,
                kind: item.kind,
                size: item.size,
                dateModified: MockDate.date,
                dateCreated: MockDate.date
            )
        }

        private func store(
            _ state: BrowseTabFeature.State,
            metadataGate: AsyncGate,
            usageGate: AsyncGate,
            clock: TestClock<Duration> = TestClock()
        ) -> TestStoreOf<BrowseTabFeature> {
            let photosMetadata = metadata(of: photos)
            return TestStore(initialState: state) {
                BrowseTabFeature()
            } withDependencies: {
                $0.date = .constant(MockDate.date)
                $0.continuousClock = clock
                $0.filesClient.fetchMetadata = { _, _ in
                    try await metadataGate.wait()
                    return photosMetadata
                }
                $0.filesClient.fetchUsage = { _, _ in
                    try await usageGate.wait()
                    return StorageUsage()
                }
            }
        }

        @Test("Opening a folder with the inspector open shows that folder on the new screen")
        func openingAFolderCarriesTheInspector() async {
            var state = BrowseTabFeature.State(serverURL: serverURL)
            state.root.items = [photos]
            state.root.infoItem = photos
            state.root.infoPhase = .loaded
            let metadataGate = AsyncGate()
            let usageGate = AsyncGate()
            let store = store(state, metadataGate: metadataGate, usageGate: usageGate)

            await store.send(.root(.delegate(.openFolder(photos)))) {
                $0.path.append(BrowseNavigation.screen(for: photos, serverURL: serverURL, openedFrom: $0.root))
                $0.inspectorLeftOpenPaths = [""]
            }
            await store.receive(\.path[id: 0].infoTapped) {
                $0.path[id: 0]?.infoItem = photos
                $0.path[id: 0]?.infoPhase = .loading
            }
            await store.receive(\.root.infoDismissed) {
                $0.root.infoItem = nil
                $0.root.infoPhase = .idle
            }
            metadataGate.open()
            await store.receive(\.path[id: 0].infoMetadataResponse.success) {
                $0.path[id: 0]?.infoPhase = .loaded
                $0.path[id: 0]?.infoMetadata = metadata(of: photos)
            }
            usageGate.open()
            await store.receive(\.path[id: 0].infoUsageResponse.success)
        }

        @Test("Going back to a folder the inspector followed from selects and shows the folder just left")
        func goingBackCarriesTheInspector() async {
            var state = BrowseTabFeature.State(serverURL: serverURL)
            state.root.items = [photos]
            state.inspectorLeftOpenPaths = [""]
            var pushed = BrowseNavigation.screen(for: photos, serverURL: serverURL)
            pushed.infoItem = photos
            pushed.infoPhase = .loaded
            state.path.append(pushed)
            let metadataGate = AsyncGate()
            let usageGate = AsyncGate()
            let store = store(state, metadataGate: metadataGate, usageGate: usageGate)

            await store.send(.goBack) {
                $0.forwardStack = [pushed]
                $0.path.removeAll()
                $0.inspectorLeftOpenPaths = []
            }
            await store.receive(\.root.tableSelectionChanged) {
                $0.root.selectedItemIDs = [photos.id]
            }
            await store.receive(\.root.infoTapped) {
                $0.root.infoItem = photos
                $0.root.infoPhase = .loading
            }
            metadataGate.open()
            await store.receive(\.root.infoMetadataResponse.success) {
                $0.root.infoPhase = .loaded
                $0.root.infoMetadata = metadata(of: photos)
            }
            usageGate.open()
            await store.receive(\.root.infoUsageResponse.success)
        }

        @Test("Going back to a folder that had no inspector closes it first, then goes back")
        func goingBackClosesTheInspectorFirst() async {
            var state = BrowseTabFeature.State(serverURL: serverURL)
            state.root.items = [photos]
            var pushed = BrowseNavigation.screen(for: photos, serverURL: serverURL)
            pushed.infoItem = photos
            pushed.infoPhase = .loaded
            state.path.append(pushed)
            let clock = TestClock()
            let store = store(state, metadataGate: AsyncGate(), usageGate: AsyncGate(), clock: clock)
            var closed = pushed
            closed.infoItem = nil
            closed.infoPhase = .idle

            await store.send(.goBack)
            await store.receive(\.path[id: 0].infoDismissed) {
                $0.path[id: 0] = closed
            }
            await clock.advance(by: .seconds(DSMotion.quickFadeDuration))
            await store.receive(\.inspectorClosedForBack) {
                $0.forwardStack = [closed]
                $0.path.removeAll()
            }
        }

        @Test("Home forgets where the inspector was left open, so a later Back does not reopen it")
        func homeForgetsWhereTheInspectorWasLeftOpen() async {
            var state = BrowseTabFeature.State(serverURL: serverURL)
            state.root.items = [photos]
            state.inspectorLeftOpenPaths = ["", photos.id]
            let pushed = BrowseNavigation.screen(for: photos, serverURL: serverURL)
            state.path.append(pushed)
            let store = store(state, metadataGate: AsyncGate(), usageGate: AsyncGate())

            await store.send(.goHome) {
                $0.forwardStack = [pushed]
                $0.path.removeAll()
                $0.inspectorLeftOpenPaths = []
            }
        }

        @Test("A folder opened during the inspector fade stays open")
        func aFolderOpenedDuringTheFadeStaysOpen() async {
            var state = BrowseTabFeature.State(serverURL: serverURL)
            state.root.items = [photos]
            var pushed = BrowseNavigation.screen(for: photos, serverURL: serverURL)
            pushed.infoItem = photos
            pushed.infoPhase = .loaded
            state.path.append(pushed)
            let clock = TestClock()
            let store = store(state, metadataGate: AsyncGate(), usageGate: AsyncGate(), clock: clock)
            let inbox = BrowseFixtures.folder(TestFolder.inbox, in: photos.id)

            await store.send(.goBack)
            await store.receive(\.path[id: 0].infoDismissed) {
                $0.path[id: 0]?.infoItem = nil
                $0.path[id: 0]?.infoPhase = .idle
            }
            await store.send(.path(.element(id: 0, action: .delegate(.openFolder(inbox))))) {
                $0.path.append(BrowseNavigation.screen(for: inbox, serverURL: serverURL, openedFrom: $0.path[id: 0]))
            }
            await clock.advance(by: .seconds(DSMotion.quickFadeDuration))
            await store.receive(\.inspectorClosedForBack)
            #expect(store.state.path.last?.directoryPath == inbox.id)
        }

        @Test("Going back with the selection inspector open closes it first, then goes back")
        func goingBackClosesTheSelectionInspectorFirst() async {
            var state = BrowseTabFeature.State(serverURL: serverURL)
            state.root.items = [photos]
            var pushed = BrowseNavigation.screen(for: photos, serverURL: serverURL)
            pushed.isInfoShowingSelection = true
            state.path.append(pushed)
            let clock = TestClock()
            let store = store(state, metadataGate: AsyncGate(), usageGate: AsyncGate(), clock: clock)
            var closed = pushed
            closed.isInfoShowingSelection = false

            await store.send(.goBack)
            await store.receive(\.path[id: 0].infoDismissed) {
                $0.path[id: 0] = closed
            }
            await clock.advance(by: .seconds(DSMotion.quickFadeDuration))
            await store.receive(\.inspectorClosedForBack) {
                $0.forwardStack = [closed]
                $0.path.removeAll()
            }
        }
    }
#endif
