@testable import CoreModels
import Foundation
import Testing

@Suite("FileItem decoding")
struct FileItemDecodingTests {
    @Test("decodes a full directory listing entry")
    func decodesFullEntry() throws {
        let json = #"""
        {"name": "Photos", "path": "Home", "dateModified": 1800000000, "size": 4096, "kind": "directory", "supportsThumbnail": true}
        """#
        let item = try JSONDecoder().decode(FileItem.self, from: Data(json.utf8))
        #expect(item.name == "Photos")
        #expect(item.isDirectory == true)
        #expect(item.supportsThumbnail == true)
    }

    @Test("edge case: missing supportsThumbnail defaults to false")
    func missingSupportsThumbnailDefaultsFalse() throws {
        let json = #"""
        {"name": "notes.txt", "path": "Home", "dateModified": 1800000000, "size": 12, "kind": "txt"}
        """#
        let item = try JSONDecoder().decode(FileItem.self, from: Data(json.utf8))
        #expect(item.supportsThumbnail == false)
        #expect(item.isDirectory == false)
    }

    @Test("edge case: id joins path and name when path is non-empty")
    func idJoinsPathAndName() {
        let item = FileItem(name: "file.txt", path: "Home/Docs", dateModified: Date(), size: 0, kind: "txt")
        #expect(item.id == "Home/Docs/file.txt")
    }

    @Test("edge case: id is just the name when path is empty (root level)")
    func idIsNameAtRoot() {
        let item = FileItem(name: "Volume", path: "", dateModified: Date(), size: 0, kind: "directory")
        #expect(item.id == "Volume")
    }

    @Test("happy path: common video and audio kinds are streamable")
    func commonVideoAndAudioKindsAreStreamable() {
        for kind in ["mp4", "mov", "webm", "mp3", "m4a", "MP4"] {
            let item = FileItem(name: "clip.\(kind)", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(item.isStreamableMedia, "expected \(kind) to be streamable")
        }
    }

    @Test("edge case: images, documents, and directories are not streamable")
    func nonMediaKindsAreNotStreamable() {
        for kind in ["jpg", "pdf", "txt", "directory"] {
            let item = FileItem(name: "file", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(!item.isStreamableMedia, "expected \(kind) not to be streamable")
        }
    }

    @Test("happy path: images, RAW photos, and PDFs preview via download")
    func imagesRawAndPDFPreviewViaDownload() {
        for kind in ["jpg", "png", "heic", "nef", "cr2", "pdf", "PDF"] {
            let item = FileItem(name: "file.\(kind)", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(item.isPreviewableViaDownload, "expected \(kind) to be previewable via download")
        }
    }

    @Test("edge case: video, audio, text, and directories are not previewable via download")
    func nonDownloadPreviewableKinds() {
        for kind in ["mp4", "mp3", "txt", "directory"] {
            let item = FileItem(name: "file", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(!item.isPreviewableViaDownload, "expected \(kind) not to be previewable via download")
        }
    }

    @Test("edge case: only RAW camera extensions report isRawImage, not regular images")
    func rawImageIsDistinctFromRegularImage() {
        let raw = FileItem(name: "photo.nef", path: "", dateModified: Date(), size: 0, kind: "nef")
        let jpeg = FileItem(name: "photo.jpg", path: "", dateModified: Date(), size: 0, kind: "jpg")
        #expect(raw.isRawImage)
        #expect(!jpeg.isRawImage)
        #expect(jpeg.isImage)
        #expect(!raw.isImage)
    }

    @Test("happy path: common archive kinds report isArchive")
    func commonArchiveKindsAreArchives() {
        for kind in ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz", "ZIP"] {
            let item = FileItem(name: "bundle.\(kind)", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(item.isArchive, "expected \(kind) to be an archive")
        }
    }

    @Test("edge case: images, documents, media, and directories are not archives")
    func nonArchiveKindsAreNotArchives() {
        for kind in ["jpg", "pdf", "txt", "mp4", "directory"] {
            let item = FileItem(name: "file", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(!item.isArchive, "expected \(kind) not to be an archive")
        }
    }

    @Test("happy path: media, images, PDFs, and ordinary text/code kinds are previewable")
    func previewableKinds() {
        for kind in ["mp4", "mp3", "jpg", "nef", "pdf", "txt", "md", "json", "swift"] {
            let item = FileItem(name: "file", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(item.isPreviewable, "expected \(kind) to be previewable")
        }
    }

    @Test("edge case: archives and known binary formats are not previewable")
    func nonPreviewableKinds() {
        for kind in ["zip", "exe", "dmg", "apk", "sqlite", "dll", "ttf", "psd"] {
            let item = FileItem(name: "file", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(!item.isPreviewable, "expected \(kind) not to be previewable")
        }
    }

    @Test("happy path: mp4/mov/m4v video and mp3/wav/aac/m4a/flac audio are natively playable")
    func nativelyPlayableStreamableKinds() {
        for kind in ["mp4", "mov", "m4v", "MP4", "mp3", "wav", "aac", "m4a", "flac"] {
            let item = FileItem(name: "clip.\(kind)", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(item.isNativelyPlayable, "expected \(kind) to be natively playable")
        }
    }

    @Test("edge case: containers/codecs AVFoundation can't decode report isNativelyPlayable false")
    func nonNativelyPlayableStreamableKinds() {
        for kind in ["webm", "mkv", "avi", "wmv", "flv", "mpg", "mpeg", "ogg", "opus", "wma", "jpg", "directory"] {
            let item = FileItem(name: "clip.\(kind)", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(!item.isNativelyPlayable, "expected \(kind) not to be natively playable")
        }
    }

    @Test("happy path: previewable kinds (native and VLC media, downloadable, plain text, browsable archives) are never flagged unsupported")
    func supportedKindsAreNotUnsupportedForPreview() {
        // Includes the VLC-only containers (mkv, webm, avi, ogg, wma): they play through
        // VLCPlayerView, so they are previewable and must never report unsupported.
        for kind in ["mp4", "mp3", "mkv", "webm", "avi", "ogg", "wma", "jpg", "nef", "pdf", "doc", "docx", "txt", "md", "zip", "rar"] {
            let item = FileItem(name: "file.\(kind)", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(!item.isUnsupportedForPreview, "expected \(kind) not to be unsupported")
        }
    }

    @Test("edge case: non-browsable archives and known binaries are unsupported")
    func unsupportedKindsAreFlaggedUnsupportedForPreview() {
        for kind in ["7z", "tar", "gz", "exe", "dmg", "ttf"] {
            let item = FileItem(name: "file.\(kind)", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(item.isUnsupportedForPreview, "expected \(kind) to be unsupported")
        }
    }

    @Test("edge case: directories are never unsupported (they're not previewed at all, but the flag shouldn't claim they are)")
    func directoryIsNotUnsupportedForPreview() {
        let item = FileItem(name: "Documents", path: "", dateModified: Date(), size: 0, kind: "directory")
        #expect(!item.isUnsupportedForPreview)
    }

    @Test("happy path: only zip and rar report isBrowsableArchive")
    func browsableArchiveKinds() {
        for kind in ["zip", "rar", "ZIP", "RAR"] {
            let item = FileItem(name: "bundle.\(kind)", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(item.isBrowsableArchive, "expected \(kind) to be a browsable archive")
        }
    }

    @Test("edge case: other archive formats are not browsable client-side")
    func nonBrowsableArchiveKinds() {
        for kind in ["7z", "tar", "gz", "bz2", "xz", "tgz", "jpg", "directory"] {
            let item = FileItem(name: "bundle.\(kind)", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(!item.isBrowsableArchive, "expected \(kind) not to be a browsable archive")
        }
    }

    @Test("happy path: office and rich document kinds report isOfficeDocument and are previewable via download")
    func officeDocumentKinds() {
        for kind in ["doc", "docx", "xls", "xlsx", "ppt", "pptx", "odt", "ods", "odp", "rtf", "DOCX", "PPTX", "RTF"] {
            let item = FileItem(name: "report.\(kind)", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(item.isOfficeDocument, "expected \(kind) to be an office document")
            #expect(item.isPreviewableViaDownload, "expected \(kind) to be previewable via download")
        }
    }

    @Test("edge case: plain text and other kinds are not office documents")
    func nonOfficeDocumentKinds() {
        for kind in ["txt", "pdf", "md", "csv", "directory"] {
            let item = FileItem(name: "file", path: "", dateModified: Date(), size: 0, kind: kind)
            #expect(!item.isOfficeDocument, "expected \(kind) not to be an office document")
        }
    }

    @Test("error path: missing required field fails to decode")
    func missingRequiredFieldThrows() {
        let json = #"{"name": "file.txt", "path": "Home"}"#
        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(FileItem.self, from: Data(json.utf8))
        }
    }

    @Test("round-trips through Codable")
    func codableRoundTrip() throws {
        let original = FileItem(
            name: "report.pdf",
            path: "Home/Docs",
            dateModified: Date(timeIntervalSince1970: 1800000000),
            size: 2048,
            kind: "pdf",
            supportsThumbnail: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(FileItem.self, from: data)
        #expect(decoded == original)
    }
}
