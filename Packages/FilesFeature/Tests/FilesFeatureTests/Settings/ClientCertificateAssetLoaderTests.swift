@testable import FilesFeature
import Foundation
import Testing

@Suite("ClientCertificateAssetLoader")
struct ClientCertificateAssetLoaderTests {
    @Test("Ranges ask for exactly what AVPlayer requested")
    func ranges() {
        #expect(ClientCertificateAssetLoader.rangeHeader(offset: 0, length: 2, toEnd: false) == "bytes=0-1")
        #expect(ClientCertificateAssetLoader.rangeHeader(offset: 1000, length: 500, toEnd: false) == "bytes=1000-1499")
        #expect(ClientCertificateAssetLoader.rangeHeader(offset: 1000, length: 500, toEnd: true) == "bytes=1000-")
    }

    @Test("The total length comes from Content-Range, else the body length")
    func totalLength() throws {
        let url = URL(string: "https://files.example.com/api/preview")!
        let partial = try #require(HTTPURLResponse(url: url, statusCode: 206, httpVersion: nil, headerFields: [
            "Content-Range": "bytes 0-1/52428800", "Content-Length": "2",
        ]))
        #expect(ClientCertificateAssetLoader.totalLength(of: partial) == 52_428_800)
        let full = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Length": "1234"]
        ))
        #expect(ClientCertificateAssetLoader.totalLength(of: full) == 1234)
        let unknown = try #require(HTTPURLResponse(url: url, statusCode: 206, httpVersion: nil, headerFields: [
            "Content-Range": "bytes 0-1/*", "Content-Length": "2",
        ]))
        #expect(ClientCertificateAssetLoader.totalLength(of: unknown) == nil)
    }

    @Test("A generic MIME type falls back to the file extension")
    func contentType() {
        #expect(ClientCertificateAssetLoader
            .contentType(mimeType: "video/mp4", fileExtension: "bin") == "public.mpeg-4")
        #expect(ClientCertificateAssetLoader
            .contentType(mimeType: "application/octet-stream", fileExtension: "mov") == "com.apple.quicktime-movie")
        #expect(ClientCertificateAssetLoader.contentType(mimeType: nil, fileExtension: "mp3") == "public.mp3")
    }

    @Test("Only https URLs are rewritten to the loader scheme")
    func scheme() {
        let loader = ClientCertificateAssetLoader(
            remoteURL: URL(string: "https://files.example.com/api/preview?path=a.mp4")!, cookies: [],
            fileExtension: "mp4"
        )
        #expect(loader?.asset.url.scheme == ClientCertificateAssetLoader.scheme)
        #expect(loader?.asset.url.query == "path=a.mp4")
        loader?.invalidate()
        #expect(ClientCertificateAssetLoader(
            remoteURL: URL(string: "http://files.example.com/a.mp4")!,
            cookies: [],
            fileExtension: "mp4"
        ) == nil)
    }
}
