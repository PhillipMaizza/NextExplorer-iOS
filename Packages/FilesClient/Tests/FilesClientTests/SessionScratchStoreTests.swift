@testable import FilesClient
import Foundation
import NetworkClient
import Testing

@Suite("SessionScratchStore")
struct SessionScratchStoreTests {
    @Test("Purging removes every scratch folder and stray download, and nothing else")
    func purgeRemovesScratchOnly() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("scratch-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let archive = root.appendingPathComponent(SessionScratchLocation.archiveBrowser).appendingPathComponent("Files_a.zip")
        let uploads = root.appendingPathComponent(SessionScratchLocation.pendingUploads)
        try fileManager.createDirectory(at: archive, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: uploads, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: archive.appendingPathComponent("entry.txt"))
        try Data("secret".utf8).write(to: uploads.appendingPathComponent("photo.jpg"))
        let strayDownload = root.appendingPathComponent("\(NetworkClient.downloadTemporaryFilePrefix)\(UUID().uuidString)")
        try Data("secret".utf8).write(to: strayDownload)
        let unrelated = root.appendingPathComponent("someone-else.tmp")
        try Data("keep".utf8).write(to: unrelated)
        let html = root.appendingPathComponent(SessionScratchLocation.htmlPreview).appendingPathComponent("doc")
        try fileManager.createDirectory(at: html, withIntermediateDirectories: true)
        try Data("secret".utf8).write(to: html.appendingPathComponent("index.html"))
        let envelope = root.appendingPathComponent("\(SessionScratchLocation.uploadEnvelopePrefix)x.multipart")
        try Data("secret".utf8).write(to: envelope)

        SessionScratchStore.live(temporaryDirectory: root).purge(.everything)

        #expect(!fileManager.fileExists(atPath: archive.deletingLastPathComponent().path))
        #expect(!fileManager.fileExists(atPath: uploads.path))
        #expect(!fileManager.fileExists(atPath: strayDownload.path))
        #expect(!fileManager.fileExists(atPath: html.deletingLastPathComponent().path))
        #expect(!fileManager.fileExists(atPath: envelope.path))
        #expect(fileManager.fileExists(atPath: unrelated.path))
    }

    @Test("A fresh sign in keeps uploads staging and downloads streaming, and clears the rest")
    func purgeKeepsPendingUploads() throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("scratch-keep-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let uploads = root.appendingPathComponent(SessionScratchLocation.pendingUploads)
        try fileManager.createDirectory(at: uploads, withIntermediateDirectories: true)
        try Data("shared in".utf8).write(to: uploads.appendingPathComponent("photo.jpg"))

        let inFlight = root.appendingPathComponent("\(NetworkClient.downloadTemporaryFilePrefix)thumb")
        try Data("streaming".utf8).write(to: inFlight)
        let html = root.appendingPathComponent(SessionScratchLocation.htmlPreview)
        try fileManager.createDirectory(at: html, withIntermediateDirectories: true)

        let envelope = root.appendingPathComponent("\(SessionScratchLocation.uploadEnvelopePrefix)live.multipart")
        try Data("uploading".utf8).write(to: envelope)

        SessionScratchStore.live(temporaryDirectory: root).purge(.keepingActiveTransfers)

        #expect(fileManager.fileExists(atPath: envelope.path))

        #expect(fileManager.fileExists(atPath: uploads.appendingPathComponent("photo.jpg").path))
        #expect(fileManager.fileExists(atPath: inFlight.path))
        #expect(!fileManager.fileExists(atPath: html.path))
    }

    @Test("Purging an empty temporary folder is harmless")
    func purgeWhenEmpty() {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scratch-empty-\(UUID().uuidString)")
        SessionScratchStore.live(temporaryDirectory: root).purge(.everything)
    }
}
