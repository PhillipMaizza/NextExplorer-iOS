import CoreModels
import Foundation
@testable import ShareUploads
import Testing
import TestUtils
import UniformTypeIdentifiers

@Suite("Shared item staging")
struct SharedItemLoaderStagingTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("StagingTests-\(TestID.uuid().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func batch(in root: URL) throws -> UploadBatch {
        let uploader = BackgroundUploader(root: root, notifier: UploadNotifier { _ in }, defaults: .standard)
        return try uploader.makeBatch(credentials: Harness.credentials, destination: TestFolder.photos)
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
        #expect(SharedItemLoader.pairedMovieName(stillName: ShareUploadsTestValue.heicName, movieType: .quickTimeMovie) == Constants.lowercaseMovieName)
        #expect(SharedItemLoader.pairedMovieName(stillName: ShareUploadsTestValue.imageBaseName, movieType: .mpeg4Movie) == "IMG_0042.mp4")
        #expect(SharedItemLoader.pairedMovieName(stillName: "a.b.heic", movieType: .quickTimeMovie) == "a.b.mov")
    }

    // MARK: Staging with real providers

    @Test("A provider holding only a file URL uploads the file's bytes, not the URL text")
    func stagesTheRealFile() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent(ShareUploadsTestValue.reportName)
        try Data(Constants.fileBytes.utf8).write(to: source)
        let provider = NSItemProvider()
        provider.registerItem(forTypeIdentifier: UTType.fileURL.identifier) { completion, _, _ in
            completion?(source as NSURL, nil)
        }
        #expect(provider.registeredTypeIdentifiers == [UTType.fileURL.identifier])

        let staged = try await SharedItemLoader.stageAll(provider, in: batch(in: root))

        #expect(staged.map(\.fileName) == [ShareUploadsTestValue.reportName])
        let text = try envelopeText(#require(staged.first))
        #expect(text.contains(Constants.fileBytes))
        #expect(!text.contains("file:///"), "the URL's text is not what is uploaded")
    }

    private func fileURLProvider(_ url: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerItem(forTypeIdentifier: UTType.fileURL.identifier) { completion, _, _ in
            completion?(url as NSURL, nil)
        }
        return provider
    }

    private func envelopes(in batch: UploadBatch) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: batch.directory.path).filter { $0.hasSuffix(".multipart") }
    }

    @Test("A folder is reported as a folder, never silently skipped, and leaves no envelope")
    func folderIsAFailure() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let batch = try batch(in: root)

        await #expect(throws: ShareUploadError.isFolder) {
            try await SharedItemLoader.stageAll(fileURLProvider(root), in: batch)
        }
        #expect(try envelopes(in: batch).isEmpty)
    }

    @Test("A file URL with nothing behind it is a read failure, not a skipped item")
    func missingFileIsAFailure() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let batch = try batch(in: root)

        await #expect(throws: CocoaError(.fileNoSuchFile)) {
            try await SharedItemLoader.stageAll(fileURLProvider(root.appendingPathComponent("missing.txt")), in: batch)
        }
        #expect(try envelopes(in: batch).isEmpty)
    }

    // MARK: Progress and cancellation of a representation read

    /// What a fake provider handed the loader, so a test can drive the read by hand.
    private final class FakeRead: @unchecked Sendable {
        private let lock = NSLock()
        private var storedCompletion: (@Sendable (URL?, Bool, (any Error)?) -> Void)?
        let progress = Progress(totalUnitCount: 100)

        var completion: (@Sendable (URL?, Bool, (any Error)?) -> Void)? {
            get { lock.withLock { storedCompletion } }
            set { lock.withLock { storedCompletion = newValue } }
        }
    }

    @Test("A representation read reports the provider's progress in whole percents, then stages the file")
    func representationReportsProgress() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent(Constants.documentName)
        try Data(Constants.pdfBytes.utf8).write(to: source)
        let batch = try batch(in: root)
        let read = FakeRead()
        read.progress.completedUnitCount = 50
        let (fractions, report) = AsyncStream<Double>.makeStream()

        let staging = Task {
            try await SharedItemLoader.stageRepresentation(
                type: .pdf, suggestedName: nil, pairedWith: nil, in: batch,
                load: { _, completion in
                    read.completion = completion
                    return read.progress
                },
                onFraction: { report.yield($0) }
            )
        }
        var iterator = fractions.makeAsyncIterator()
        #expect(await iterator.next() == 0.5, "what was read before the observer existed is reported")
        read.progress.completedUnitCount = 75
        #expect(await iterator.next() == 0.75)
        let completion = try #require(read.completion)
        completion(source, false, nil)

        let file = try await staging.value
        #expect(file.fileName == Constants.documentName)
        #expect(try envelopeText(file).contains(Constants.pdfBytes))
    }

    @Test("Cancelling a representation read cancels the provider's progress and stages nothing, even if the copy still finishes")
    func representationCancellationStopsTheCopy() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Big.mov")
        try Data("movie".utf8).write(to: source)
        let batch = try batch(in: root)
        let read = FakeRead()
        let (loaded, signalLoaded) = AsyncStream<Void>.makeStream()

        let staging = Task {
            try await SharedItemLoader.stageRepresentation(
                type: .quickTimeMovie, suggestedName: nil, pairedWith: nil, in: batch,
                load: { _, completion in
                    read.completion = completion
                    signalLoaded.yield()
                    return read.progress
                },
                onFraction: { _ in }
            )
        }
        var iterator = loaded.makeAsyncIterator()
        await iterator.next()
        staging.cancel()

        await #expect(throws: CancellationError.self) { try await staging.value }
        #expect(read.progress.isCancelled, "the provider is told to stop copying")
        let completion = try #require(read.completion)
        completion(source, false, nil)
        #expect(try envelopes(in: batch).isEmpty, "a copy that finishes late is not staged")
    }

    @Test("Several files of one item share the item's progress")
    func overallFractionSpansTheFiles() {
        #expect(SharedItemLoader.overallFraction(position: 0, count: 2, fraction: 0.5) == 0.25)
        #expect(SharedItemLoader.overallFraction(position: 1, count: 2, fraction: 0.5) == 0.75)
        #expect(SharedItemLoader.overallFraction(position: 1, count: 2, fraction: 1) == 1)
        #expect(SharedItemLoader.overallFraction(position: 0, count: 0, fraction: 0.5) == 0)
    }

    @Test("A Live Photo provider stages the still and the paired movie under one name")
    func stagesLivePhotoPair() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let still = root.appendingPathComponent(ShareUploadsTestValue.heicName)
        let movie = root.appendingPathComponent("0F3A.mov")
        try Data(Constants.stillBytes.utf8).write(to: still)
        try Data(Constants.movieBytes.utf8).write(to: movie)
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

        #expect(staged.map(\.fileName) == [ShareUploadsTestValue.heicName, Constants.lowercaseMovieName])
        let texts = try staged.map(envelopeText)
        #expect(texts[0].contains(Constants.stillBytes))
        #expect(texts[1].contains(Constants.movieBytes))
    }

    @Test("A plain image provider stages just the one file")
    func plainImage() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let image = root.appendingPathComponent(TestFile.photo)
        try Data("jpeg bytes".utf8).write(to: image)
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.jpeg.identifier, fileOptions: [], visibility: .all) { completion in
            completion(image, false, nil)
            return nil
        }

        let staged = try await SharedItemLoader.stageAll(provider, in: batch(in: root))

        #expect(staged.map(\.fileName) == [TestFile.photo])
    }

    // MARK: iCloud placeholders

    @Test("A placeholder is downloaded before it is read, a local file is simply read")
    func downloadBeforeRead() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(Constants.textName)
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
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("x-\(TestID.uuid().uuidString)")
        let access = FileAccess(ubiquityStatus: { _ in .notDownloaded }, startDownload: { _ in throw CocoaError(.fileReadNoPermission) })
        #expect(throws: CocoaError.self) {
            try access.read(file) { $0 }
        }
    }

    @Test("A file the body cannot read surfaces the body's error")
    func bodyErrorPropagates() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent(Constants.textName)
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
        let file = root.appendingPathComponent(Constants.cloudName)
        try Data(Constants.cloudBytes.utf8).write(to: file)
        let downloads = LockedList()
        let access = FileAccess(ubiquityStatus: { _ in .notDownloaded }, startDownload: { downloads.add($0) })

        let staged = try await SharedItemLoader.stageFile(at: file, in: batch(in: root), access: access)

        #expect(downloads.items == [file])
        #expect(try envelopeText(staged).contains(Constants.cloudBytes))
        #expect(staged.fileName == Constants.cloudName)
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

private enum Constants {
    static let cloudBytes = "cloud bytes"
    static let cloudName = "Cloud.pdf"
    static let documentName = "Doc.pdf"
    static let fileBytes = "real file bytes"
    static let lowercaseMovieName = "IMG_0042.mov"
    static let movieBytes = "movie bytes"
    static let pdfBytes = "pdf bytes"
    static let stillBytes = "still bytes"
    static let textName = "doc.txt"
}
