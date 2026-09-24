#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    @testable import FilesFeature
    import Foundation
    import Testing

    @MainActor
    struct FolderWindowFeatureTests {
        private let serverURL = URL(string: "https://example.com")!

        @Test
        func delegatesAreForwardedToTheMainWindow() async {
            let forwarded = LockIsolated<[BrowseTabFeature.Action.Delegate]>([])
            let store = TestStore(initialState: FolderWindowFeature.State(serverURL: serverURL)) {
                FolderWindowFeature { delegate in forwarded.withValue { $0.append(delegate) } }
            }
            let upload = PendingUpload(fileURL: URL(fileURLWithPath: "/tmp/a.txt"), fileName: "a.txt", destination: "Docs")

            await store.send(.browse(.delegate(.uploadRequested([upload]))))
            await store.send(.browse(.delegate(.favoritesChanged)))
            await store.finish()

            #expect(forwarded.value == [.uploadRequested([upload]), .favoritesChanged])
        }

        @Test
        func folderNavigationStaysInTheWindow() async {
            let forwarded = LockIsolated<[BrowseTabFeature.Action.Delegate]>([])
            let store = TestStore(initialState: FolderWindowFeature.State(serverURL: serverURL)) {
                FolderWindowFeature { delegate in forwarded.withValue { $0.append(delegate) } }
            }

            await store.send(.browse(.navigateToDirectory(path: "Photos", title: "Photos"))) {
                $0.browse.path = StackState([BrowseFeature.State(serverURL: serverURL, directoryPath: "Photos", title: "Photos")])
            }
            #expect(forwarded.value.isEmpty)
        }
    }
#endif
