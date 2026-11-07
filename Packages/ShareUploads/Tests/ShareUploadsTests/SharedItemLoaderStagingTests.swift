import CoreModels
import Foundation
@testable import ShareUploads
import Testing
import UniformTypeIdentifiers

@Suite("Shared item staging")
struct SharedItemLoaderStagingTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("StagingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func batch(in root: URL) throws -> UploadBatch {
        let uploader = BackgroundUploader(root: root, notifier: UploadNotifier { _ in }, defaults: .standard)
        return try uploader.makeBatch(credentials: Harness.credentials, destination: "Photos")
    }

    private func envelopeText(_ file: UploadBatch.StagedFile) throws -> String {
        try String(contentsOf: file.envelopeURL, encoding: .isoLatin1)
    }

    // MARK: The decision

    @Test("A file URL is staged by reading the file, never as a representation of the URL's text")
    func fileURLMode() {
        #expect(SharedItemLoader.stagingMode(for: .fileURL) == .fileURL)
        #expect(UTType.fileURL.conforms(to: .data), "the reason a data check cannot tell it apart")
        #expect(SharedItemLoader.stagingMode(for: .heic) == .representation)
        #expect(SharedItemLoader.stagingMode(for: .pdf) == .representation)
        #expect(SharedItemLoader.stagingMode(for: .quickTimeMovie) == .representation)
    }

    @Test("A provider offering only a file URL stages through the file URL path")
    func fileURLOnlyProvider() {
        let types = SharedItemLoader.stagingTypes(registered: ["public.file-url"])
        #expect(types == [.fileURL])
        #expect(types.map(SharedItemLoader.stagingMode(for:)) == [.fileURL])
    }

    @Test("Items without a file stage nothing")
    func nothingToStage() {
        #expect(SharedItemLoader.stagingTypes(registered: ["public.plain-text"]).isEmpty)
        #expect(SharedItemLoader.stagingTypes(registered: ["public.url"]).isEmpty)
        #expect(SharedItemLoader.stagingTypes(registered: []).isEmpty)
    }

    @Test("A Live Photo stages its still and its paired movie, any other image just itself")
    func livePhotoTypes() {
        #expect(
            SharedItemLoader.stagingTypes(registered: ["com.apple.live-photo", "public.heic", "public.jpeg", "com.apple.quicktime-movie"])
                == [.heic, .quickTimeMovie]
        )
        #expect(SharedItemLoader.stagingTypes(registered: ["com.apple.live-photo", "public.heic"]) == [.heic], "no movie offered, nothing to pair")
        #expect(SharedItemLoader.stagingTypes(registered: ["com.apple.live-photo", "com.apple.quicktime-movie"]) == [.quickTimeMovie])
        #expect(SharedItemLoader.stagingTypes(registered: ["public.heic", "com.apple.quicktime-movie"]) == [.heic], "an image next to a video is not a pair")
    }

    @Test("The paired movie takes the still's name with the movie's extension")
    func pairedName() {
        #expect(SharedItemLoader.pairedMovieName(stillName: "IMG_0042.HEIC", movieType: .quickTimeMovie) == "IMG_0042.mov")
        #expect(SharedItemLoader.pairedMovieName(stillName: "IMG_0042", movieType: .mpeg4Movie) == "IMG_0042.mp4")
        #expect(SharedItemLoader.pairedMovieName(stillName: "a.b.heic", movieType: .quickTimeMovie) == "a.b.mov")
    }

    // MARK: Staging with real providers

    @Test("A provider holding only a file URL uploads the file's bytes, not the URL text")
    func stagesTheRealFile() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Report.pdf")
        try Data("real file bytes".utf8).write(to: source)
        let provider = NSItemProvider()
        provider.registerItem(forTypeIdentifier: UTType.fileURL.identifier) { completion, _, _ in
            completion?(source as NSURL, nil)
        }
        #expect(provider.registeredTypeIdentifiers == [UTType.fileURL.identifier])

        let staged = try await SharedItemLoader.stageAll(provider, in: batch(in: root))

        #expect(staged.map(\.fileName) == ["Report.pdf"])
        let text = try envelopeText(#require(staged.first))
        #expect(text.contains("real file bytes"))
        #expect(!text.contains("file:///"), "the URL's text is not what is uploaded")
    }

    @Test("The compatibility stage also reads the file behind a file URL")
    func singleStageReadsTheFile() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Notes.txt")
        try Data("note bytes".utf8).write(to: source)
        let provider = NSItemProvider()
        provider.registerItem(forTypeIdentifier: UTType.fileURL.identifier) { completion, _, _ in
            completion?(source as NSURL, nil)
        }

        let staged = try await SharedItemLoader.stage(provider, in: batch(in: root))

        #expect(try envelopeText(#require(staged)).contains("note bytes"))
    }

    @Test("A file URL that points at a folder or at nothing stages nothing")
    func folderAndMissing() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        for url in [root, root.appendingPathComponent("missing.txt")] {
            let provider = NSItemProvider()
            provider.registerItem(forTypeIdentifier: UTType.fileURL.identifier) { completion, _, _ in
                completion?(url as NSURL, nil)
            }
            let staged = try await SharedItemLoader.stageAll(provider, in: batch(in: root))
            #expect(staged.isEmpty)
        }
    }

    @Test("A Live Photo provider stages the still and the paired movie under one name")
    func stagesLivePhotoPair() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let still = root.appendingPathComponent("IMG_0042.HEIC")
        let movie = root.appendingPathComponent("0F3A.mov")
        try Data("still bytes".utf8).write(to: still)
        try Data("movie bytes".utf8).write(to: movie)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.heic.identifier, fileOptions: [], visibility: .all) { completion in
            completion(still, false, nil)
            return nil
        }
        provider.registerDataRepresentation(forTypeIdentifier: UTType.livePhoto.identifier, visibility: .all) { completion in
            completion(Data(), nil)
            return nil
        }
        provider.registerFileRepresentation(forTypeIdentifier: UTType.quickTimeMovie.identifier, fileOptions: [], visibility: .all) { completion in
            completion(movie, false, nil)
            return nil
        }

        let staged = try await SharedItemLoader.stageAll(provider, in: batch(in: root))

        #expect(staged.map(\.fileName) == ["IMG_0042.HEIC", "IMG_0042.mov"])
        let texts = try staged.map(envelopeText)
        #expect(texts[0].contains("still bytes"))
        #expect(texts[1].contains("movie bytes"))
    }

    @Test("A plain image provider stages just the one file")
    func plainImage() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent("photo.jpg")
        try Data("jpeg bytes".utf8).write(to: image)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { completion in
            completion(image, false, nil)
            return nil
        }

        let staged = try await SharedItemLoader.stageAll(provider, in: batch(in: root))

        #expect(staged.map(\.fileName) == ["photo.jpg"])
    }

    // MARK: iCloud placeholders

    @Test("Only a file iCloud has not downloaded needs a download")
    func downloadDecision() {
        #expect(FileAccess.needsDownload(.notDownloaded))
        #expect(!FileAccess.needsDownload(.current))
        #expect(!FileAccess.needsDownload(.downloaded))
        #expect(!FileAccess.needsDownload(nil), "a file outside iCloud has no status")
    }

    @Test("A placeholder is downloaded before it is read, a local file is simply read")
    func downloadBeforeRead() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("doc.txt")
        try Data("body".utf8).write(to: file)
        let downloads = LockedList()

        let placeholder = FileAccess(ubiquityStatus: { _ in .notDownloaded }, startDownload: { downloads.add($0) })
        let read = try placeholder.read(file) { try String(contentsOf: $0, encoding: .utf8) }
        #expect(read == "body")
        #expect(downloads.items == [file])

        let local = FileAccess(ubiquityStatus: { _ in .current }, startDownload: { downloads.add($0) })
        _ = try local.read(file) { $0 }
        let plain = FileAccess(ubiquityStatus: { _ in nil }, startDownload: { downloads.add($0) })
        _ = try plain.read(file) { $0 }
        #expect(downloads.items == [file], "no further download for files already here")
    }

    @Test("A failed download request stops the read and the error is passed on")
    func downloadFailure() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("x-\(UUID().uuidString)")
        let access = FileAccess(ubiquityStatus: { _ in .notDownloaded }, startDownload: { _ in throw CocoaError(.fileReadNoPermission) })
        #expect(throws: CocoaError.self) {
            try access.read(file) { $0 }
        }
    }

    @Test("A file the body cannot read surfaces the body's error")
    func bodyErrorPropagates() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("doc.txt")
        try Data("body".utf8).write(to: file)

        #expect(throws: ShareUploadError.insufficientSpace) {
            try FileAccess(ubiquityStatus: { _ in nil }, startDownload: { _ in }).read(file) { _ -> Int in
                throw ShareUploadError.insufficientSpace
            }
        }
    }

    @Test("Staging a file URL asks for the download first, then writes the envelope from the coordinated read")
    func stagingDownloadsPlaceholders() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Cloud.pdf")
        try Data("cloud bytes".utf8).write(to: file)
        let downloads = LockedList()
        let access = FileAccess(ubiquityStatus: { _ in .notDownloaded }, startDownload: { downloads.add($0) })

        let staged = try await SharedItemLoader.stageFile(at: file, in: batch(in: root), access: access)

        #expect(downloads.items == [file])
        #expect(try envelopeText(#require(staged)).contains("cloud bytes"))
        #expect(staged?.fileName == "Cloud.pdf")
    }
}

final class LockedList: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [URL] = []

    var items: [URL] {
        lock.withLock { stored }
    }

    func add(_ url: URL) {
        lock.withLock { stored.append(url) }
    }
}
