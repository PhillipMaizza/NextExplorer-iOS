#if DEBUG
    import CoreModels
    import FilesClient
    import Foundation

    /// The UI tests' server side file tree, in memory for one app launch: every operation acts on
    /// the folder it names, as the real server does, so a move leaves one folder and lands in another
    /// and undoing it brings it back. It starts from a seeded tree; folders made during the test
    /// start empty.
    /// The lock keeps it safe across the client's `@Sendable` async closures.
    final class MockFileTree: @unchecked Sendable {
        private enum Constants {
            static let untitledFolder = "Untitled Folder"
            static let archiveKind = "zip"
            static let archiveExtension = "zip"
            static let trashIDPrefix = "trash-"
            static let day: TimeInterval = 86400
        }

        /// A deleted item and the folders below it, kept to put back as they were. `texts` holds
        /// what its text files read, by their path inside it ("" is the item itself).
        struct Trashed {
            let item: TrashItem
            let original: FileItem
            var subtree: [String: [FileItem]]
            var texts: [String: String] = [:]
        }

        private let lock = NSLock()
        /// Each folder's children, by folder path ("" is the root).
        private var folders: [String: [FileItem]]
        /// The trash, newest first, as the server's trash keeps it.
        private var trash: [Trashed] = []
        private var nextTrashID = 0

        init(seed: [String: [FileItem]], trash: [Trashed] = []) {
            folders = seed
            self.trash = trash
        }

        private func locked<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }

        func list(_ path: String) -> [FileItem] {
            locked { children(of: path) }
        }

        func createFolder(in path: String, named name: String) -> FileItem {
            locked {
                let folder = FileItem(
                    name: freeName(name.isEmpty ? Constants.untitledFolder : name, in: path),
                    path: path,
                    dateModified: Date(),
                    size: 0,
                    kind: FileItem.directoryKind
                )
                folders[path, default: []].append(folder)
                folders[folder.id] = []
                return folder
            }
        }

        func rename(_ item: FileItem, to newName: String) -> FileItem {
            locked {
                let renamed = Self.relocated(item, to: item.path, named: newName)
                replaceChild(item.id, in: item.path, with: renamed)
                rekeySubtree(from: item.id, to: renamed.id)
                return renamed
            }
        }

        /// Into the trash unless `permanent`, as a server with its trash on does.
        func delete(_ items: [FileItem], permanent: Bool) -> DeleteOutcome {
            locked {
                let entries = items.map { item in
                    let subtree = subtree(of: item.id)
                    removeChild(item.id, from: item.path)
                    dropSubtree(item.id)
                    guard !permanent else { return DeleteOutcome.Entry(path: item.id, status: .deleted) }
                    nextTrashID += 1
                    let deletedAt = Date()
                    let trashed = TrashItem(
                        id: Constants.trashIDPrefix + String(nextTrashID),
                        name: item.name,
                        isDirectory: item.isDirectory,
                        size: item.size,
                        deletedAt: deletedAt,
                        expiresAt: deletedAt
                            .addingTimeInterval(Double(UITestSupport.trashRetentionDays) * Constants.day),
                        location: TrashItem.Location(isPersonal: false, name: nil, parent: item.path),
                        openPath: item.path
                    )
                    trash.insert(Trashed(item: trashed, original: item, subtree: subtree), at: 0)
                    return DeleteOutcome.Entry(path: item.id, status: .trashed)
                }
                return DeleteOutcome(items: entries)
            }
        }

        func trashListing() -> TrashListing {
            locked { TrashListing(
                isEnabled: true,
                retentionDays: UITestSupport.trashRetentionDays,
                items: trash.map(\.item)
            ) }
        }

        /// What a deleted folder held at `path` inside it ("" is its top), or nil when it is gone.
        func trashEntries(_ itemID: TrashItem.ID, path: String) -> TrashFolderListing? {
            locked {
                guard let trashed = trash.first(where: { $0.item.id == itemID }) else { return nil }
                let key = path.isEmpty ? trashed.original.id : "\(trashed.original.id)/\(path)"
                let entries = (trashed.subtree[key] ?? []).map {
                    TrashEntry(name: $0.name, isDirectory: $0.isDirectory, size: $0.size, modifiedAt: $0.dateModified)
                }
                return TrashFolderListing(item: trashed.item, path: path, entries: entries)
            }
        }

        /// What a deleted text file reads, by its path inside the deleted item.
        func trashText(_ itemID: TrashItem.ID, path: String) -> TrashText? {
            locked {
                guard let trashed = trash.first(where: { $0.item.id == itemID }),
                      let content = trashed.texts[path]
                else { return nil }
                let name = path.split(separator: "/").last.map(String.init) ?? trashed.item.name
                return TrashText(name: name, content: content)
            }
        }

        /// Back where each came from, under a free name when its own is taken.
        func restore(_ ids: [TrashItem.ID]) -> TrashActionResult {
            locked {
                TrashActionResult(items: ids.map { id in
                    guard let index = trash.firstIndex(where: { $0.item.id == id }) else {
                        return .init(key: id, status: .notFound)
                    }
                    let trashed = trash.remove(at: index)
                    let parent = trashed.original.path
                    let name = freeName(trashed.original.name, in: parent)
                    let restored = Self.relocated(trashed.original, to: parent, named: name)
                    folders[parent, default: []].append(restored)
                    for (key, items) in trashed.subtree {
                        let newKey = restored.id + key.dropFirst(trashed.original.id.count)
                        folders[newKey] = items.map { Self.relocated($0, to: newKey, named: $0.name) }
                    }
                    return .init(
                        key: id,
                        status: .restored,
                        name: trashed.original.name,
                        restoredName: name,
                        path: parent,
                        isRenamed: name != trashed.original.name
                    )
                })
            }
        }

        /// Single entries from inside a deleted folder, back at their own path. Folders above them
        /// that are still deleted come back empty around them, so the restored entry has a home.
        func restoreEntries(_ itemID: TrashItem.ID, paths: [String]) -> TrashActionResult {
            locked {
                guard let index = trash.firstIndex(where: { $0.item.id == itemID }) else {
                    return TrashActionResult(items: paths.map { .init(key: $0, status: .notFound) })
                }
                var trashed = trash[index]
                let entries = paths.map { path -> TrashActionResult.Entry in
                    let full = "\(trashed.original.id)/\(path)"
                    let parent = (full as NSString).deletingLastPathComponent
                    guard let child = trashed.subtree[parent]?.first(where: { $0.id == full }) else {
                        return .init(key: path, status: .notFound)
                    }
                    addMissingFolders(parent, dated: trashed.original.dateModified)
                    let name = freeName(child.name, in: parent)
                    let restored = Self.relocated(child, to: parent, named: name)
                    folders[parent, default: []].append(restored)
                    for (key, items) in trashed.subtree where key == full || key.hasPrefix("\(full)/") {
                        let newKey = restored.id + key.dropFirst(full.count)
                        folders[newKey] = items.map { Self.relocated($0, to: newKey, named: $0.name) }
                        trashed.subtree[key] = nil
                    }
                    trashed.subtree[parent]?.removeAll { $0.id == full }
                    return .init(
                        key: path,
                        status: .restored,
                        name: child.name,
                        restoredName: name,
                        path: parent,
                        isRenamed: name != child.name
                    )
                }
                trash[index] = trashed
                return TrashActionResult(items: entries)
            }
        }

        private func addMissingFolders(_ path: String, dated date: Date) {
            var parent = ""
            for component in path.split(separator: "/").map(String.init) {
                let id = parent.isEmpty ? component : "\(parent)/\(component)"
                if !children(of: parent).contains(where: { $0.id == id }) {
                    folders[parent, default: []].append(FileItem(
                        name: component,
                        path: parent,
                        dateModified: date,
                        size: 0,
                        kind: FileItem.directoryKind
                    ))
                }
                if folders[id] == nil {
                    folders[id] = []
                }
                parent = id
            }
        }

        func purge(_ ids: [TrashItem.ID]) -> TrashActionResult {
            locked {
                TrashActionResult(items: ids.map { id in
                    let before = trash.count
                    trash.removeAll { $0.item.id == id }
                    return .init(key: id, status: trash.count < before ? .purged : .notFound)
                })
            }
        }

        func emptyTrash() -> TrashEmptySummary {
            locked {
                defer { trash = [] }
                return TrashEmptySummary(purged: trash.count)
            }
        }

        /// A move or a copy into `destination`. A name already taken there gets a free one, as the
        /// server keeps both.
        func transfer(_ items: [FileItem], to destination: String, operation: TransferOperation) -> TransferResult {
            locked {
                let entries = items.map { item in
                    let landed = Self.relocated(item, to: destination, named: freeName(item.name, in: destination))
                    folders[destination, default: []].append(landed)
                    if operation == .move {
                        removeChild(item.id, from: item.path)
                        rekeySubtree(from: item.id, to: landed.id)
                    } else {
                        copySubtree(from: item.id, to: landed.id)
                    }
                    return TransferResult.Entry(from: item.id, to: landed.id)
                }
                return TransferResult(destination: destination, items: entries)
            }
        }

        /// Everything below `scope`, as the server's search walks it: names holding the query first,
        /// then the files named in `contentMatches`, as if their contents held it.
        func search(_ query: String, under scope: String, contentMatches: Set<String>) -> SearchPage {
            locked {
                let found = items(under: scope)
                let named = found.filter { $0.name.localizedCaseInsensitiveContains(query) }
                let held = found.filter { !$0.isDirectory && contentMatches.contains($0.name) }
                let ordered = named + held.filter { !named.contains($0) }
                return SearchPage(items: ordered.map { item in
                    let isContentMatch = held.contains(item)
                    return SearchResultItem(
                        name: item.name,
                        path: item.path,
                        kind: SearchResultItem.kind(isDirectory: item.isDirectory),
                        matchLine: isContentMatch ? query : nil,
                        matchLineNumber: isContentMatch ? 1 : nil,
                        isNameMatch: named.contains(item),
                        isContentMatch: isContentMatch
                    )
                })
            }
        }

        /// A file's own facts, or a folder's totals over everything below it, as the info sheet and
        /// the offline estimate read them.
        func metadata(at path: String) -> FileMetadata {
            locked {
                let name = (path as NSString).lastPathComponent
                let item = folders[(path as NSString).deletingLastPathComponent]?.first { $0.name == name }
                let date = item?.dateModified ?? Date()
                if let item, !item.isDirectory {
                    return FileMetadata(
                        path: path,
                        name: name,
                        kind: item.kind,
                        size: item.size,
                        dateModified: date,
                        dateCreated: date
                    )
                }
                let below = items(under: path)
                let files = below.filter { !$0.isDirectory }
                return FileMetadata(
                    path: path,
                    name: name,
                    kind: FileItem.directoryKind,
                    size: 0,
                    dateModified: date,
                    dateCreated: date,
                    directory: FileMetadata.DirectorySummary(
                        totalSize: files.reduce(0) { $0 + $1.size },
                        fileCount: files.count,
                        dirCount: below.count - files.count,
                        isTruncated: false
                    )
                )
            }
        }

        func compress(_ item: FileItem) -> FileItem {
            locked {
                let archive = FileItem(
                    name: freeName("\(item.name).\(Constants.archiveExtension)", in: item.path),
                    path: item.path,
                    dateModified: Date(),
                    size: 0,
                    kind: Constants.archiveKind
                )
                folders[item.path, default: []].append(archive)
                return archive
            }
        }

        // MARK: Called with the lock held

        /// Everything listed below `scope`, in a stable order.
        private func items(under scope: String) -> [FileItem] {
            folders
                .filter { path, _ in scope.isEmpty || path == scope || path.hasPrefix("\(scope)/") }
                .sorted { $0.key < $1.key }
                .flatMap(\.value)
        }

        private func children(of path: String) -> [FileItem] {
            folders[path] ?? []
        }

        private func replaceChild(_ id: String, in path: String, with item: FileItem) {
            var listed = children(of: path)
            if let index = listed.firstIndex(where: { $0.id == id }) {
                listed[index] = item
            }
            folders[path] = listed
        }

        private func removeChild(_ id: String, from path: String) {
            folders[path] = children(of: path).filter { $0.id != id }
        }

        /// The folder at `old` and everything listed below it now live at `new`.
        private func rekeySubtree(from old: String, to new: String) {
            for (key, items) in subtree(of: old) {
                folders[key] = nil
                let newKey = new + key.dropFirst(old.count)
                folders[newKey] = items.map { Self.relocated($0, to: newKey, named: $0.name) }
            }
        }

        private func copySubtree(from old: String, to new: String) {
            for (key, items) in subtree(of: old) {
                let newKey = new + key.dropFirst(old.count)
                folders[newKey] = items.map { Self.relocated($0, to: newKey, named: $0.name) }
            }
        }

        private func dropSubtree(_ path: String) {
            for key in subtree(of: path).keys {
                folders[key] = nil
            }
        }

        private func subtree(of path: String) -> [String: [FileItem]] {
            folders.filter { $0.key == path || $0.key.hasPrefix(path + "/") }
        }

        /// `name`, or "name (2).ext", "name (3).ext"... when the folder already lists it.
        private func freeName(_ name: String, in path: String) -> String {
            let taken = Set(children(of: path).map(\.name))
            guard taken.contains(name) else { return name }
            let base = (name as NSString).deletingPathExtension
            let ext = (name as NSString).pathExtension
            var copy = 2
            while true {
                let candidate = ext.isEmpty ? "\(base) (\(copy))" : "\(base) (\(copy)).\(ext)"
                if !taken.contains(candidate) {
                    return candidate
                }
                copy += 1
            }
        }

        private static func relocated(_ item: FileItem, to path: String, named name: String) -> FileItem {
            FileItem(
                name: name,
                path: path,
                dateModified: item.dateModified,
                size: item.size,
                kind: item.kind,
                supportsThumbnail: item.supportsThumbnail
            )
        }
    }
#endif
