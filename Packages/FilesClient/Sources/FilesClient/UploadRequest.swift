import CoreModels
import Foundation
import NetworkClient

/// `POST /api/upload` for one file, built so any session can send it: the in app upload and the
/// Share Extension's background session (which streams it from disk after the extension is gone).
public enum UploadRequest {
    public enum EnvelopeError: Error, Equatable {
        /// A NUL byte in a field would truncate it on the server.
        case invalidField(String)
    }

    private enum Constants {
        static let chunkSizeBytes = 1_048_576
        static let boundaryPrefix = "Boundary-"
        static let lineBreak = "\r\n"
        static let boundaryMarker = "--"
        static let space = " "
        static let nulScalar: Unicode.Scalar = "\0"
        static let carriageReturn = "\r"
        static let lineFeed = "\n"
        static let doubleQuote = "\""
        static let singleQuote = "'"
        static let emptyResponseMessage = "Upload response was empty."
        static let dispositionPrefix = "Content-Disposition: form-data; name="
        static let filenameAttribute = "; filename="
        static let contentTypePrefix = "Content-Type: "
    }

    private static func quoted(_ value: String) -> String {
        Constants.doubleQuote + value + Constants.doubleQuote
    }

    private static func partHeader(boundary: String, name: String, fileName: String? = nil) -> String {
        let lineBreak = Constants.lineBreak
        var header = Constants.boundaryMarker + boundary + lineBreak + Constants.dispositionPrefix + quoted(name)
        if let fileName {
            header += Constants.filenameAttribute + quoted(fileName) + lineBreak + Constants
                .contentTypePrefix + MIMEType.octetStream
        }
        return header + lineBreak + lineBreak
    }

    /// Writes the multipart envelope to `envelopeURL` (the field order the server needs, then the
    /// file streamed in chunks) and returns the request that uploads it from that file. The caller
    /// adds the session cookie when its session doesn't (a background session keeps no cookies).
    public static func make(
        serverURL: URL,
        fileURL: URL,
        fileName: String,
        destination: String,
        envelopeURL: URL,
        boundary: String? = nil
    ) throws -> URLRequest {
        let boundary = boundary ?? Constants.boundaryPrefix + UUID().uuidString
        try writeEnvelope(
            to: envelopeURL,
            boundary: boundary,
            fileURL: fileURL,
            fileName: fileName,
            destination: destination
        )
        return request(serverURL: serverURL, contentType: MIMEType.multipartFormData(boundary: boundary))
    }

    /// The upload request for an envelope written earlier, given the content type header that carries
    /// its boundary. A failed upload is retried from the stored envelope with this.
    public static func request(serverURL: URL, contentType: String) -> URLRequest {
        var request = FilesService.makeRequest(url: serverURL.appendingPathComponent(APIPath.upload), method: .post)
        request.setValue(contentType, forHTTPHeaderField: HTTPHeaderField.contentType)
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
            throw FilesClientError.decoding(Constants.emptyResponseMessage)
        }
        return file
    }

    static func writeEnvelope(
        to url: URL, boundary: String, fileURL: URL, fileName: String, destination: String
    ) throws {
        let destinationValue = try singleLine(destination)
        let nameValue = try singleLine(fileName)
        let headerFileName = nameValue.replacingOccurrences(of: Constants.doubleQuote, with: Constants.singleQuote)

        FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }

        func writeField(_ name: String, _ value: String) throws {
            let part = partHeader(boundary: boundary, name: name) + value + Constants.lineBreak
            try handle.write(contentsOf: Data(part.utf8))
        }

        try writeField(MultipartField.uploadDestination, destinationValue)
        try writeField(MultipartField.relativePath, nameValue)

        let header = partHeader(boundary: boundary, name: MultipartField.fileData, fileName: headerFileName)
        try handle.write(contentsOf: Data(header.utf8))

        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: Constants.chunkSizeBytes), !chunk.isEmpty {
            try handle.write(contentsOf: chunk)
        }

        let closing = Constants.lineBreak + Constants.boundaryMarker + boundary
            + Constants.boundaryMarker + Constants.lineBreak
        try handle.write(contentsOf: Data(closing.utf8))
    }

    /// CR and LF would end a header line or a field early and let a name forge extra parts, so
    /// they become spaces; NUL has no safe replacement and is refused.
    static func singleLine(_ value: String) throws -> String {
        guard !value.unicodeScalars.contains(Constants.nulScalar) else { throw EnvelopeError.invalidField(value) }
        return value
            .replacingOccurrences(of: Constants.lineBreak, with: Constants.space)
            .replacingOccurrences(of: Constants.carriageReturn, with: Constants.space)
            .replacingOccurrences(of: Constants.lineFeed, with: Constants.space)
    }
}
