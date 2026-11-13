import TestUtils
#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Testing

    @Suite(.isolatedDependencies)
    @MainActor
    struct FolderWindowFeatureTests {
        private let serverURL = BrowseTestSupport.serverURL

        private func makeStore(
            _ state: FolderWindowFeature.State? = nil,
            forwarded: LockIsolated<[FolderWindowFeature.Forwarded]> = LockIsolated([]),
            configure: (inout DependencyValues) -> Void = { _ in }
        ) -> TestStoreOf<FolderWindowFeature> {
            TestStore(initialState: state ?? FolderWindowFeature.State(serverURL: serverURL)) {
                FolderWindowFeature { item in forwarded.withValue { $0.append(item) } }
            } withDependencies: {
                configure(&$0)
            }
        }

        // MARK: Handing things to the main window

        @Test("What the browser asks of the app shell is forwarded to the main window")
        func delegatesAreForwardedToTheMainWindow() async {
            let forwarded = LockIsolated<[FolderWindowFeature.Forwarded]>([])
            let store = makeStore(forwarded: forwarded)
            let upload = PendingUpload(
                id: UUID(0),
                fileURL: URL(fileURLWithPath: "/tmp/a.txt"),
                fileName: TestFile.aText,
                destination: TestFolder.docs
            )

            await store.send(.browse(.delegate(.uploadRequested([upload]))))
            await store.send(.browse(.delegate(.favoritesChanged)))
            await store.finish()

            #expect(forwarded.value == [.browse(.uploadRequested([upload])), .browse(.favoritesChanged)])
        }

        @Test("A folder created here is handed to the main window as a change to its folder")
        func aFinishedChangeHereIsHandedToTheMainWindow() async {
            let forwarded = LockIsolated<[FolderWindowFeature.Forwarded]>([])
            let folder = FileItem(
                name: "New",
                path: "",
                dateModified: MockDate.date,
                size: 0,
                kind: FileItem.directoryKind
            )
            let store = makeStore(forwarded: forwarded)

            await store.send(.browse(.root(.newFolderResponse(.success(folder))))) {
                $0.browse.root.items = [folder]
                $0.browse.root.$undoStack.withLock { $0 = [FileUndoEntry(.created([folder]))] }
            }
            await store.finish()

            #expect(forwarded.value == [.folderChanged(.folders([""]))])
        }

        @Test("A failed change here is not handed to the main window, the listings are as they were")
        func aFailedChangeHereIsNotHandedOver() async {
            let forwarded = LockIsolated<[FolderWindowFeature.Forwarded]>([])
            let store = makeStore(forwarded: forwarded)

            await store.send(.browse(.root(.transferResponse(.failure(.offline))))) {
                $0.browse.root.transferErrorMessage = FilesClientError.offline.userMessage
            }
            await store.finish()

            #expect(forwarded.value.isEmpty)
        }

        @Test("Folder navigation stays in the window and tells the main window nothing")
        func folderNavigationStaysInTheWindow() async {
            let forwarded = LockIsolated<[FolderWindowFeature.Forwarded]>([])
            let store = makeStore(forwarded: forwarded)

            await store.send(.browse(.navigateToDirectory(path: TestFolder.photos, title: TestFolder.photos))) {
                $0.browse.path = StackState([BrowseFeature.State(
                    serverURL: serverURL,
                    directoryPath: TestFolder.photos,
                    title: TestFolder.photos
                )])
            }
            await store.finish()

            #expect(forwarded.value.isEmpty)
        }

        // MARK: Changes from other windows

        @Test("Another window's change reloads the folders shown here that it touched, and only those")
        func anotherWindowsChangeReloadsTheFoldersShownHere() async {
            var state = FolderWindowFeature.State(serverURL: serverURL)
            state.browse.path.append(BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: TestFolder.photos,
                title: TestFolder.photos
            ))
            let id = state.browse.path.ids[0]
            let listing = AsyncGate()
            let store = makeStore(state) { $0.holdFolderListings([TestFolder.photos: listing]) }

            await store.send(.otherWindowChanged(.folders([TestFolder.photos, "Elsewhere"])))
            await store.receive(\.browse.refreshDirectory)
            await store.receive(\.browse.refreshDirectory)
            await store.receive(\.browse.path[id: id].refreshButtonTapped) {
                $0.browse.path[id: id]?.phase = .loading
            }
            listing.open()
            await store.receive(\.browse.path[id: id].itemsResponse.success) {
                $0.browse.path[id: id]?.phase = .loaded
                $0.browse.path[id: id]?.access = BrowseTestSupport.readOnlyAccess
            }
            await store.receive(\.browse.path[id: id].favoritesResponse) {
                $0.browse.path[id: id]?.hasLoadedFavorites = true
            }
        }

        @Test("A move or an undo elsewhere reloads the root and every pushed folder shown here")
        func aMoveOrUndoReloadsEveryFolderInTheOtherWindows() async {
            var state = FolderWindowFeature.State(serverURL: serverURL)
            state.browse.path.append(BrowseFeature.State(
                serverURL: serverURL,
                directoryPath: TestFolder.photos,
                title: TestFolder.photos
            ))
            let id = state.browse.path.ids[0]
            let gates = ["": AsyncGate(), TestFolder.photos: AsyncGate()]
            let store = makeStore(state) { $0.holdFolderListings(gates) }

            await store.send(.otherWindowChanged(.everything))
            await store.receive(\.browse.syncPathStack)
            await store.receive(\.browse.root.refreshButtonTapped) {
                $0.browse.root.phase = .loading
            }
            await store.receive(\.browse.path[id: id].refreshButtonTapped) {
                $0.browse.path[id: id]?.phase = .loading
            }
            gates[""]?.open()
            await store.receive(\.browse.root.itemsResponse.success) {
                $0.browse.root.phase = .loaded
                $0.browse.root.access = BrowseTestSupport.readOnlyAccess
            }
            await store.receive(\.browse.root.favoritesResponse) {
                $0.browse.root.hasLoadedFavorites = true
            }
            gates[TestFolder.photos]?.open()
            await store.receive(\.browse.path[id: id].itemsResponse.success) {
                $0.browse.path[id: id]?.phase = .loaded
                $0.browse.path[id: id]?.access = BrowseTestSupport.readOnlyAccess
            }
            await store.receive(\.browse.path[id: id].favoritesResponse) {
                $0.browse.path[id: id]?.hasLoadedFavorites = true
            }
        }
    }
#endif
