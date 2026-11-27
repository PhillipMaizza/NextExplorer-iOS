import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

private enum Fixture {
    static let token = "e8B5cREF5E"
    static let folderName = "OnlyImg"
    static let fileName = "secret.txt"
    static let shareRoot = "share/\(token)"

    static func received(
        id: String = "r1",
        isDirectory: Bool = true,
        isDownloadAllowed: Bool = true,
        expiresAt: Date? = nil
    ) -> Share {
        Share(
            id: id,
            shareToken: token,
            ownerId: "other",
            sourceName: isDirectory ? folderName : fileName,
            isDirectory: isDirectory,
            accessMode: .readonly,
            sharingType: .users,
            hasPassword: false,
            permissions: SharePermissions(canDownload: isDownloadAllowed),
            expiresAt: expiresAt,
            label: "TO-ME",
            createdAt: MockDate.date,
            updatedAt: MockDate.date
        )
    }

    static func ownFolder() -> Share {
        Share(
            id: "o1",
            shareToken: token,
            ownerId: "me",
            sourcePath: folderName,
            sourceSpace: "personal",
            isDirectory: true,
            accessMode: .readonly,
            sharingType: .anyone,
            hasPassword: false,
            createdAt: MockDate.date,
            updatedAt: MockDate.date
        )
    }
}

@Suite(.isolatedDependencies)
@MainActor
struct ReceivedShareOpenTests {
    private func makeStore(_ mutate: (inout SharedFeature.State) -> Void) -> TestStoreOf<SharedFeature> {
        var state = SharedFeature.State(serverURL: TestHost.serverURL)
        state.now = MockDate.date
        mutate(&state)
        return TestStore(initialState: state) { SharedFeature() }
    }

    @Test("Opening a folder shared with me asks to browse it under its own name")
    func openingAReceivedFolderBrowsesIt() async {
        let share = Fixture.received()
        let store = makeStore { $0.withMe = [share] }

        await store.send(.openTapped(share))
        await store.receive(\.delegate, .openFolder(path: Fixture.shareRoot, title: Fixture.folderName))
    }

    @Test("An expired share, a file share and a share of my own do not open as a folder")
    func onlyLiveReceivedFoldersOpen() async {
        let expired = Fixture.received(id: "r2", expiresAt: MockDate.date.addingTimeInterval(-60))
        let file = Fixture.received(id: "r3", isDirectory: false)
        let own = Fixture.ownFolder()
        let store = makeStore {
            $0.withMe = [expired, file]
            $0.byMe = [own]
        }

        await store.send(.openTapped(expired))
        await store.send(.openTapped(file))
        await store.send(.openTapped(own))
    }

    @Test(
        "Download on a file shared with me fetches it by its shared path; a folder, an expired share or one without downloads sends nothing"
    )
    func downloadingAReceivedFile() async throws {
        let file = Fixture.received(id: "r3", isDirectory: false)
        let expired = Fixture.received(id: "r4", isDirectory: false, expiresAt: MockDate.date.addingTimeInterval(-60))
        let folder = Fixture.received()
        let viewOnly = Fixture.received(id: "r5", isDirectory: false, isDownloadAllowed: false)
        let item = try #require(file.receivedFileItem)
        let store = makeStore { $0.withMe = [file, expired, folder, viewOnly] }

        await store.send(.downloadTapped(file))
        await store.receive(\.delegate, .downloadRequested([item]))
        await store.send(.downloadTapped(expired))
        await store.send(.downloadTapped(folder))
        await store.send(.downloadTapped(viewOnly))
    }
}

@Suite(.isolatedDependencies)
@MainActor
struct ReceivedShareBrowseTests: MainTabTestSupport {
    private var screen: BrowseFeature.State {
        BrowseFeature.State(serverURL: serverURL, directoryPath: Fixture.shareRoot, title: Fixture.folderName)
    }

    private func openShare(_ store: TestStoreOf<MainTabFeature>) async {
        await store.send(.shared(.delegate(.openFolder(path: Fixture.shareRoot, title: Fixture.folderName))))
        await store.receive(\.sharedBrowse.navigateToDirectory) {
            $0.sharedBrowse.path[id: 0] = screen
        }
    }

    @Test("A received folder opens inside Shared, leaves Browse alone and stays out of Recent Folders")
    func receivedFolderOpensInsideShared() async {
        let store = makeStore(makeState { $0.selectedTab = .shared })
        await openShare(store)
        #expect(store.state.browse.path.isEmpty)
        #expect(store.state.selectedTab == .shared)
    }

    @Test("Back at the share root returns to the With me list, and Forward reopens the share")
    func backAtTheShareRootReturnsToWithMe() async {
        let store = makeStore(makeState { $0.selectedTab = .shared }) {
            $0.filesClient.sharedWithMeLinks = { _ in [] }
        }
        await openShare(store)

        await store.send(.backRequested)
        await store.receive(\.sharedBrowse.goBack) {
            $0.sharedBrowse.forwardStack = [screen]
            $0.sharedBrowse.path.removeAll()
        }
        await receiveWithMeList(store)

        await store.send(.forwardRequested)
        await store.receive(\.sharedBrowse.goForward) {
            $0.sharedBrowse.forwardStack = []
            $0.sharedBrowse.path[id: 1] = screen
        }
    }

    private func receiveWithMeList(_ store: TestStoreOf<MainTabFeature>) async {
        await store.receive(\.sharedBrowse.delegate, .openSharedWithMe)
        await store.receive(\.sharedWithMeRequested)
        await store.receive(\.shared.segmentChanged) {
            $0.shared.segment = .withMe
            $0.shared.phases[.withMe] = .loading
        }
        await store.receive(\.shared.sharesResponse) {
            $0.shared.phases[.withMe] = .loaded
            $0.shared.dataSources[.withMe] = .live
        }
    }

    @Test("Up at the share root also returns to the With me list")
    func upAtTheShareRootReturnsToWithMe() async {
        let store = makeStore(makeState { $0.selectedTab = .shared }) {
            $0.filesClient.sharedWithMeLinks = { _ in [] }
        }
        await openShare(store)

        await store.send(.enclosingFolderRequested)
        await store.receive(\.sharedBrowse.goToEnclosingFolder) {
            $0.sharedBrowse.forwardStack = [screen]
            $0.sharedBrowse.path.removeAll()
        }
        await receiveWithMeList(store)
    }

    @Test("Go to Folder with a share path opens it under Shared")
    func goToFolderWithASharePathOpensUnderShared() async {
        let store = makeStore(makeState { $0.isGoToFolderPresented = true })

        await store.send(.goToFolderRequested(Fixture.shareRoot)) {
            $0.selectedTab = .shared
            $0.isGoToFolderPresented = false
        }
        await store.receive(\.sharedBrowse.navigateToDirectory) {
            $0.sharedBrowse.path[id: 0] = BrowseFeature.State(
                serverURL: serverURL, directoryPath: Fixture.shareRoot, title: Fixture.token
            )
        }
    }

    @Test("Leaving a share for a folder outside it, as a search result does, opens it in Browse")
    func aPathOutsideTheShareOpensInBrowse() async {
        let store = makeStore(makeState { $0.selectedTab = .shared })
        await openShare(store)

        await store.send(.sharedBrowse(.navigateToDirectory(path: "personal/Docs", title: "Docs")))
        await store.receive(\.sharedBrowse.delegate) {
            $0.selectedTab = .browse
        }
        await store.receive(\.browse.navigateToDirectory) {
            $0.recentFolders = ["personal/Docs"]
            $0.browse.path[id: 1] = BrowseFeature.State(
                serverURL: serverURL, directoryPath: "personal/Docs", title: "Docs"
            )
        }
    }
}

struct ReceivedSharePathTests {
    @Test("A received file is the one item inside its share, named and typed by the file")
    func receivedFileItem() throws {
        let item = try #require(Fixture.received(isDirectory: false).receivedFileItem)
        #expect(item.id == "\(Fixture.shareRoot)/\(Fixture.fileName)")
        #expect(item.kind == "txt")
        #expect(Fixture.received().receivedFileItem == nil)
    }

    @Test(
        "Only paths inside share/<token> belong to a received share",
        arguments: [
            ("share/abc", "share/abc"),
            ("share/abc/Photos/2024", "share/abc"),
            ("share", nil),
            ("personal/share/abc", nil),
            ("", nil),
        ] as [(String, String?)]
    )
    func shareRoot(path: String, expected: String?) {
        #expect(ReceivedShareSpace.shareRoot(of: path) == expected)
    }
}

@Suite(.isolatedDependencies)
@MainActor
struct ReceivedShareInfoTests {
    @Test("Get Info on a folder inside a received share loads its details but never the owner's disk")
    func infoInsideAShareSkipsTheOwnersDisk() async {
        let folder = BrowseFixtures.folder("Sub", in: Fixture.shareRoot)
        let metadata = FileMetadata(
            path: folder.id,
            name: folder.name,
            kind: FileItem.directoryKind,
            size: 0,
            dateModified: MockDate.date,
            dateCreated: MockDate.date
        )
        let store = BrowseFixtures.store(BrowseFixtures.state(Fixture.shareRoot, items: [folder])) {
            $0.filesClient.fetchMetadata = { _, _ in metadata }
        }

        await store.send(.infoTapped(folder)) {
            $0.infoItem = folder
            $0.infoPhase = .loading
        }
        await store.receive(\.infoMetadataResponse) {
            $0.infoPhase = .loaded
            $0.infoMetadata = metadata
        }
    }
}
