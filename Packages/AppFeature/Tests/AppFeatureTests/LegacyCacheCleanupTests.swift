@testable import AppFeature
import FilesClient
import Foundation
import Testing

@Suite("Legacy cache cleanup")
struct LegacyCacheCleanupTests {
    private enum Fixture {
        static let account = "https://files.example.com|alice"
        static let scopedName = CacheAccountScope.scopedFileName("payload.json", scope: account)
        static let legacyName = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef.json"
        static let rootPrefix = "legacy-cleanup-"
        static let suitePrefix = "legacy-cleanup-defaults-"
        static let bytes = Data("x".utf8)
    }

    private struct Sandbox {
        let root: URL
        let applicationSupport: URL
        let caches: URL
        let defaults: UserDefaults
        let suite: String

        func entries() -> [(directory: URL, isFolder: Bool)] {
            let directories = [CacheLayout.directoryCacheName, CacheLayout.listCacheName].map {
                applicationSupport.appendingPathComponent($0, isDirectory: true)
            } + (CacheLayout.previewSlotNamespaces + CacheLayout.flatScopedDirectories).map {
                caches.appendingPathComponent(CacheLayout.previewCacheName, isDirectory: true)
                    .appendingPathComponent($0, isDirectory: true)
            }
            return directories.map { ($0, CacheLayout.previewSlotNamespaces.contains($0.lastPathComponent)) }
        }

        func seed(_ name: String) throws {
            for (directory, isFolder) in entries() {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let entry = directory.appendingPathComponent(name)
                if isFolder {
                    try FileManager.default.createDirectory(at: entry, withIntermediateDirectories: true)
                    try Fixture.bytes.write(to: entry.appendingPathComponent("file.bin"))
                } else {
                    try Fixture.bytes.write(to: entry)
                }
            }
        }

        func exists(_ name: String) -> [Bool] {
            entries().map { FileManager.default.fileExists(atPath: $0.directory.appendingPathComponent(name).path) }
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suite)
        }
    }

    private func makeSandbox() throws -> Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("\(Fixture.rootPrefix)\(UUID().uuidString)")
        let suite = "\(Fixture.suitePrefix)\(UUID().uuidString)"
        return try Sandbox(
            root: root,
            applicationSupport: root.appendingPathComponent("support"),
            caches: root.appendingPathComponent("caches"),
            defaults: #require(UserDefaults(suiteName: suite)),
            suite: suite
        )
    }

    private func run(_ sandbox: Sandbox) {
        LegacyCacheCleanup.run(defaults: sandbox.defaults, applicationSupport: sandbox.applicationSupport, caches: sandbox.caches)
    }

    @Test("entries without an account prefix are removed from every cache location and prefixed ones stay")
    func removesOnlyUnscopedEntries() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        try sandbox.seed(Fixture.legacyName)
        try sandbox.seed(Fixture.scopedName)

        run(sandbox)

        #expect(sandbox.exists(Fixture.legacyName).allSatisfy { !$0 })
        #expect(sandbox.exists(Fixture.scopedName).allSatisfy { $0 })
    }

    @Test("the cleanup runs once: entries that appear later are left alone")
    func runsOnlyOnce() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }
        try sandbox.seed(Fixture.legacyName)
        run(sandbox)

        try sandbox.seed(Fixture.legacyName)
        run(sandbox)

        #expect(sandbox.exists(Fixture.legacyName).allSatisfy { $0 })
    }

    @Test("missing cache directories are not an error and still mark the cleanup done")
    func nothingToClean() throws {
        let sandbox = try makeSandbox()
        defer { sandbox.cleanUp() }

        run(sandbox)
        try sandbox.seed(Fixture.legacyName)
        run(sandbox)

        #expect(sandbox.exists(Fixture.legacyName).allSatisfy { $0 })
    }

    @Test("the names the stores write count as account prefixed, and older unprefixed ones do not")
    func prefixRecognition() {
        let prefix = CacheAccountScope.namePrefix(for: Fixture.account)
        #expect(CacheAccountScope.hasAccountPrefix(Fixture.scopedName))
        #expect(!CacheAccountScope.hasAccountPrefix(Fixture.legacyName))
        #expect(!CacheAccountScope.hasAccountPrefix(String(prefix.replacingOccurrences(of: "a", with: "g")) + "x"))
        #expect(!CacheAccountScope.hasAccountPrefix(String(prefix.dropLast())))
        #expect(!CacheAccountScope.hasAccountPrefix(""))
    }
}
