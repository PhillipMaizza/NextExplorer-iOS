import Foundation
@testable import ShareUploads
import Testing
import TestUtils

@Suite("Shared item renaming")
struct SharedItemRenameTests {
    private enum Constants {
        static let reportName = "report.pdf"
        static let quarterlyName = "Quarterly.pdf"
        static let quarterly = "Quarterly"
        static let paddedQuarterly = "  Quarterly "
        static let photoBase = "IMG_0042"
        static let archiveName = "backup.tar.gz"
        static let archiveBase = "backup.tar"
        static let archiveExtension = "gz"
        static let dotFile = ".env"
        static let bytes = "file bytes"
    }

    @Test("A typed name replaces the part before the extension, trimmed, and keeps the extension")
    func renameKeepsTheExtension() {
        #expect(SharedItemLoader.renamed(Constants.reportName, to: Constants.paddedQuarterly) == Constants
            .quarterlyName)
        #expect(SharedItemLoader.renamed(Constants.photoBase, to: Constants.quarterly) == Constants.quarterly)
    }

    @Test("No name, or a blank one, keeps the item's own name", arguments: [nil, "", "   "])
    func blankKeepsTheName(base: String?) {
        #expect(SharedItemLoader.renamed(Constants.reportName, to: base) == Constants.reportName)
    }

    @Test("The editable part is the suggested name without its last extension")
    func editableName() {
        let archive = SharedItemLoader.editableName(suggestedName: Constants.archiveName)
        #expect(archive?.base == Constants.archiveBase)
        #expect(archive?.fileExtension == Constants.archiveExtension)
        let photo = SharedItemLoader.editableName(suggestedName: Constants.photoBase)
        #expect(photo?.base == Constants.photoBase)
        #expect(photo?.fileExtension == "")
        let dotFile = SharedItemLoader.editableName(suggestedName: Constants.dotFile)
        #expect(dotFile?.base == Constants.dotFile)
        #expect(SharedItemLoader.editableName(suggestedName: nil) == nil)
        #expect(SharedItemLoader.editableName(suggestedName: "") == nil)
    }

    @Test("A file staged from its URL uploads under the new name")
    func stagedFileTakesTheNewName() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RenameTests-\(TestID.uuid().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(Constants.reportName)
        try Data(Constants.bytes.utf8).write(to: file)
        let uploader = BackgroundUploader(root: root, notifier: UploadNotifier { _ in }, defaults: .standard)
        let batch = try uploader.makeBatch(credentials: Harness.credentials, destination: TestFolder.photos)

        let staged = try await SharedItemLoader.stageFile(
            at: file,
            in: batch,
            access: FileAccess(ubiquityStatus: { _ in nil }, startDownload: { _ in }),
            renamedTo: Constants.quarterly
        )

        #expect(staged.fileName == Constants.quarterlyName)
    }
}
