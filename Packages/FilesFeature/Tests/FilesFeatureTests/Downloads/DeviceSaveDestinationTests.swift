@testable import FilesFeature
import Testing

struct DeviceSaveDestinationTests {
    @Test(arguments: ["jpg", "JPG", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "dng"])
    func pictureKindsGoToPhotos(kind: String) {
        #expect(DeviceSaveDestination.destination(forKind: kind) == .photos(isVideo: false))
    }

    @Test(arguments: ["mov", "MP4", "m4v"])
    func videoKindsGoToPhotosAsVideos(kind: String) {
        #expect(DeviceSaveDestination.destination(forKind: kind) == .photos(isVideo: true))
    }

    @Test(arguments: ["pdf", "txt", "zip", "svg", "psd", "webp", "mkv", "", "directory"])
    func everythingElseGoesThroughSaveToFiles(kind: String) {
        #expect(DeviceSaveDestination.destination(forKind: kind) == .files)
    }
}
