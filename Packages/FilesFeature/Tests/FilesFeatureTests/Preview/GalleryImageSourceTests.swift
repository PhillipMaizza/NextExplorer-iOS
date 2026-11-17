import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

/// Where a gallery photo is read from, online and offline, with and without a copy on the device,
/// and what the preview already fetched for the file the gallery opens on.
struct GalleryImageSourceTests {
    private enum Constants {
        static let verifiedCopy = URL(fileURLWithPath: "/offline/verified/a.jpg")
        static let olderCopy = URL(fileURLWithPath: "/offline/older/a.jpg")
    }

    private let photo = BrowseFixtures.file(TestFile.aPhoto, in: TestFolder.photos)

    private func resolve(verified: URL? = nil, anyPinned: URL? = nil, isOnline: Bool) -> GalleryImageSource {
        GalleryImageSource.resolve(
            item: photo,
            serverURL: BrowseTestSupport.serverURL,
            verifiedCopy: verified,
            anyPinnedCopy: anyPinned,
            isOnline: isOnline
        )
    }

    @Test("A verified copy on the device is read locally, online or not")
    func verifiedCopyWins() {
        #expect(resolve(verified: Constants.verifiedCopy, anyPinned: Constants.olderCopy, isOnline: true)
            == .local(Constants.verifiedCopy))
        #expect(resolve(verified: Constants.verifiedCopy, isOnline: false) == .local(Constants.verifiedCopy))
    }

    @Test("Offline, a kept copy whose date or size moved on still opens instead of a blank page")
    func offlineServesAnyKeptCopy() {
        #expect(resolve(anyPinned: Constants.olderCopy, isOnline: false) == .local(Constants.olderCopy))
    }

    @Test("Offline with nothing kept, it goes to the preview file, never the stream")
    func offlineWithoutACopyDownloads() {
        #expect(resolve(isOnline: false) == .download)
    }

    @Test("Online, a copy that no longer matches is skipped for the fresh file, streamed")
    func onlineStreamsTheFreshFile() throws {
        let streamURL = try #require(FilesClient.previewURL(serverURL: BrowseTestSupport.serverURL, item: photo))
        #expect(resolve(anyPinned: Constants.olderCopy, isOnline: true) == .stream(streamURL))
        #expect(resolve(isOnline: true) == .stream(streamURL))
    }

    @Test("What the preview already fetched serves only the file it was fetched for")
    func thePreloadServesOnlyItsOwnFile() {
        let other = BrowseFixtures.file(TestFile.bPhoto, in: TestFolder.photos)
        let preload = GalleryPreload(itemID: photo.id, fileURL: Constants.verifiedCopy, text: TestFile.notes)

        #expect(preload.fileURL(for: photo) == Constants.verifiedCopy)
        #expect(preload.text(for: photo) == TestFile.notes)
        #expect(preload.fileURL(for: other) == nil)
        #expect(preload.text(for: other) == nil)
        #expect(GalleryPreload().fileURL(for: photo) == nil)
    }
}
