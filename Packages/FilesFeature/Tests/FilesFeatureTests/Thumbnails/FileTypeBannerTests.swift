import CoreModels
@testable import FilesFeature
import Testing

struct FileTypeBannerTests {
    @Test(arguments: ["pdf", "jar", "exe", "mp3", "zip", "pub"])
    func aShortExtensionGetsABanner(_ kind: String) {
        #expect(FileTypeIcon.hasBanner(forKind: kind))
    }

    @Test(arguments: [FileItem.unknownKind, "", "torrent", "xyz123", "tar.gz", "e\u{301}\u{301}\u{301}", "日本"])
    func anUnknownLongOrUnusualExtensionKeepsThePlainPage(_ kind: String) {
        #expect(!FileTypeIcon.hasBanner(forKind: kind))
    }
}
