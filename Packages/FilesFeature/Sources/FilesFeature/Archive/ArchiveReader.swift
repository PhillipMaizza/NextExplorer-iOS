import Foundation
import Unrar
import ZIPFoundation

/// One entry inside a `.zip`/`.rar`, normalized across both underlying libraries' own
/// `Entry` types — `path` is the entry's full path within the archive (e.g. `"a/b/c.txt"`),
/// same shape whether it came from `ZIPFoundation` or `Unrar.swift`.
struct ArchiveEntry: Sendable {
    let path: String
    let isDirectory: Bool
    let size: UInt64
}

enum ArchiveReaderError: Error {
    case unsupportedFormat
    case entryNotFound
    case entryTooLarge
}

/// Keeps the archive open (`ZIPFoundation.Archive` holds a live file handle; `Unrar.Archive`
/// re-opens per call but this still avoids re-downloading) for the lifetime of
/// `ArchiveBrowserView`, so opening an entry for preview — including sibling asset lookups for
/// an in-archive HTML/Markdown render — never re-fetches the archive itself. `rarEntries` is a
/// cache, not part of the "source" concept — `Unrar.Archive.entries()` fully re-parses the
/// archive's header list on every call, so without this, previewing an HTML file with N
/// sibling assets inside a `.rar` would re-parse the whole archive N+1 times.
/// `@unchecked Sendable`: `ZIPFoundation.Archive` / `Unrar.Archive` aren't thread-safe and
/// `cachedRarEntries` is mutable, so every access to the underlying handles goes through
/// `lock` — `entries()`, `extract(_:to:)` and the `rarEntries()` cache are all serialized by
/// the type itself rather than by a caller-side gating convention.
final class ArchiveSource: @unchecked Sendable {
    let kind: Kind
    private let lock = NSLock()
    private var cachedRarEntries: [Unrar.Entry]?

    enum Kind {
        case zip(ZIPFoundation.Archive)
        case rar(Unrar.Archive)
    }

    init(_ kind: Kind) {
        self.kind = kind
    }

    func entries() throws -> [ArchiveEntry] {
        lock.lock()
        defer { lock.unlock() }
        switch kind {
        case let .zip(archive):
            return archive.map { entry in
                ArchiveEntry(path: entry.path, isDirectory: entry.type == .directory, size: entry.uncompressedSize)
            }
        case .rar:
            return try rarEntries().map { entry in
                ArchiveEntry(path: entry.fileName, isDirectory: entry.directory, size: entry.uncompressedSize)
            }
        }
    }

    /// Extracts a single entry, by its full in-archive path, to `destinationURL`. Both branches
    /// stream to disk rather than buffering the whole entry in memory, and both enforce a hard
    /// size ceiling (`ArchiveReader.guardExtraction` on the declared size, plus a running byte
    /// count on the actual stream) so a crafted archive whose header understates the inflated
    /// size still can't fill the device.
    func extract(_ entryPath: String, to destinationURL: URL) throws {
        lock.lock()
        defer { lock.unlock() }
        switch kind {
        case let .zip(archive):
            guard let entry = archive[entryPath] else { throw ArchiveReaderError.entryNotFound }
            try ArchiveReader.guardExtraction(uncompressedSize: entry.uncompressedSize, destination: destinationURL)
            guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
                throw ArchiveReaderError.entryNotFound
            }
            let fileHandle = try FileHandle(forWritingTo: destinationURL)
            defer { try? fileHandle.close() }
            var written: UInt64 = 0
            _ = try archive.extract(entry, bufferSize: 1024 * 1024, skipCRC32: true) { chunk in
                written += UInt64(chunk.count)
                guard written <= ArchiveReader.maxEntrySize else { throw ArchiveReaderError.entryTooLarge }
                fileHandle.write(chunk)
            }
        case let .rar(archive):
            guard let entry = try rarEntries().first(where: { $0.fileName == entryPath }) else {
                throw ArchiveReaderError.entryNotFound
            }
            try ArchiveReader.guardExtraction(uncompressedSize: entry.uncompressedSize, destination: destinationURL)
            guard FileManager.default.createFile(atPath: destinationURL.path, contents: nil) else {
                throw ArchiveReaderError.entryNotFound
            }
            let fileHandle = try FileHandle(forWritingTo: destinationURL)
            defer { try? fileHandle.close() }
            var written: UInt64 = 0
            var overflowed = false
            // `Unrar`'s handler can't throw, so once the running count passes the ceiling we stop
            // writing and report afterward — the decoder keeps running but nothing more hits disk.
            try archive.extract(entry) { chunk, _ in
                guard !overflowed else { return }
                written += UInt64(chunk.count)
                if written > ArchiveReader.maxEntrySize {
                    overflowed = true
                    return
                }
                fileHandle.write(chunk)
            }
            if overflowed {
                throw ArchiveReaderError.entryTooLarge
            }
        }
    }

    private func rarEntries() throws -> [Unrar.Entry] {
        guard case let .rar(archive) = kind else { return [] }
        if let cachedRarEntries {
            return cachedRarEntries
        }
        let entries = try archive.entries()
        cachedRarEntries = entries
        return entries
    }
}

/// Reads a downloaded archive's contents entirely on-device — there's no server endpoint for
/// this (`POST /api/files/zip/extract` only fully unpacks to disk), so this is the only way
/// to show what's inside without materializing every archive a user taps.
enum ArchiveReader {
    /// Hard ceiling on a single extracted entry. A crafted archive (a "zip bomb") can declare a
    /// tiny compressed size yet inflate to hundreds of gigabytes; without a cap the streaming
    /// writer would fill the device before the write ever failed.
    static let maxEntrySize: UInt64 = 2 * 1024 * 1024 * 1024

    static func open(fileURL: URL, kind: String) throws -> ArchiveSource {
        switch kind.lowercased() {
        case "zip": return try ArchiveSource(.zip(ZIPFoundation.Archive(url: fileURL, accessMode: .read)))
        case "rar": return try ArchiveSource(.rar(Unrar.Archive(fileURL: fileURL)))
        default: throw ArchiveReaderError.unsupportedFormat
        }
    }

    static func entries(from source: ArchiveSource) throws -> [ArchiveEntry] {
        try source.entries()
    }

    static func extract(_ entryPath: String, from source: ArchiveSource, to destinationURL: URL) throws {
        try source.extract(entryPath, to: destinationURL)
    }

    /// Rejects an extraction before it starts when the declared size exceeds the ceiling or the
    /// volume's available space, so an honest but huge entry never begins filling the disk.
    static func guardExtraction(uncompressedSize: UInt64, destination: URL) throws {
        guard uncompressedSize <= maxEntrySize else { throw ArchiveReaderError.entryTooLarge }
        if let available = availableCapacity(at: destination.deletingLastPathComponent()),
           uncompressedSize > available
        {
            throw ArchiveReaderError.entryTooLarge
        }
    }

    private static func availableCapacity(at url: URL) -> UInt64? {
        guard let capacity = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage else { return nil }
        return capacity >= 0 ? UInt64(capacity) : nil
    }
}
