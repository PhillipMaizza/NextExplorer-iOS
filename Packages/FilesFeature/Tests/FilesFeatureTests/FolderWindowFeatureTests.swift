#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Testing

    @MainActor
    struct FolderWindowFeatureTests {
        private let serverURL = URL(string: "https://example.com")!

        @Test
        func delegatesAreForwardedToTheMainWindow() async {
            let forwarded = LockIsolated<[FolderWindowFeature.Forwarded]>([])
            let store = TestStore(initialState: FolderWindowFeature.State(serverURL: serverURL)) {
                FolderWindowFeature { item in forwarded.withValue { $0.append(item) } }
            }
            let upload = PendingUpload(fileURL: URL(fileURLWithPath: "/tmp/a.txt"), fileName: "a.txt", destination: "Docs")

            await store.send(.browse(.delegate(.uploadRequested([upload]))))
            await store.send(.browse(.delegate(.favoritesChanged)))
            await store.finish()

            #expect(forwarded.value == [.browse(.uploadRequested([upload])), .browse(.favoritesChanged)])
        }

        @Test
        func aFinishedChangeHereIsHandedToTheMainWindow() async {
            let forwarded = LockIsolated<[FolderWindowFeature.Forwarded]>([])
            let folder = FileItem(name: "New", path: "", dateModified: Date(), size: 0, kind: "directory")
            let store = TestStore(initialState: FolderWindowFeature.State(serverURL: serverURL)) {
                FolderWindowFeature { item in forwarded.withValue { $0.append(item) } }
            }
            store.exhaustivity = .off

            await store.send(.browse(.root(.newFolderResponse(.success(folder)))))
            await store.send(.browse(.root(.transferResponse(.failure(.offline)))))
            await store.finish()

            #expect(forwarded.value == [.folderChanged(.folders([""]))])
        }

        @Test
        func anotherWindowsChangeReloadsTheFoldersShownHere() async {
            var state = FolderWindowFeature.State(serverURL: serverURL)
            state.browse.path.append(BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos"))
            let store = TestStore(initialState: state) {
                FolderWindowFeature { _ in }
            } withDependencies: {
                $0.filesClient.browse = { _, _ in throw FilesClientError.offline }
                $0.filesClient.favorites = { _ in [] }
            }
            store.exhaustivity = .off

            await store.send(.otherWindowChanged(.folders(["Photos", "Elsewhere"])))
            await store.receive(\.browse.refreshDirectory)
            await store.receive(\.browse.refreshDirectory)
            await store.receive(\.browse.path)
        }

        @Test
        func folderNavigationStaysInTheWindow() async {
            let forwarded = LockIsolated<[FolderWindowFeature.Forwarded]>([])
            let store = TestStore(initialState: FolderWindowFeature.State(serverURL: serverURL)) {
                FolderWindowFeature { item in forwarded.withValue { $0.append(item) } }
            }

            await store.send(.browse(.navigateToDirectory(path: "Photos", title: "Photos"))) {
                $0.browse.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos")])
            }
            #expect(forwarded.value.isEmpty)
        }
    }
#endif
