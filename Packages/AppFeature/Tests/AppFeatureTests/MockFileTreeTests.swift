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

    private let template = [
        FileItem(name: Constants.photos, path: "", dateModified: MockDate.date, size: 0, kind: FileItem.directoryKind),
        FileItem(name: Constants.notes, path: "", dateModified: MockDate.date, size: 1, kind: "txt"),
    ]

    @Test
    func aFolderOpenedForTheFirstTimeListsTheTemplateAtItsOwnPath() {
        let tree = MockFileTree(template: template, seededDepth: 1)
        #expect(tree.list(Constants.docs).map(\.id) == ["Documents/Photos", "Documents/notes.txt"])
    }

    @Test
    func foldersBelowTheSeededDepthStartEmpty() {
        let tree = MockFileTree(template: template, seededDepth: 1)
        #expect(tree.list("Documents/Photos").isEmpty)
        #expect(MockFileTree(template: template, seededDepth: 0).list(Constants.docs).isEmpty)
    }

    @Test
    func aMadeFolderStartsEmptyAndAMoveIntoItLeavesTheSource() {
        let tree = MockFileTree(template: template, seededDepth: 1)
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
    func aTakenNameGetsAFreeOneAsTheServerKeepsBoth() {
        let tree = MockFileTree(template: template, seededDepth: 1)
        let notes = tree.list("")[1]
        let result = tree.transfer([notes], to: Constants.docs, operation: .copy)

        #expect(result.items.map(\.to) == ["Documents/notes (2).txt"])
        #expect(tree.list("").contains { $0.id == Constants.notes })
    }

    @Test
    func renamingAFolderCarriesWhatIsInside() {
        let tree = MockFileTree(template: template, seededDepth: 1)
        let reports = tree.createFolder(in: Constants.docs, named: Constants.reports)
        let notes = tree.list(Constants.docs)[1]
        _ = tree.transfer([notes], to: reports.id, operation: .move)

        let renamed = tree.rename(reports, to: "Archive")

        #expect(tree.list(renamed.id).map(\.id) == ["Documents/Archive/notes.txt"])
    }

    @Test
    func deletingAFolderForgetsWhatWasInside() {
        let tree = MockFileTree(template: template, seededDepth: 1)
        let reports = tree.createFolder(in: Constants.docs, named: Constants.reports)
        _ = tree.delete([reports], permanent: true)
        #expect(!tree.list(Constants.docs).contains { $0.name == Constants.reports })
        #expect(tree.list(reports.id).isEmpty)
        #expect(tree.trashListing().items.isEmpty)
    }

    @Test
    func aTrashedFolderComesBackWithWhatWasInsideUnderAFreeName() {
        let tree = MockFileTree(template: template, seededDepth: 1)
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
        let tree = MockFileTree(template: template, seededDepth: 1)
        let reports = tree.createFolder(in: Constants.docs, named: Constants.reports)
        _ = tree.delete([reports], permanent: false)

        #expect(tree.emptyTrash() == TrashEmptySummary(purged: 1))
        #expect(tree.purge(["missing"]).items.first?.status == .notFound)
    }
}
