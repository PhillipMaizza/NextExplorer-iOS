import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import TestUtils

extension DependencyValues {
    /// The folder answers with `items` and `access`. A listing of non-empty items starts an offline
    /// availability check whose answer arrives on its own, so tests that follow it with the favorites
    /// answer hold that behind `holdFavorites(_:)`.
    mutating func serveListing(_ items: [FileItem], access: FileAccess = BrowseTestSupport.readOnlyAccess) {
        filesClient.browse = { _, path in BrowseResult(items: items, access: access, path: path) }
    }

    /// The favorites answer empty once the test opens the gate, after it has received the offline
    /// availability check that the listing started, so the two arrive in a fixed order.
    mutating func holdFavorites(_ gate: AsyncGate) {
        filesClient.favorites = { _ in
            try await gate.wait()
            return []
        }
    }
}

/// Builders the `BrowseFeature` reducer tests share: items, state, and a store whose unlisted
/// dependencies fail the test when touched.
enum BrowseFixtures {
    /// Can write and delete but not share: what the transfer tests need from a folder.
    static let writableAccess = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true)

    /// The kind is the file extension unless given, which is how the server labels files.
    static func file(_ name: String, in path: String = "", kind: String? = nil, size: Int64 = 0, modified: Date = MockDate.date) -> FileItem {
        FileItem(name: name, path: path, dateModified: modified, size: size, kind: kind ?? (name as NSString).pathExtension)
    }

    static func folder(_ name: String, in path: String = "") -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: 0, kind: FileItem.directoryKind)
    }

    static func favorite(_ path: String, position: Int = 0) -> Favorite {
        Favorite(
            id: "\(position)", path: path, label: nil, icon: "folder", color: nil,
            position: position, createdAt: MockDate.date, updatedAt: MockDate.date
        )
    }

    /// What the server answers to a copy or move: each source lands in `destination` under its own
    /// name, or under `renamedTo` when the server numbered it, and `skipped` ones are reported unmoved.
    static func transferResult(
        _ sources: [FileItem],
        to destination: String,
        renamedTo: [String: String] = [:],
        skipping skipped: [FileItem] = []
    ) -> TransferResult {
        TransferResult(
            destination: destination,
            items: sources.map { .init(from: $0.id, to: "\(destination)/\(renamedTo[$0.name] ?? $0.name)") }
                + skipped.map { .init(from: $0.id, to: $0.id, skipped: true) }
        )
    }

    /// The transfer answer of a copy into the folder on screen, as the reducer applies it: the copies
    /// join the listing (unless `alreadyListed`, a name the folder held before) and are recorded for
    /// undo, and the listing waits for them to show up.
    @MainActor
    static func receiveCopyIntoOpenFolder(
        _ store: TestStoreOf<BrowseFeature>,
        listed: [FileItem],
        alreadyListed: [FileItem] = [],
        message: String,
        clearsClipboard: Bool
    ) async {
        let copies = alreadyListed + listed
        await store.receive(\.transferResponse.success) {
            $0.isPerformingFileAction = false
            $0.fileActionProgressMessage = nil
            $0.pendingTransferRetry = nil
            $0.transferSuccessMessage = message
            for item in listed {
                $0.items.append(item)
            }
            $0.$undoStack.withLock { $0.record(FileUndoEntry(.created(copies))) }
            $0.awaitedArrivalIDs = Set(copies.map(\.id))
            $0.arrivalChecksLeft = 3
            if clearsClipboard {
                $0.$clipboard.withLock { $0 = nil }
            }
        }
        await store.receive(.delegate(.directoryContentsChanged))
    }

    @MainActor
    static func state(
        _ path: String = "",
        title: String = "Browse",
        items: [FileItem] = [],
        access: FileAccess? = nil
    ) -> BrowseFeature.State {
        var state = BrowseFeature.State(serverURL: BrowseTestSupport.serverURL, directoryPath: path, title: title)
        state.items = IdentifiedArray(uniqueElements: items)
        state.access = access
        return state
    }

    /// A state that finished loading its listing, the starting point for anything that acts on rows.
    @MainActor
    static func loadedState(
        _ path: String = "",
        items: [FileItem] = [],
        access: FileAccess = BrowseTestSupport.fullAccess
    ) -> BrowseFeature.State {
        var state = state(path, items: items, access: access)
        state.phase = .loaded
        return state
    }

    @MainActor
    static func store(
        _ state: BrowseFeature.State? = nil,
        configure: (inout DependencyValues) -> Void = { _ in }
    ) -> TestStoreOf<BrowseFeature> {
        TestStore(initialState: state ?? self.state()) {
            BrowseFeature()
        } withDependencies: {
            $0.date = .constant(MockDate.date)
            configure(&$0)
        }
    }
}
