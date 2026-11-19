@testable import AppFeature
import CoreModels
import FilesClient
import Foundation
import Testing
import TestUtils

/// The UI tests' in memory server: each folder keeps its own files, so moves, renames and copies
/// land where they are sent and can be undone.
struct MockFileTreeTests {
    private enum Constants {
        static let docs = "Documents"
        static let reports = "Reports"
        static let notes = "notes.txt"
        static let photos = "Photos"
    }

    private func item(_ name: String, in path: String, isFolder: Bool = false) -> FileItem {
        FileItem(
            name: name,
            path: path,
            dateModified: MockDate.date,
            size: isFolder ? 0 : 1,
            kind: isFolder ? FileItem.directoryKind : "txt"
        )
    }

    private var seed: [String: [FileItem]] {
        [
            "": [item(Constants.photos, in: "", isFolder: true), item(Constants.notes, in: "")],
            Constants.docs: [
                item(Constants.photos, in: Constants.docs, isFolder: true),
                item(Constants.notes, in: Constants.docs),
            ],
            "\(Constants.docs)/\(Constants.photos)": [],
        ]
    }

    @Test
    func aSeededFolderListsItsOwnChildren() {
        let tree = MockFileTree(seed: seed)
        #expect(tree.list(Constants.docs).map(\.id) == ["Documents/Photos", "Documents/notes.txt"])
        #expect(tree.list("Documents/Photos").isEmpty)
    }

    @Test
    func aFolderTheSeedNeverNamedListsNothing() {
        #expect(MockFileTree(seed: seed).list("Elsewhere").isEmpty)
    }

    @Test
    func theBrowseWorldListsEveryFolderItNamesWithNoNameTwice() {
        let world = MockBrowseTree.seed(now: MockDate.date)
        for (path, items) in world {
            #expect(Set(items.map(\.name)).count == items.count, "\(path) repeats a name")
            for folder in items where folder.isDirectory {
                #expect(world[folder.id] != nil, "\(folder.id) is listed but has no listing")
            }
        }
    }

    @Test
    func onlyTheTeamLibraryIsReadOnly() {
        let library = UITestFixture.Folder.teamLibrary.path
        #expect(!MockBrowseTree.access(for: library).canDelete)
        #expect(!MockBrowseTree.access(for: "\(library)/Sub").canWrite)
        #expect(MockBrowseTree.access(for: Constants.docs).canDelete)
        #expect(MockBrowseTree.access(for: "\(library) Copy").canWrite)
    }

    @Test
    func searchWalksEveryFolderBelowItsScope() {
        let tree = MockFileTree(seed: seed)
        #expect(tree.search("notes", under: "", contentMatches: []).items.map(\.id) == [
            Constants.notes,
            "Documents/notes.txt",
        ])
        #expect(tree.search("notes", under: Constants.docs, contentMatches: []).items.map(\.id) == [
            "Documents/notes.txt",
        ])
    }

    @Test
    func aContentFixtureMatchesAnyPhraseAfterTheNameMatches() {
        let page = MockFileTree(seed: seed).search("photo", under: "", contentMatches: [Constants.notes])
        #expect(page.items.map(\.id) == ["Photos", "Documents/Photos", Constants.notes, "Documents/notes.txt"])
        #expect(page.items.map(\.matchKind) == [.name, .name, .contents, .contents])
    }

    @Test
    func aFolderTotalsEverythingBelowItAndAFileReportsItself() {
        let tree = MockFileTree(seed: seed)
        let root = tree.metadata(at: "").directory
        #expect(root?.totalSize == 2)
        #expect(root?.fileCount == 2)
        #expect(root?.dirCount == 2)
        #expect(tree.metadata(at: "Documents/notes.txt").directory == nil)
        #expect(tree.metadata(at: "Documents/notes.txt").size == 1)
    }

    @Test
    func aMadeFolderStartsEmptyAndAMoveIntoItLeavesTheSource() {
        let tree = MockFileTree(seed: seed)
        let reports = tree.createFolder(in: Constants.docs, named: Constants.reports)
        #expect(tree.list(reports.id).isEmpty)

        let notes = tree.list(Constants.docs)[1]
        let result = tree.transfer([notes], to: reports.id, operation: .move)

        #expect(result.items.map(\.to) == ["Documents/Reports/notes.txt"])
        #expect(!tree.list(Constants.docs).contains { $0.name == Constants.notes })
        #expect(tree.list(reports.id).map(\.name) == [Constants.notes])

        let moved = tree.list(reports.id)[0]
        _ = tree.transfer([moved], to: Constants.docs, operation: .move)
        #expect(tree.list(Constants.docs).contains { $0.id == "Documents/notes.txt" })
        #expect(tree.list(reports.id).isEmpty)
    }

    @Test
    func aMoveIntoAFolderNeverListedBeforeLandsThere() {
        let tree = MockFileTree(seed: seed)
        let notes = tree.list("")[1]
        _ = tree.transfer([notes], to: "Elsewhere", operation: .move)
        #expect(tree.list("Elsewhere").map(\.id) == ["Elsewhere/notes.txt"])
    }

    @Test
    func aTakenNameGetsAFreeOneAsTheServerKeepsBoth() {
        let tree = MockFileTree(seed: seed)
        let notes = tree.list("")[1]
        let result = tree.transfer([notes], to: Constants.docs, operation: .copy)

        #expect(result.items.map(\.to) == ["Documents/notes (2).txt"])
        #expect(tree.list("").contains { $0.id == Constants.notes })
    }

    @Test
    func renamingAFolderCarriesWhatIsInside() {
        let tree = MockFileTree(seed: seed)
        let reports = tree.createFolder(in: Constants.docs, named: Constants.reports)
        let notes = tree.list(Constants.docs)[1]
        _ = tree.transfer([notes], to: reports.id, operation: .move)

        let renamed = tree.rename(reports, to: "Archive")

        #expect(tree.list(renamed.id).map(\.id) == ["Documents/Archive/notes.txt"])
    }

    @Test
    func deletingAFolderForgetsWhatWasInside() {
        let tree = MockFileTree(seed: seed)
        let reports = tree.createFolder(in: Constants.docs, named: Constants.reports)
        _ = tree.delete([reports], permanent: true)
        #expect(!tree.list(Constants.docs).contains { $0.name == Constants.reports })
        #expect(tree.list(reports.id).isEmpty)
        #expect(tree.trashListing().items.isEmpty)
    }

    @Test
    func aTrashedFolderComesBackWithWhatWasInsideUnderAFreeName() {
        let tree = MockFileTree(seed: seed)
        let reports = tree.createFolder(in: Constants.docs, named: Constants.reports)
        let notes = tree.createFolder(in: reports.id, named: "Notes")

        let outcome = tree.delete([reports], permanent: false)
        #expect(outcome.trashedCount == 1)
        let trashed = tree.trashListing().items
        #expect(trashed.map(\.name) == [Constants.reports])
        _ = tree.createFolder(in: Constants.docs, named: Constants.reports)

        let result = tree.restore(trashed.map(\.id))

        #expect(result.items.first?.restoredName == "\(Constants.reports) (2)")
        #expect(tree.list("\(Constants.docs)/\(Constants.reports) (2)").map(\.name) == [notes.name])
        #expect(tree.trashListing().items.isEmpty)
    }

    @Test
    func emptyingTheTrashCountsWhatWent() {
        let tree = MockFileTree(seed: seed)
        let reports = tree.createFolder(in: Constants.docs, named: Constants.reports)
        _ = tree.delete([reports], permanent: false)

        #expect(tree.emptyTrash() == TrashEmptySummary(purged: 1))
        #expect(tree.purge(["missing"]).items.first?.status == .notFound)
    }
}
