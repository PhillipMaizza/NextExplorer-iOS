@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// `LegacyDownloadStore` over the real filesystem, each test in its own temporary folder: the
/// point is what actually lands on disk, which account can list it, and what is removed when.
struct LegacyDownloadStoreTests {
    private enum Constants {
        /// Account folders are named by `DownloadAccountScope.identifier`: 32 lowercase hex characters.
        static let scopeA = "0123456789abcdef0123456789abcdef"
        static let scopeB = "fedcba9876543210fedcba9876543210"
        static let accountA = "https://files.example.com|alice"
        static let accountB = "https://files.example.com|bob"
        static let contents = "hello"
        static let fileName = "report.pdf"
    }

    /// One temporary root per test: the private folder plus the two shared folders older
    /// versions saved into.
    private struct Sandbox {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(TestID.name(), isDirectory: true)
        var privateRoot: URL {
            root.appendingPathComponent("private", isDirectory: true)
        }

        var documents: URL {
            root.appendingPathComponent("Documents/Downloads", isDirectory: true)
        }

        var caches: URL {
            root.appendingPathComponent("Caches/Downloads", isDirectory: true)
        }

        var store: LegacyDownloadStore {
            .onDisk(SavedEarlierDisk(privateRoot: privateRoot, sharedRoots: [documents, caches]))
        }

        func source(_ name: String = Constants.fileName, contents: String = Constants.contents) throws -> URL {
            let folder = root.appendingPathComponent("source", isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        /// A file an older version left in a shared folder, at `folder` below `sharedRoot`.
        @discardableResult
        func sharedFile(_ name: String, in sharedRoot: URL, folder: String? = nil) throws -> URL {
            let directory = folder.map { sharedRoot.appendingPathComponent($0, isDirectory: true) } ?? sharedRoot
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(name)
            try Constants.contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        func exists(_ url: URL) -> Bool {
            FileManager.default.fileExists(atPath: url.path)
        }

        func cleanUp() {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: Save and list

    @Test("A saved file lands in the account's own private folder and is listed for that account")
    func saveAndListStayInTheAccountsFolder() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }

        let saved = try sandbox.store.save(sandbox.source(), Constants.fileName, Constants.scopeA)

        #expect(saved.deletingLastPathComponent() == sandbox.privateRoot.appendingPathComponent(Constants.scopeA))
        let listed = try sandbox.store.list(Constants.scopeA)
        #expect(listed.map(\.fileName) == [Constants.fileName])
        #expect(listed.map(\.size) == [5])
    }

    @Test("Another account never lists a file saved by the first")
    func anotherAccountListsNothing() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        _ = try sandbox.store.save(sandbox.source(), Constants.fileName, Constants.scopeA)

        #expect(try sandbox.store.list(Constants.scopeB).isEmpty)
    }

    @Test("Without an account nothing is listed and nothing is saved")
    func withoutAnAccountNothingIsListedNorSaved() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        _ = try sandbox.store.save(sandbox.source(), Constants.fileName, Constants.scopeA)

        #expect(try sandbox.store.list("").isEmpty)
        #expect(throws: (any Error).self) {
            try sandbox.store.save(sandbox.source(), Constants.fileName, "")
        }
    }

    @Test("A scope that is a path can neither save nor list outside the private folder")
    func aPathScopeIsRejected() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }

        #expect(throws: (any Error).self) {
            try sandbox.store.save(sandbox.source(), Constants.fileName, "../escape")
        }
        #expect(try sandbox.store.list("..").isEmpty)
    }

    @Test("Two files sharing a name both survive")
    func saveDisambiguatesASharedName() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }

        let first = try sandbox.store.save(sandbox.source(contents: "first"), Constants.fileName, Constants.scopeA)
        let second = try sandbox.store.save(sandbox.source(contents: "second"), Constants.fileName, Constants.scopeA)

        #expect(second.lastPathComponent == "report (1).pdf")
        #expect(try String(contentsOf: first, encoding: .utf8) == "first")
        #expect(try String(contentsOf: second, encoding: .utf8) == "second")
    }

    @Test("A server name with ../ stays inside the account's folder")
    func saveKeepsATraversingNameInside() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }

        let saved = try sandbox.store.save(sandbox.source(), "../../../\(Constants.fileName)", Constants.scopeA)

        #expect(saved.deletingLastPathComponent().lastPathComponent == Constants.scopeA)
        #expect(saved.lastPathComponent == Constants.fileName)
    }

    @Test("A folder inside an account's folder is never listed as a file")
    func foldersAreNotListed() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let nested = sandbox.privateRoot.appendingPathComponent("\(Constants.scopeA)/\(Constants.scopeB)")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        #expect(try sandbox.store.list(Constants.scopeA).isEmpty)
    }

    // MARK: Rename and delete

    @Test("Rename changes the name in place; a name carrying a path is refused")
    func renameStaysInPlace() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let saved = try sandbox.store.save(sandbox.source(), Constants.fileName, Constants.scopeA)

        #expect(throws: (any Error).self) { try sandbox.store.rename(saved, "../escaped.pdf") }
        let renamed = try sandbox.store.rename(saved, "renamed.pdf")

        #expect(renamed.deletingLastPathComponent() == saved.deletingLastPathComponent())
        #expect(!sandbox.exists(saved))
        #expect(sandbox.exists(renamed))
    }

    @Test("Delete removes the copy, and a missing copy throws")
    func deleteRemovesTheCopy() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let saved = try sandbox.store.save(sandbox.source(), Constants.fileName, Constants.scopeA)

        try sandbox.store.delete(saved)

        #expect(!sandbox.exists(saved))
        #expect(throws: (any Error).self) { try sandbox.store.delete(saved) }
    }

    // MARK: Moving out of the shared folders

    @Test("Each account's files move from both shared folders into its private folder")
    func ownedFilesMovePrivate() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.sharedFile(Constants.fileName, in: sandbox.documents, folder: Constants.scopeA)
        try sandbox.sharedFile("photo.jpg", in: sandbox.caches, folder: Constants.scopeA)
        try sandbox.sharedFile("notes.txt", in: sandbox.documents, folder: Constants.scopeB)

        sandbox.store.moveSharedFilesToPrivateStorage()

        #expect(try sandbox.store.list(Constants.scopeA).map(\.fileName).sorted() == ["photo.jpg", "report.pdf"])
        #expect(try sandbox.store.list(Constants.scopeB).map(\.fileName) == ["notes.txt"])
        // The Files app no longer shows anything.
        #expect(!sandbox.exists(sandbox.documents))
        #expect(!sandbox.exists(sandbox.caches))
    }

    @Test("Files with no owner are deleted, never given to an account")
    func unownedFilesAreDeleted() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let loose = try sandbox.sharedFile(Constants.fileName, in: sandbox.documents)
        let strayFolder = try sandbox.sharedFile("notes.txt", in: sandbox.documents, folder: "Not an account")

        sandbox.store.moveSharedFilesToPrivateStorage()

        #expect(!sandbox.exists(loose))
        #expect(!sandbox.exists(strayFolder))
        #expect(try sandbox.store.list(Constants.scopeA).isEmpty)
    }

    @Test("A name already in the private folder keeps both files")
    func movingKeepsBothOnAClash() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        _ = try sandbox.store.save(sandbox.source(), Constants.fileName, Constants.scopeA)
        try sandbox.sharedFile(Constants.fileName, in: sandbox.documents, folder: Constants.scopeA)

        sandbox.store.moveSharedFilesToPrivateStorage()

        #expect(try sandbox.store.list(Constants.scopeA).map(\.fileName).sorted() == ["report (1).pdf", "report.pdf"])
    }

    @Test("Running again with nothing left to move changes nothing")
    func movingTwiceIsANoOp() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        try sandbox.sharedFile(Constants.fileName, in: sandbox.documents, folder: Constants.scopeA)

        sandbox.store.moveSharedFilesToPrivateStorage()
        sandbox.store.moveSharedFilesToPrivateStorage()

        #expect(try sandbox.store.list(Constants.scopeA).map(\.fileName) == [Constants.fileName])
    }

    // MARK: Removal with the account

    @Test("Removing an account removes its files and only its files")
    func removeAccountRemovesItsFiles() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.recordOwner(Constants.accountA, Constants.scopeA)
        sandbox.store.recordOwner(Constants.accountB, Constants.scopeB)
        _ = try sandbox.store.save(sandbox.source(), Constants.fileName, Constants.scopeA)
        _ = try sandbox.store.save(sandbox.source(), Constants.fileName, Constants.scopeB)

        sandbox.store.removeAccount(Constants.accountA)

        #expect(try sandbox.store.list(Constants.scopeA).isEmpty)
        #expect(try sandbox.store.list(Constants.scopeB).map(\.fileName) == [Constants.fileName])
    }

    @Test("Removing an account a second time, or one never recorded, removes nothing else")
    func removeUnknownAccountIsSafe() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.recordOwner(Constants.accountA, Constants.scopeA)
        _ = try sandbox.store.save(sandbox.source(), Constants.fileName, Constants.scopeA)

        sandbox.store.removeAccount(Constants.accountB)

        #expect(try sandbox.store.list(Constants.scopeA).map(\.fileName) == [Constants.fileName])
    }

    @Test("Signing everyone out removes every account's files")
    func removeAllRemovesEverything() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        sandbox.store.recordOwner(Constants.accountA, Constants.scopeA)
        _ = try sandbox.store.save(sandbox.source(), Constants.fileName, Constants.scopeA)
        _ = try sandbox.store.save(sandbox.source(), Constants.fileName, Constants.scopeB)

        sandbox.store.removeAll()

        #expect(try sandbox.store.list(Constants.scopeA).isEmpty)
        #expect(try sandbox.store.list(Constants.scopeB).isEmpty)
        #expect(!sandbox.exists(sandbox.privateRoot))
    }
}
