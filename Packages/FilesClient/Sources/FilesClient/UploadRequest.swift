import CoreModels
import Foundation
import NetworkClient

/// `POST /api/upload` for one file, built so any session can send it: the in app upload and the
/// Share Extension's background session (which streams it from disk after the extension is gone).
public enum UploadRequest {
    /// Writes the multipart envelope to `envelopeURL` (the field order the server needs, then the
    /// file streamed in chunks) and returns the request that uploads it from that file. The caller
    /// adds the session cookie when its session doesn't (a background session keeps no cookies).
    public static func make(
        serverURL: URL,
        fileURL: URL,
        fileName: String,
        destination: String,
        envelopeURL: URL,
        boundary: String = "Boundary-\(UUID().uuidString)"
    ) throws -> URLRequest {
        try writeEnvelope(to: envelopeURL, boundary: boundary, fileURL: fileURL, fileName: fileName, destination: destination)
        var request = FilesService.makeRequest(url: serverURL.appendingPathComponent(APIPath.upload), method: .post)
        request.setValue(MIMEType.multipartFormData(boundary: boundary), forHTTPHeaderField: HTTPHeaderField.contentType)
        return request
    }

    /// The stored file the server echoes back, possibly renamed on a collision.
    public static func decodeResponse(_ data: Data, _ response: HTTPURLResponse) throws -> FileItem {
        try FilesService.validateReportingMessage(data, response)
        let uploaded: [FileItem]
        do {
            uploaded = try FilesService.makeDecoder().decode([FileItem].self, from: data)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
        guard let file = uploaded.first else {
            throw FilesClientError.decoding("Upload response was empty.")
        }
        return file
    }

    static func writeEnvelope(
        to url: URL, boundary: String, fileURL: URL, fileName: String, destination: String
    ) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        func writeField(_ name: String, _ value: String) throws {
            let part = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n"
            try handle.write(contentsOf: Data(part.utf8))
        }

        try writeField(MultipartField.uploadDestination, destination)
        try writeField(MultipartField.relativePath, fileName)

        // The server takes the stored name from the `relativePath` field, not this header, but
        // a raw `"` or CR/LF here would still break the multipart framing.
        let headerFileName = fileName
            .replacingOccurrences(of: "\"", with: "'")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
        let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"\(MultipartField.fileData)\"; filename=\"\(headerFileName)\"\r\nContent-Type: \(MIMEType.octetStream)\r\n\r\n"
        try handle.write(contentsOf: Data(header.utf8))

        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }

        try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
    }
}
