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
        let tree = MockFileTree(template: template)
        #expect(tree.list(Constants.docs).map(\.id) == ["Documents/Photos", "Documents/notes.txt"])
    }

    @Test
    func aMadeFolderStartsEmptyAndAMoveIntoItLeavesTheSource() {
        let tree = MockFileTree(template: template)
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
        let tree = MockFileTree(template: template)
        let notes = tree.list("")[1]
        let result = tree.transfer([notes], to: Constants.docs, operation: .copy)

        #expect(result.items.map(\.to) == ["Documents/notes (2).txt"])
        #expect(tree.list("").contains { $0.id == Constants.notes })
    }

    @Test
    func renamingAFolderCarriesWhatIsInside() {
        let tree = MockFileTree(template: template)
        let reports = tree.createFolder(in: Constants.docs, named: Constants.reports)
        let notes = tree.list(Constants.docs)[1]
        _ = tree.transfer([notes], to: reports.id, operation: .move)

        let renamed = tree.rename(reports, to: "Archive")

        #expect(tree.list(renamed.id).map(\.id) == ["Documents/Archive/notes.txt"])
    }

    @Test
    func deletingAFolderForgetsWhatWasInside() {
        let tree = MockFileTree(template: template)
        let reports = tree.createFolder(in: Constants.docs, named: Constants.reports)
        tree.delete([reports])
        // Listed again, a folder of that name is a fresh one from the template.
        #expect(!tree.list(Constants.docs).contains { $0.name == Constants.reports })
        #expect(tree.list(reports.id).count == template.count)
    }
}
