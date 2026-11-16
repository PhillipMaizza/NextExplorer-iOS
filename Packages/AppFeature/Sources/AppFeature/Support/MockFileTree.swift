#if DEBUG
    import CoreModels
    import FilesClient
    import Foundation

    /// The UI tests' server side file tree, in memory for one app launch: every operation acts on
    /// the folder it names, as the real server does, so a move leaves one folder and lands in another
    /// and undoing it brings it back. The root and the folders down to `seededDepth` list the fixture
    /// `template` the first time they are opened, so the folders a test opens have the files it
    /// expects; deeper folders, and any made during the test, start empty.
    /// The lock keeps it safe across the client's `@Sendable` async closures.
    final class MockFileTree: @unchecked Sendable {
        private enum Constants {
            static let untitledFolder = "Untitled Folder"
            static let archiveKind = "zip"
            static let archiveExtension = "zip"
        }

        private let lock = NSLock()
        private let template: [FileItem]
        private let seededDepth: Int
        /// Each listed folder's children, by folder path ("" is the root).
        private var folders: [String: [FileItem]] = [:]

        init(template: [FileItem], seededDepth: Int) {
            self.template = template
            self.seededDepth = seededDepth
        }

        private func locked<T>(_ body: () -> T) -> T {
            lock.lock()
            defer { lock.unlock() }
            return body()
        }

        /// The folder's children, filled from the template the first time it is listed.
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
                folders[path, default: children(of: path)].append(folder)
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

        func delete(_ items: [FileItem]) {
            locked {
                for item in items {
                    removeChild(item.id, from: item.path)
                    dropSubtree(item.id)
                }
            }
        }

        /// A move or a copy into `destination`. A name already taken there gets a free one, as the
        /// server keeps both.
        func transfer(_ items: [FileItem], to destination: String, operation: TransferOperation) -> TransferResult {
            locked {
                let entries = items.map { item in
                    let landed = Self.relocated(item, to: destination, named: freeName(item.name, in: destination))
                    folders[destination, default: children(of: destination)].append(landed)
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

        func compress(_ item: FileItem) -> FileItem {
            locked {
                let archive = FileItem(
                    name: freeName("\(item.name).\(Constants.archiveExtension)", in: item.path),
                    path: item.path,
                    dateModified: Date(),
                    size: 0,
                    kind: Constants.archiveKind
                )
                folders[item.path, default: children(of: item.path)].append(archive)
                return archive
            }
        }

        // MARK: Called with the lock held

        private func children(of path: String) -> [FileItem] {
            if let listed = folders[path] {
                return listed
            }
            let depth = path.isEmpty ? 0 : path.split(separator: "/").count
            let fresh = depth > seededDepth ? [] : template.map { Self.relocated($0, to: path, named: $0.name) }
            folders[path] = fresh
            return fresh
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
