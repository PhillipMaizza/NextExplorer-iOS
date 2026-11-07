import CoreModels
import FilesClient
import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    /// In app drag payload: which server item is being dragged. Declared in the app's
    /// Info.plist so it never leaves the process as anything the system would try to keep.
    static let nextExplorerItem = UTType(exportedAs: "com.phillipmaizza.nextexplorer.item")
}

/// Which server and account a drag started in. A drop only moves rows when it names the account
/// the receiving window is showing, so a same path row of another server or account is never moved.
struct DragOrigin: Codable, Equatable, Sendable {
    let serverURL: String
    let scope: String

    static func current(serverURL: URL, scope: String = CacheAccountScope.current) -> DragOrigin {
        DragOrigin(serverURL: serverURL.absoluteString, scope: scope)
    }
}

struct ServerItemReference: Codable, Transferable {
    let id: String
    /// Absent in a payload written before drags carried an identity, which a drop refuses.
    var origin: DragOrigin?
    /// The dragged row itself, so another Browse window, which does not list it, can move it.
    var item: FileItem?
    /// Every selected row when the dragged one is part of a multi selection.
    var batch: [FileItem]?

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .nextExplorerItem)
    }

    /// A drag of `item`: the whole selection travels along when the row is part of it.
    init(dragging item: FileItem, selection: [FileItem] = [], origin: DragOrigin? = nil) {
        id = item.id
        self.origin = origin
        self.item = item
        batch = selection.count > 1 && selection.contains { $0.id == item.id } ? selection : nil
    }

    init(id: String, item: FileItem? = nil, batch: [FileItem]? = nil, origin: DragOrigin? = nil) {
        self.id = id
        self.origin = origin
        self.item = item
        self.batch = batch
    }

    /// The rows this drag carries, without duplicates.
    var items: [FileItem] {
        let carried = batch ?? item.map { [$0] } ?? []
        var seen: Set<FileItem.ID> = []
        return carried.filter { seen.insert($0.id).inserted }
    }
}

/// A dragged row. Inside the app it is a reference (drop on a folder to move it); dragged out
/// a file becomes a file promise: the download only starts once the drop lands, and the copy
/// keeps its real name. Folders never export as a file.
struct DraggedServerItem: Transferable {
    let reference: ServerItemReference
    let fileName: String
    let isDirectory: Bool
    let fetch: @Sendable () async throws -> URL

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(exporting: \.reference)
        FileRepresentation(exportedContentType: .data) { item in
            try await SentTransferredFile(item.fetch())
        }
        .exportingCondition { !$0.isDirectory }
        .suggestedFileName { $0.fileName }
    }
}

extension DraggedServerItem {
    init(item: FileItem, selection: [FileItem] = [], serverURL: URL, filesClient: FilesClient) {
        self.init(
            reference: ServerItemReference(dragging: item, selection: selection, origin: .current(serverURL: serverURL)),
            fileName: item.name,
            isDirectory: item.isDirectory
        ) {
            try await filesClient.downloadRawFile(serverURL, item)
        }
    }
}

/// Builds a row's drag payload only when asked. `draggable` takes its payload as an escaping
/// autoclosure, and building one walks the selection, so a row must not build it while it renders.
struct DraggedServerItemBuilder {
    let item: FileItem
    let serverURL: URL
    let filesClient: FilesClient
    let selection: () -> [FileItem]

    func build() -> DraggedServerItem {
        DraggedServerItem(item: item, selection: selection(), serverURL: serverURL, filesClient: filesClient)
    }
}

/// What a list row, grid cell or the folder background takes on a touch device: rows of this
/// app (moved) or files from the Files app and Photos (uploaded).
enum BrowseDrop: Transferable {
    case items([FileItem], origin: DragOrigin?)
    case file(URL)

    static var transferRepresentation: some TransferRepresentation {
        ProxyRepresentation(importing: { (reference: ServerItemReference) in
            BrowseDrop.items(reference.items, origin: reference.origin)
        })
        FileRepresentation(importedContentType: .item) { received in
            try BrowseDrop.file(DroppedFileStaging.copy(received.file))
        }
    }
}

/// The system deletes a received file once the drop closure returns, so it is copied somewhere
/// the upload staging can still read it. Upload staging then makes its own copy and deletes this
/// one (`discardCopy`); a copy that never reaches staging is removed by the session purge and the
/// stale sweep.
enum DroppedFileStaging {
    static let directoryName = SessionScratchLocation.droppedFiles
    private static let pathSeparator = "/"

    static func directory(in temporaryDirectory: URL = FileManager.default.temporaryDirectory) -> URL {
        temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    static func copy(_ source: URL, fileManager: FileManager = .default) throws -> URL {
        let didAccess = source.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                source.stopAccessingSecurityScopedResource()
            }
        }
        let directory = directory(in: fileManager.temporaryDirectory)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(source.lastPathComponent)
        try fileManager.copyItem(at: source, to: destination)
        return destination
    }

    /// Deletes the drop copy at `url` with its folder. Anything outside the drop directory is left alone.
    static func discardCopy(at url: URL, temporaryDirectory: URL = FileManager.default.temporaryDirectory) {
        let root = directory(in: temporaryDirectory).standardizedFileURL.path
        let folder = url.deletingLastPathComponent().standardizedFileURL
        guard folder.path.hasPrefix(root + pathSeparator) else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}

/// A drop split by what the reducer does with each part.
struct BrowseDropPlan: Equatable {
    /// Rows already listed in the folder on screen: moved by id.
    var listedIDs: [FileItem.ID] = []
    /// Rows this folder does not list (another window): moved by value.
    var foreignItems: [FileItem] = []
    var fileURLs: [URL] = []

    var isEmpty: Bool {
        listedIDs.isEmpty && foreignItems.isEmpty && fileURLs.isEmpty
    }

    /// `destination` is the folder the drop lands in. Rows that are that folder, one of its
    /// ancestors or already inside it are dropped from the plan, and so are rows whose drag did not
    /// start in `receiver` (another server or account, or a payload with no identity).
    init(drops: [BrowseDrop], listed: [FileItem.ID], destination: String, receiver: DragOrigin) {
        let listedSet = Set(listed)
        var seen: Set<FileItem.ID> = []
        for drop in drops {
            switch drop {
            case let .items(items, origin) where origin == receiver:
                for item in items where Self.canMove(item, into: destination) && seen.insert(item.id).inserted {
                    if listedSet.contains(item.id) {
                        listedIDs.append(item.id)
                    } else {
                        foreignItems.append(item)
                    }
                }
            case let .file(url) where url.isFileURL:
                fileURLs.append(url)
            case .items, .file:
                break
            }
        }
    }

    static func canMove(_ item: FileItem, into destination: String) -> Bool {
        item.id != destination && item.path != destination && !destination.hasPrefix(item.id + "/")
    }
}
