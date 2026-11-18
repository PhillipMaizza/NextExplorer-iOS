import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// The file an Offline tab row or tile draws its thumbnail for: what kind takes which path, and the
/// signature that keeps it in step with the copy kept on the device.
struct OfflinePinnedThumbnailTests {
    private enum Constants {
        static let keptSize: Int64 = 3_200_000
        static let usageSize: Int64 = 4_096
    }

    private let kept = OfflineCopyMetadata(dateModified: MockDate.date, size: Constants.keptSize)

    private func usage(_ path: String, isDirectory: Bool = false, copy: OfflineCopyMetadata? = nil)
        -> OfflinePinnedRootUsage
    {
        OfflinePinnedRootUsage(
            root: OfflinePinnedRoot(path: path, isDirectory: isDirectory),
            sizeBytes: Constants.usageSize,
            copy: copy
        )
    }

    @Test("A folder has no thumbnail file")
    func folderHasNone() {
        #expect(usage(TestFolder.photos, isDirectory: true).thumbnailFile == nil)
    }

    @Test("A kept file carries the copy's date and size, so its signature follows the kept copy")
    func keptCopySignature() throws {
        let file = try #require(usage(TestPath.photosPhoto, copy: kept).thumbnailFile)
        #expect(file.id == TestPath.photosPhoto)
        #expect(file.name == TestFile.aPhoto)
        #expect(file.path == TestFolder.photos)
        #expect(file.dateModified == MockDate.date)
        #expect(file.size == Constants.keptSize)
    }

    @Test("A file not downloaded yet still gets one, sized like its usage")
    func notDownloadedYet() throws {
        let file = try #require(usage(TestPath.photosPhoto).thumbnailFile)
        #expect(file.dateModified == .distantPast)
        #expect(file.size == Constants.usageSize)
    }

    @Test(
        "Pictures and videos take the thumbnail path, whatever the case of their extension",
        arguments: [TestFile.aPhoto, TestFile.cameraPhoto, TestFile.screenshot, TestFile.clip, TestFile.cameraClip]
    )
    func picturesAndVideosSupportThumbnails(name: String) throws {
        let file = try #require(usage("\(TestFolder.media)/\(name)", copy: kept).thumbnailFile)
        #expect(file.supportsThumbnail)
    }

    @Test("A PDF renders its first page instead of a thumbnail")
    func aPDFSkipsTheThumbnailPath() throws {
        let file = try #require(usage("\(TestFolder.docs)/\(TestFile.aPDF)", copy: kept).thumbnailFile)
        #expect(!file.supportsThumbnail)
        #expect(file.isPDF)
    }

    @Test("Any other file keeps its type icon")
    func otherFilesSkipTheThumbnailPath() throws {
        let file = try #require(usage("\(TestFolder.docs)/\(TestFile.archive)", copy: kept).thumbnailFile)
        #expect(!file.supportsThumbnail)
        #expect(!file.isPDF)
    }

    @Test("A file at the top level has an empty parent")
    func topLevelFile() throws {
        let file = try #require(usage(TestFile.aPhoto, copy: kept).thumbnailFile)
        #expect(file.path.isEmpty)
        #expect(file.id == TestFile.aPhoto)
    }
}
