import Foundation
import Testing

@testable import FilesFeature

/// Exercises `LocalDownloadStore.liveValue` against the real filesystem (the simulator's own
/// sandboxed Documents/Caches directories) — same spirit as `KeychainClientTests` hitting the
/// real Security framework rather than a mock, since the whole point is verifying actual
/// on-disk behavior.
@Suite
struct LocalDownloadStoreTests {
    private let store = LocalDownloadStore.liveValue
    /// A fake per-account scope so tests exercise the scoped `Downloads/<scope>/` folder and
    /// stay isolated from any real account subfolder on the simulator.
    private let scope = "test-\(UUID().uuidString)"

    private func makeSourceFile(named name: String, contents: String = "hello") throws -> URL {
        let sourceURL = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try contents.write(to: sourceURL, atomically: true, encoding: .utf8)
        return sourceURL
    }

    // MARK: Happy path

    @Test
    func saveWritesToTheDocumentsDownloadsSubfolder() throws {
        let fileName = "\(UUID().uuidString).txt"
        let sourceURL = try makeSourceFile(named: fileName)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let destinationURL = try store.save(sourceURL, fileName, .documents, scope)
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        #expect(destinationURL.pathComponents.suffix(3) == ["Downloads", scope, fileName])
        #expect(destinationURL.deletingLastPathComponent().lastPathComponent == scope)
        #expect(try String(contentsOf: destinationURL, encoding: .utf8) == "hello")
    }

    @Test
    func saveWritesToTheCachesDownloadsSubfolder() throws {
        let fileName = "\(UUID().uuidString).txt"
        let sourceURL = try makeSourceFile(named: fileName)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let destinationURL = try store.save(sourceURL, fileName, .cache, scope)
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        let cachesURL = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        #expect(destinationURL.path.hasPrefix(cachesURL.path))
        #expect(try String(contentsOf: destinationURL, encoding: .utf8) == "hello")
    }

    // MARK: Edge cases

    @Test
    func saveDisambiguatesAnExistingNameRatherThanOverwriting() throws {
        let fileName = "\(UUID().uuidString).txt"
        let firstSource = try makeSourceFile(named: fileName, contents: "first")
        let firstDestination = try store.save(firstSource, fileName, .documents, scope)
        try? FileManager.default.removeItem(at: firstSource)

        let secondSourceName = "\(UUID().uuidString).txt"
        let secondSource = try makeSourceFile(named: secondSourceName, contents: "second")
        defer {
            try? FileManager.default.removeItem(at: secondSource)
            try? FileManager.default.removeItem(at: firstDestination)
        }

        let secondDestination = try store.save(secondSource, fileName, .documents, scope)

        // Two different server files sharing a name must both survive locally.
        #expect(secondDestination != firstDestination)
        #expect(secondDestination.lastPathComponent.contains("(1)"))
        #expect(try String(contentsOf: firstDestination, encoding: .utf8) == "first")
        #expect(try String(contentsOf: secondDestination, encoding: .utf8) == "second")
        try? FileManager.default.removeItem(at: secondDestination)
    }

    @Test
    func saveThrowsWhenTheSourceFileDoesNotExist() {
        let missingSource = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")

        #expect(throws: Error.self) {
            try store.save(missingSource, "whatever.txt", .documents, scope)
        }
    }

    @Test
    func saveKeepsATraversingServerNameInsideTheDownloadsFolder() throws {
        let sourceName = "\(UUID().uuidString).txt"
        let sourceURL = try makeSourceFile(named: sourceName)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        // A hostile directory listing hands back `name` with `../` segments.
        let destinationURL = try store.save(sourceURL, "../../../../\(sourceName)", .documents, scope)
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        #expect(destinationURL.deletingLastPathComponent().lastPathComponent == scope)
        #expect(destinationURL.lastPathComponent == sourceName)
        #expect(!destinationURL.standardizedFileURL.path.contains(".."))
    }

    // MARK: rename

    @Test
    func renameChangesTheFileNameInPlace() throws {
        let original = "\(UUID().uuidString).txt"
        let sourceURL = try makeSourceFile(named: original)
        let saved = try store.save(sourceURL, original, .documents, scope)
        try? FileManager.default.removeItem(at: sourceURL)

        let renamed = try store.rename(saved, "renamed-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: renamed) }

        #expect(renamed.deletingLastPathComponent() == saved.deletingLastPathComponent())
        #expect(!FileManager.default.fileExists(atPath: saved.path))
        #expect(try String(contentsOf: renamed, encoding: .utf8) == "hello")
    }

    @Test
    func renameRejectsATypedNameThatCarriesAPath() throws {
        let original = "\(UUID().uuidString).txt"
        let sourceURL = try makeSourceFile(named: original)
        let saved = try store.save(sourceURL, original, .documents, scope)
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: saved)
        }

        #expect(throws: Error.self) {
            try store.rename(saved, "../../../../escaped.txt")
        }
        // The original file is untouched.
        #expect(FileManager.default.fileExists(atPath: saved.path))
    }

    // MARK: list

    @Test
    func listIncludesFilesSavedToBothDocumentsAndCache() throws {
        let documentsFileName = "\(UUID().uuidString).txt"
        let cacheFileName = "\(UUID().uuidString).txt"
        let documentsSource = try makeSourceFile(named: documentsFileName)
        let cacheSource = try makeSourceFile(named: cacheFileName)
        defer {
            try? FileManager.default.removeItem(at: documentsSource)
            try? FileManager.default.removeItem(at: cacheSource)
        }

        let documentsDestination = try store.save(documentsSource, documentsFileName, .documents, scope)
        let cacheDestination = try store.save(cacheSource, cacheFileName, .cache, scope)
        defer {
            try? FileManager.default.removeItem(at: documentsDestination)
            try? FileManager.default.removeItem(at: cacheDestination)
        }

        let downloads = try store.list(scope)

        #expect(downloads.contains { $0.fileName == documentsFileName && $0.location == .documents })
        #expect(downloads.contains { $0.fileName == cacheFileName && $0.location == .cache })
    }

    @Test
    func listReflectsTheActualFileSize() throws {
        let fileName = "\(UUID().uuidString).txt"
        let sourceURL = try makeSourceFile(named: fileName, contents: "hello")
        defer { try? FileManager.default.removeItem(at: sourceURL) }
        let destinationURL = try store.save(sourceURL, fileName, .documents, scope)
        defer { try? FileManager.default.removeItem(at: destinationURL) }

        let downloads = try store.list(scope)

        let saved = downloads.first { $0.fileName == fileName }
        #expect(saved?.size == 5)
    }

    // MARK: delete

    @Test
    func deleteRemovesTheFileFromDisk() throws {
        let fileName = "\(UUID().uuidString).txt"
        let sourceURL = try makeSourceFile(named: fileName)
        let destinationURL = try store.save(sourceURL, fileName, .documents, scope)
        try? FileManager.default.removeItem(at: sourceURL)

        try store.delete(destinationURL)

        #expect(!FileManager.default.fileExists(atPath: destinationURL.path))
    }

    @Test
    func deleteThrowsWhenTheFileDoesNotExist() {
        let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).txt")

        #expect(throws: Error.self) {
            try store.delete(missingURL)
        }
    }

    // MARK: per-account scoping

    @Test
    func listIsScopedPerAccountAndDoesNotLeakAcrossScopes() throws {
        let otherScope = "test-\(UUID().uuidString)"
        let fileName = "\(UUID().uuidString).txt"
        let source = try makeSourceFile(named: fileName)
        defer { try? FileManager.default.removeItem(at: source) }

        let destination = try store.save(source, fileName, .documents, scope)
        defer { try? FileManager.default.removeItem(at: destination) }

        #expect(try store.list(scope).contains { $0.fileName == fileName })
        #expect(try !store.list(otherScope).contains { $0.fileName == fileName })
    }

    @Test
    func listMigratesLegacyUnscopedDownloadsIntoTheCurrentScope() throws {
        let migrationScope = "test-\(UUID().uuidString)"
        let fileName = "\(UUID().uuidString).txt"
        let documentsURL = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let legacyRoot = documentsURL.appendingPathComponent("Downloads", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyRoot, withIntermediateDirectories: true)
        let legacyFile = legacyRoot.appendingPathComponent(fileName)
        try "legacy".write(to: legacyFile, atomically: true, encoding: .utf8)

        let downloads = try store.list(migrationScope)

        // The loose legacy file moved into the current account's scope subfolder.
        #expect(!FileManager.default.fileExists(atPath: legacyFile.path))
        let migrated = downloads.first { $0.fileName == fileName }
        #expect(migrated?.url.deletingLastPathComponent().lastPathComponent == migrationScope)
        if let migrated { try? FileManager.default.removeItem(at: migrated.url) }
    }
}
