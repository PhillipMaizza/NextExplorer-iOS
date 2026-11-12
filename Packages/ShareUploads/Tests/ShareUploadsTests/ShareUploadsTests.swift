import CoreModels
import Foundation
@testable import ShareUploads
import Testing
import UniformTypeIdentifiers
import TestUtils

@Suite("Share uploads")
struct ShareUploadsTests {
    private let credentials = SessionCredentials(
        serverBaseURL: URL(string: TestHost.serverURLString)!,
        authMode: .local,
        cookieName: TestSession.cookieName,
        cookieValue: TestSession.uploadCookieValue,
        cookieDomain: TestHost.server,
        cookiePath: "/",
        cookieIsSecure: true,
        expiresAt: nil,
        username: TestAccount.username
    )

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ShareUploadsTests-\(TestID.uuid().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Upload defaults are kept per account and forgotten on removal")
    func defaultsPerAccount() throws {
        let suite = "ShareUploadsTests-\(TestID.uuid().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let client = UploadDefaultsClient.live(defaults: defaults)

        client.save("a", UploadDefaults(folderPath: TestFolder.photos, shouldUploadWithoutAsking: true))
        client.save("b", UploadDefaults(folderPath: TestFolder.docs))

        #expect(client.load("a").directFolder == TestFolder.photos)
        #expect(client.load("b").directFolder == nil, "without Upload Without Asking it still asks")
        #expect(client.load("b").folderPath == TestFolder.docs)
        client.remove("a")
        #expect(client.load("a") == UploadDefaults())
        #expect(client.load("b").folderPath == TestFolder.docs)
    }

    @Test("A folder is never uploaded to without asking unless both settings are on")
    func directFolderNeedsBoth() {
        #expect(UploadDefaults(folderPath: nil, shouldUploadWithoutAsking: true).directFolder == nil)
        #expect(UploadDefaults(folderPath: "", shouldUploadWithoutAsking: true).directFolder == nil)
        #expect(UploadDefaults(folderPath: TestFolder.photos, shouldUploadWithoutAsking: false).directFolder == nil)
        #expect(UploadDefaults(folderPath: TestFolder.photos, shouldUploadWithoutAsking: true).directFolder == TestFolder.photos)
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
        #expect(SharedItemLoader.fileName(fileURL: named, suggestedName: ShareUploadsTestValue.imageBaseName, type: .heic) == ShareUploadsTestValue.heicName)
        let bare = URL(fileURLWithPath: "/tmp/7F2A1C")
        #expect(SharedItemLoader.fileName(fileURL: bare, suggestedName: ShareUploadsTestValue.imageBaseName, type: .heic) == "IMG_0042.heic")
        #expect(SharedItemLoader.fileName(fileURL: bare, suggestedName: nil, type: .quickTimeMovie) == "7F2A1C.mov")
        #expect(SharedItemLoader.fileName(fileURL: bare, suggestedName: ShareUploadsTestValue.reportName, type: .pdf) == ShareUploadsTestValue.reportName)
    }

    @Test("Staging writes the upload envelope with the destination, name and bytes, no cookie yet")
    func stagingWritesEnvelope() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent(ShareUploadsTestValue.sourcePhoto)
        try Data(Constants.photoBytes.utf8).write(to: source)
        let uploader = BackgroundUploader(root: root, notifier: UploadNotifier { _ in })

        var batch = try uploader.makeBatch(credentials: credentials, destination: TestPath.photos2026)
        let staged = try batch.envelope(for: source, fileName: Constants.numberedPhoto)
        batch.add(staged)
        try FileManager.default.removeItem(at: source)

        let envelope = try String(contentsOf: staged.envelopeURL, encoding: .utf8)
        #expect(envelope.contains(TestPath.photos2026))
        #expect(envelope.contains(Constants.numberedPhoto))
        #expect(envelope.contains(Constants.photoBytes))
        #expect(staged.request.url?.absoluteString == "https://files.example.com/api/upload")
        #expect(staged.request.httpMethod == "POST")
        #expect(staged.request.value(forHTTPHeaderField: ShareUploadsTestValue.cookieHeader) == nil)
        #expect(batch.count == 1)

        uploader.discard(batch)
        #expect(!FileManager.default.fileExists(atPath: staged.envelopeURL.path))
    }

    @Test("Signing an account out cancels its pending batches and keeps the others'")
    func cancelKeepsSignedInAccounts() throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let center = RecordingCenter()
        let uploader = BackgroundUploader(root: root, notifier: UploadNotifier { _ in }, notifications: center.center)
        func pendingBatch(for accountID: String) throws -> URL {
            let id = TestID.uuid().uuidString
            let directory = root.appendingPathComponent(id, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Manifest(
                accountID: accountID, destination: TestFolder.photos, fileNames: [TestFile.aPhoto], envelopes: [Constants.aEnvelope],
                contentTypes: ["multipart/form-data; boundary=B"], serverURL: credentials.serverBaseURL,
                startedAt: TestClock.reference
            ).save(in: directory)
            try Data("envelope".utf8).write(to: directory.appendingPathComponent(Constants.aEnvelope))
            return directory
        }
        let leaving = try pendingBatch(for: ShareUploadsTestValue.leavingAccount)
        let staying = try pendingBatch(for: ShareUploadsTestValue.stayingAccount)

        uploader.cancel(keepingAccounts: [ShareUploadsTestValue.stayingAccount])

        #expect(!FileManager.default.fileExists(atPath: leaving.path))
        #expect(FileManager.default.fileExists(atPath: staying.path))
        uploader.cancel(keepingAccounts: [])
        #expect(!FileManager.default.fileExists(atPath: staying.path), "the last sign out leaves nothing staged")
        #expect(center.removedIdentifiers == [[leaving.lastPathComponent], [staying.lastPathComponent]])
    }
}

private enum Constants {
    static let aEnvelope = "a.multipart"
    static let photoBytes = "photo bytes"
    static let numberedPhoto = "IMG_1.jpg"
}
