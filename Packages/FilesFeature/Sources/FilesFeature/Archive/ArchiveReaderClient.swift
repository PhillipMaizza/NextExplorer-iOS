import CoreModels
import Dependencies
import DependenciesMacros
import Foundation

@DependencyClient
struct ArchiveReaderClient: Sendable {
    var list: @Sendable (_ fileURL: URL, _ kind: String, _ inside: String) async throws -> ArchiveListing
    var extract: @Sendable (_ fileURL: URL, _ kind: String, _ entryPath: String, _ destination: URL) async throws
        -> Void
    var release: @Sendable (_ fileURL: URL) async -> Void
}

extension ArchiveReaderClient: DependencyKey {
    static var liveValue: ArchiveReaderClient {
        let cache = ArchiveSourceCache()
        return ArchiveReaderClient(
            list: { fileURL, kind, inside in
                try await ArchiveReaderClient.level(of: cache.entries(fileURL, kind: kind), inside: inside)
            },
            extract: { fileURL, kind, entryPath, destination in
                try await cache.extract(fileURL, kind: kind, entryPath: entryPath, to: destination)
            },
            release: { fileURL in
                await cache.release(fileURL)
            }
        )
    }

    static let testValue = ArchiveReaderClient()

    static func level(of entries: [ArchiveEntry], inside: String) -> ArchiveListing {
        let prefix = inside.isEmpty ? "" : inside + "/"
        var folders: [String: ArchiveListingEntry] = [:]
        var files: [ArchiveListingEntry] = []
        for entry in entries where prefix.isEmpty || entry.path.hasPrefix(prefix) {
            let components = entry.path.dropFirst(prefix.count).split(separator: "/")
            guard let first = components.first.map(String.init) else { continue }
            let path = prefix + first
            if components.count == 1, !entry.isDirectory {
                files.append(ArchiveListingEntry(path: path, name: first, isDirectory: false, size: Int64(entry.size)))
            } else if folders[first] == nil {
                folders[first] = ArchiveListingEntry(path: path, name: first, isDirectory: true, size: nil)
            }
        }
        let byName: (ArchiveListingEntry, ArchiveListingEntry) -> Bool = {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        return ArchiveListing(inside: inside, entries: folders.values.sorted(by: byName) + files.sorted(by: byName))
    }
}

extension DependencyValues {
    var archiveReader: ArchiveReaderClient {
        get { self[ArchiveReaderClient.self] }
        set { self[ArchiveReaderClient.self] = newValue }
    }
}

private actor ArchiveSourceCache {
    private var opened: [URL: (source: ArchiveSource, entries: [ArchiveEntry])] = [:]

    func entries(_ fileURL: URL, kind: String) throws -> [ArchiveEntry] {
        try open(fileURL, kind: kind).entries
    }

    func extract(_ fileURL: URL, kind: String, entryPath: String, to destination: URL) throws {
        let source = try open(fileURL, kind: kind).source
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? FileManager.default.removeItem(at: destination)
        try ArchiveReader.extract(entryPath, from: source, to: destination)
    }

    func release(_ fileURL: URL) {
        opened[fileURL] = nil
    }

    private func open(_ fileURL: URL, kind: String) throws -> (source: ArchiveSource, entries: [ArchiveEntry]) {
        if let cached = opened[fileURL] {
            return cached
        }
        let source = try ArchiveReader.open(fileURL: fileURL, kind: kind)
        let fresh = try (source: source, entries: ArchiveReader.entries(from: source))
        opened[fileURL] = fresh
        return fresh
    }
}
