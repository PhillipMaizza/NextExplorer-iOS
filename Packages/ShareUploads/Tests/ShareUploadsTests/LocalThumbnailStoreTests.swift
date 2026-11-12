import CoreGraphics
import CoreModels
import FilesClient
import Foundation
import ImageIO
@testable import ShareUploads
import Testing
import TestUtils
import UniformTypeIdentifiers

/// The thumbnails seeded from a file shared into the app: kept per account, used only for the file
/// that was uploaded, dropped when stale, cleared at session boundaries.
@Suite("Upload thumbnails seeded from the local copy")
struct LocalThumbnailStoreTests {
    private enum Constants {
        static let photo = "Photos/2026/beach.png"
        static let otherAccount = "https://other.example.com|bob"
        static let imagePixels = 64
        static let pageSize = CGSize(width: 120, height: 160)
        static let halfHour: TimeInterval = 30 * 60
        static let twoHours: TimeInterval = 2 * 60 * 60
        static let eightDays: TimeInterval = 8 * 24 * 60 * 60
    }

    private let account = Harness.credentials.accountID

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("UploadThumbnails-\(TestID.uuid().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func store(in root: URL, now: Date = MockDate.date) -> LocalThumbnailStore {
        .onDisk(root: root, now: { now })
    }

    /// A small PNG on disk, and its byte size.
    private func png(in root: URL) throws -> (url: URL, size: Int64) {
        let side = Constants.imagePixels
        let context = try #require(CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let image = try #require(context.makeImage())
        let url = root.appendingPathComponent("beach.png")
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return try (url, Int64(#require(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize)))
    }

    private func pdf(in root: URL) throws -> URL {
        let url = root.appendingPathComponent("scan.pdf")
        var box = CGRect(origin: .zero, size: Constants.pageSize)
        let context = try #require(CGContext(url as CFURL, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 0.8, green: 0.1, blue: 0.1, alpha: 1))
        context.fill(box)
        context.endPDFPage()
        context.closePDF()
        return url
    }

    private func read(_ store: LocalThumbnailStore, scope: String, size: Int64, modified: Date) -> Data? {
        CacheAccountScope.withPinned(scope) { store.thumbnail(Constants.photo, size, modified) }
    }

    // MARK: Seed and read

    @Test("A seeded picture reads back as a JPEG for the uploaded file")
    func aSeedReadsBackForTheUploadedFile() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (file, size) = try png(in: root)
        let store = store(in: root)

        store.seed(file, .png, Constants.photo, account, MockDate.date)

        let jpeg = try #require(read(store, scope: account, size: size, modified: MockDate.date))
        #expect(ThumbnailRendering.image(from: jpeg, maxPixel: CGFloat(Constants.imagePixels)) != nil)
        #expect(store.totalSizeBytes() > 0)
    }

    @Test("A file of another size at the same path is not the uploaded one")
    func anotherSizeIsNotTheUploadedFile() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (file, size) = try png(in: root)
        let store = store(in: root)
        store.seed(file, .png, Constants.photo, account, MockDate.date)

        #expect(read(store, scope: account, size: size + 1, modified: MockDate.date) == nil)
        #expect(read(store, scope: account, size: size, modified: MockDate.date) == nil, "a mismatch drops the seed")
    }

    @Test("A file modified well before the upload started is an older file the server kept, not the upload")
    func anOlderFileIsNotTheUpload() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (file, size) = try png(in: root)
        let store = store(in: root)
        store.seed(file, .png, Constants.photo, account, MockDate.date)

        #expect(read(store, scope: account, size: size, modified: MockDate.date.addingTimeInterval(-Constants.twoHours)) == nil)
    }

    @Test("A server clock somewhat behind the phone still matches the upload")
    func aServerClockBehindStillMatches() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (file, size) = try png(in: root)
        let store = store(in: root)
        store.seed(file, .png, Constants.photo, account, MockDate.date)

        #expect(read(store, scope: account, size: size, modified: MockDate.date.addingTimeInterval(-Constants.halfHour)) != nil)
    }

    @Test("A seed older than a week is dropped")
    func aWeekOldSeedIsDropped() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (file, size) = try png(in: root)
        store(in: root).seed(file, .png, Constants.photo, account, MockDate.date)
        let later = store(in: root, now: MockDate.date.addingTimeInterval(Constants.eightDays))

        #expect(read(later, scope: account, size: size, modified: MockDate.date) == nil)
    }

    @Test("Removing the seed once the server's thumbnail is in leaves nothing")
    func removeDropsTheSeed() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (file, size) = try png(in: root)
        let store = store(in: root)
        store.seed(file, .png, Constants.photo, account, MockDate.date)

        CacheAccountScope.withPinned(account) { store.remove(Constants.photo) }

        #expect(read(store, scope: account, size: size, modified: MockDate.date) == nil)
    }

    // MARK: What gets seeded

    @Test("A PDF is seeded with its first page, other files are not seeded")
    func onlyPicturesAndPDFsAreSeeded() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = try pdf(in: root)
        let text = root.appendingPathComponent("notes.txt")
        try Data("notes".utf8).write(to: text)
        let store = store(in: root)

        store.seed(text, .plainText, Constants.photo, account, MockDate.date)
        #expect(store.totalSizeBytes() == 0)

        store.seed(pdf, .pdf, Constants.photo, account, MockDate.date)
        let size = try Int64(#require(try pdf.resourceValues(forKeys: [.fileSizeKey]).fileSize))
        #expect(read(store, scope: account, size: size, modified: MockDate.date) != nil)
    }

    @Test("A file's server path joins the folder and the name, the root being empty")
    func pathJoinsFolderAndName() {
        #expect(LocalThumbnailStore.path(of: "a.jpg", in: "") == "a.jpg")
        #expect(LocalThumbnailStore.path(of: "a.jpg", in: "Photos/2026/") == "Photos/2026/a.jpg")
        #expect(LocalThumbnailStore.path(of: "a.jpg", in: "/Photos") == "Photos/a.jpg")
    }

    // MARK: Accounts and session boundaries

    @Test("Another account never sees the seed, and clearing one account keeps the other's")
    func seedsAreKeptPerAccount() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (file, size) = try png(in: root)
        let store = store(in: root)
        store.seed(file, .png, Constants.photo, account, MockDate.date)
        store.seed(file, .png, Constants.photo, Constants.otherAccount, MockDate.date)

        store.clearScope(account)

        #expect(read(store, scope: account, size: size, modified: MockDate.date) == nil)
        #expect(read(store, scope: Constants.otherAccount, size: size, modified: MockDate.date) != nil)
    }

    @Test("Clearing everything at a session boundary drops every account's seeds")
    func clearAllDropsEverything() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (file, size) = try png(in: root)
        let store = store(in: root)
        store.seed(file, .png, Constants.photo, account, MockDate.date)
        store.seed(file, .png, Constants.photo, Constants.otherAccount, MockDate.date)

        store.clearAll()

        #expect(store.totalSizeBytes() == 0)
        #expect(read(store, scope: Constants.otherAccount, size: size, modified: MockDate.date) == nil)
    }

    @Test("Without a container (no App Group) every call does nothing")
    func withoutAContainerNothingHappens() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (file, size) = try png(in: root)
        let store = LocalThumbnailStore.onDisk(root: nil, now: { MockDate.date })

        store.seed(file, .png, Constants.photo, account, MockDate.date)

        #expect(read(store, scope: account, size: size, modified: MockDate.date) == nil)
        #expect(store.totalSizeBytes() == 0)
    }

    // MARK: Staging

    @Test("Staging a picture seeds its thumbnail at its server path, for the batch's account and start")
    func stagingSeedsTheThumbnail() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let (file, _) = try png(in: root)
        let seeds = SeedLog()
        let uploader = BackgroundUploader(root: root, notifier: UploadNotifier { _ in }, defaults: .standard, availableCapacity: { _ in nil })
        var batch = try uploader.makeBatch(credentials: Harness.credentials, destination: TestFolder.photos)
        batch.now = { MockDate.date }
        batch.thumbnailStore.seed = { _, type, path, scope, startedAt in
            seeds.append("\(type?.identifier ?? "")|\(path)|\(scope)|\(startedAt == MockDate.date)")
        }

        _ = try batch.envelope(for: file, fileName: "beach.png")

        #expect(seeds.entries == ["public.png|Photos/beach.png|\(Harness.credentials.accountID)|true"])
    }
}

/// The seeds a staging asked for, in order.
private final class SeedLog: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var entries: [String] {
        lock.withLock { recorded }
    }

    func append(_ entry: String) {
        lock.withLock { recorded.append(entry) }
    }
}
