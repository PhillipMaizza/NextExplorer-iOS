@testable import FilesClient
import Foundation
import Testing
import TestUtils

@Suite("Upload envelope")
struct UploadRequestTests {
    private let boundary = "Boundary-TEST"

    private struct Parts {
        var destination: String
        var relativePath: String
        var header: String
        var body: Data
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("UploadRequestTests-\(TestID.name())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func envelope(fileName: String, destination: String, bytes: Data = Data("payload".utf8)) throws -> Data {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.bin")
        try bytes.write(to: source)
        let envelopeURL = directory.appendingPathComponent("envelope.multipart")
        try UploadRequest.writeEnvelope(to: envelopeURL, boundary: boundary, fileURL: source, fileName: fileName, destination: destination)
        return try Data(contentsOf: envelopeURL)
    }

    private func parse(_ data: Data) throws -> Parts {
        let text = try #require(String(data: data, encoding: .isoLatin1))
        let delimiter = "--\(boundary)"
        let pieces = text.components(separatedBy: delimiter)
        #expect(pieces.count == 5, "three parts and the closing marker, nothing forged")
        let destination = try #require(pieces.dropFirst().first)
        let path = try #require(pieces.dropFirst(2).first)
        let file = try #require(pieces.dropFirst(3).first)
        func value(_ piece: String) -> String {
            let afterHeaders = piece.components(separatedBy: "\r\n\r\n").dropFirst().joined(separator: "\r\n\r\n")
            return afterHeaders.hasSuffix("\r\n") ? String(afterHeaders.dropLast("\r\n".count)) : afterHeaders
        }
        let headerLine = file.components(separatedBy: "\r\n\r\n").first ?? ""
        return Parts(destination: value(destination), relativePath: value(path), header: headerLine, body: Data(value(file).utf8))
    }

    @Test("A plain name and destination are written as is")
    func plain() throws {
        let parts = try parse(envelope(fileName: "IMG_1.jpg", destination: "Photos/2026"))
        #expect(parts.destination == "Photos/2026")
        #expect(parts.relativePath == "IMG_1.jpg")
        #expect(parts.header.contains("filename=\"IMG_1.jpg\""))
    }

    @Test("CR and LF in the name, relative path and destination never end a line early")
    func newlinesAreFlattened() throws {
        let hostile = "a\r\nContent-Disposition: form-data; name=\"x\"\r\n\r\nforged"
        let data = try envelope(fileName: hostile, destination: "Photos\nSecret\r")
        let parts = try parse(data)
        #expect(!parts.destination.contains("\n"))
        #expect(!parts.destination.contains("\r"))
        #expect(!parts.relativePath.contains("\n"))
        #expect(!parts.relativePath.contains("\r"))
        #expect(!parts.header.replacingOccurrences(of: "\r\n", with: "|").contains("\n"))
        #expect(parts.destination == "Photos Secret ")
    }

    @Test("A quote cannot close the filename header early")
    func quoteIsReplacedInTheHeaderOnly() throws {
        let parts = try parse(envelope(fileName: "my \"best\" photo.jpg", destination: "Photos"))
        #expect(parts.header.contains("filename=\"my 'best' photo.jpg\""))
        #expect(parts.relativePath == "my \"best\" photo.jpg", "the stored name comes from the field, quotes intact")
    }

    @Test("NUL in any field is refused and nothing is written")
    func nulIsRefused() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("source.bin")
        try Data("x".utf8).write(to: source)
        let envelopeURL = directory.appendingPathComponent("envelope.multipart")

        for (name, destination) in [("a\0b.jpg", "Photos"), ("a.jpg", "Pho\0tos")] {
            #expect(throws: UploadRequest.EnvelopeError.self) {
                try UploadRequest.writeEnvelope(to: envelopeURL, boundary: boundary, fileURL: source, fileName: name, destination: destination)
            }
        }
        #expect(!FileManager.default.fileExists(atPath: envelopeURL.path))
    }

    @Test("Emoji, combining marks and very long names keep their bytes and the framing")
    func unicodeAndLength() throws {
        let decomposed = "Cafe\u{0301} 🙂 日本語.txt"
        let composed = "Caf\u{00E9} 🙂 日本語.txt"
        let long = String(repeating: "あ", count: 4000) + ".txt"
        for name in [decomposed, composed, long] {
            let data = try envelope(fileName: name, destination: "Docs")
            let text = try #require(String(data: data, encoding: .utf8))
            #expect(text.contains("name=\"relativePath\"\r\n\r\n\(name)\r\n"), "the name is not normalised or truncated")
            #expect(text.components(separatedBy: "--\(boundary)").count == 5)
        }
    }

    @Test("The file bytes are streamed between the header and the closing marker, whatever they contain")
    func bodyIsOpaque() throws {
        let bytes = Data("--\(boundary)\r\nnot a part".utf8) + Data([0, 1, 2, 255])
        let data = try envelope(fileName: "blob.bin", destination: "Docs", bytes: bytes)
        #expect(data.range(of: bytes) != nil)
        #expect(data.suffix("\r\n--\(boundary)--\r\n".utf8.count) == Data("\r\n--\(boundary)--\r\n".utf8))
    }
}
