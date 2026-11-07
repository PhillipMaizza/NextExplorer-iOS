import CoreModels
import Foundation
@testable import ShareUploads
import Testing
import UniformTypeIdentifiers

@Suite("Share uploads")
struct ShareUploadsTests {
    private let credentials = SessionCredentials(
        serverBaseURL: URL(string: "https://files.example.com")!,
        authMode: .local,
        cookieName: "connect.sid",
        cookieValue: "secret",
        cookieDomain: "files.example.com",
        cookiePath: "/",
        cookieIsSecure: true,
        expiresAt: nil,
        username: "phillip"
    )

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShareUploadsTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Upload defaults are kept per account and forgotten on removal")
    func defaultsPerAccount() throws {
        let suite = "ShareUploadsTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = UploadDefaultsClient.live(defaults: defaults)

        client.save("a", UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true))
        client.save("b", UploadDefaults(folderPath: "Docs"))

        #expect(client.load("a").directFolder == "Photos")
        #expect(client.load("b").directFolder == nil, "without Upload Without Asking it still asks")
        #expect(client.load("b").folderPath == "Docs")
        client.remove("a")
        #expect(client.load("a") == UploadDefaults())
        #expect(client.load("b").folderPath == "Docs")
    }

    @Test("A folder is never uploaded to without asking unless both settings are on")
    func directFolderNeedsBoth() {
        #expect(UploadDefaults(folderPath: nil, shouldUploadWithoutAsking: true).directFolder == nil)
        #expect(UploadDefaults(folderPath: "", shouldUploadWithoutAsking: true).directFolder == nil)
        #expect(UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: false).directFolder == nil)
        #expect(UploadDefaults(folderPath: "Photos", shouldUploadWithoutAsking: true).directFolder == "Photos")
    }

    @Test("The original file type is asked for: HEIC before its JPEG copy, a video before a still")
    func preferredType() {
        #expect(SharedItemLoader.preferredType(registered: ["public.heic", "public.jpeg"]) == .heic)
        #expect(SharedItemLoader.preferredType(registered: ["com.apple.quicktime-movie", "public.jpeg"]) == .quickTimeMovie)
        #expect(SharedItemLoader.preferredType(registered: ["com.adobe.pdf"]) == .pdf)
        #expect(SharedItemLoader.preferredType(registered: ["public.url"]) == nil, "a link is no file")
        #expect(SharedItemLoader.preferredType(registered: ["public.plain-text"]) == nil)
        #expect(SharedItemLoader.preferredType(registered: ["public.file-url"]) == .fileURL)
    }

    @Test("Shared files keep their own name, or get the type's extension")
    func fileNames() {
        let named = URL(fileURLWithPath: "/tmp/IMG_0042.HEIC")
        #expect(SharedItemLoader.fileName(fileURL: named, suggestedName: "IMG_0042", type: .heic) == "IMG_0042.HEIC")
        let bare = URL(fileURLWithPath: "/tmp/7F2A1C")
        #expect(SharedItemLoader.fileName(fileURL: bare, suggestedName: "IMG_0042", type: .heic) == "IMG_0042.heic")
        #expect(SharedItemLoader.fileName(fileURL: bare, suggestedName: nil, type: .quickTimeMovie) == "7F2A1C.mov")
        #expect(SharedItemLoader.fileName(fileURL: bare, suggestedName: "Report.pdf", type: .pdf) == "Report.pdf")
    }

    @Test("Staging writes the upload envelope with the destination, name and bytes, no cookie yet")
    func stagingWritesEnvelope() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.jpg")
        try Data("photo bytes".utf8).write(to: source)
        let uploader = BackgroundUploader(root: root, notifier: UploadNotifier { _ in })

        var batch = try uploader.makeBatch(credentials: credentials, destination: "Photos/2026")
        let staged = try batch.envelope(for: source, fileName: "IMG_1.jpg")
        batch.add(staged)
        try FileManager.default.removeItem(at: source)

        let envelope = try String(contentsOf: staged.envelopeURL, encoding: .utf8)
        #expect(envelope.contains("Photos/2026"))
        #expect(envelope.contains("IMG_1.jpg"))
        #expect(envelope.contains("photo bytes"))
        #expect(staged.request.url?.absoluteString == "https://files.example.com/api/upload")
        #expect(staged.request.httpMethod == "POST")
        #expect(staged.request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(batch.count == 1)

        uploader.discard(batch)
        #expect(!FileManager.default.fileExists(atPath: staged.envelopeURL.path))
    }

    @Test("A batch is finished once every file has a result, whichever process recorded it")
    func manifestResults() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manifest = Manifest(
            accountID: credentials.accountID,
            destination: "Photos",
            fileNames: ["a.jpg", "b.jpg"],
            envelopes: ["1.multipart", "2.multipart"],
            serverURL: credentials.serverBaseURL
        )
        try manifest.save(in: directory)

        #expect(Manifest.load(from: directory) == manifest)
        #expect(Manifest.record(index: 1, didSucceed: false, in: directory) == [1: false])
        #expect(Manifest.record(index: 0, didSucceed: true, in: directory) == [0: true, 1: false])
    }

    @Test("Only this app's upload sessions are claimed on wake up")
    func ownsSession() {
        #expect(BackgroundUploader.ownsSession(BackgroundUploader.identifierPrefix + "abc"))
        #expect(!BackgroundUploader.ownsSession("com.other.app.session"))
    }

    @Test("Signing an account out cancels its pending batches and keeps the others'")
    func cancelKeepsSignedInAccounts() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let uploader = BackgroundUploader(root: root, notifier: UploadNotifier { _ in })
        func pendingBatch(for accountID: String) throws -> URL {
            let id = UUID().uuidString
            let directory = root.appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Manifest(accountID: accountID, destination: "Photos", fileNames: ["a.jpg"], envelopes: ["a.multipart"], serverURL: credentials.serverBaseURL)
                .save(in: directory)
            try Data("envelope".utf8).write(to: directory.appendingPathComponent("a.multipart"))
            return directory
        }
        let leaving = try pendingBatch(for: "left")
        let staying = try pendingBatch(for: "stays")

        uploader.cancel(keepingAccounts: ["stays"])

        #expect(!FileManager.default.fileExists(atPath: leaving.path))
        #expect(FileManager.default.fileExists(atPath: staying.path))
        uploader.cancel(keepingAccounts: [])
        #expect(!FileManager.default.fileExists(atPath: staying.path), "the last sign out leaves nothing staged")
    }

    @Test("An old batch staged but never started is cleaned up at launch")
    func unstartedBatchIsCleanedUp() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try makeUnstartedBatch(in: root)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-BackgroundUploader.staleAge - 60)],
            ofItemAtPath: directory.path
        )

        BackgroundUploader(root: root, notifier: UploadNotifier { _ in }).reconnectPending()

        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("A batch another process is still staging survives the launch cleanup")
    func recentUnstartedBatchIsKept() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let directory = try makeUnstartedBatch(in: root)

        BackgroundUploader(root: root, notifier: UploadNotifier { _ in }).reconnectPending()

        #expect(FileManager.default.fileExists(atPath: directory.path))
    }

    @Test("A folder that cannot be read counts as stale")
    func missingFolderIsStale() {
        #expect(BackgroundUploader.isStale(URL(fileURLWithPath: "/nonexistent/\(UUID().uuidString)")))
    }

    private func makeUnstartedBatch(in root: URL) throws -> URL {
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("half written".utf8).write(to: directory.appendingPathComponent("x.multipart"))
        return directory
    }
}
