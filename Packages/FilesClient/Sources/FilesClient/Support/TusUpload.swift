import Foundation
import NetworkClient

/// The requests of a resumable upload (`/api/upload/tus`, tus 1.0.0 core plus creation and
/// termination). Pure builders and parsers; `FilesService.uploadChunked` drives them.
enum TusUpload {
    enum Header {
        static let resumable = "Tus-Resumable"
        static let uploadLength = "Upload-Length"
        static let uploadOffset = "Upload-Offset"
        static let uploadMetadata = "Upload-Metadata"
        static let finalizeError = "Upload-Finalize-Error"
        static let location = "Location"
    }

    private enum Constants {
        static let version = "1.0.0"
        static let offsetContentType = "application/offset+octet-stream"
        static let filenameKey = "filename"
        static let destinationKey = "uploadTo"
        static let relativePathKey = "relativePath"
    }

    /// `base64` values, comma separated, as the protocol asks. `relativePath` is the full path
    /// including the name, like the multipart field.
    static func metadata(fileName: String, destination: String) -> String {
        [
            (Constants.filenameKey, fileName),
            (Constants.destinationKey, destination),
            (Constants.relativePathKey, fileName),
        ]
        .map { "\($0.0) \(Data($0.1.utf8).base64EncodedString())" }
        .joined(separator: ",")
    }

    static func createRequest(serverURL: URL, length: Int, fileName: String, destination: String) -> URLRequest {
        var request = FilesService.makeRequest(
            url: serverURL.appendingPathComponent(APIPath.tusUpload),
            method: .post
        )
        request.setValue(Constants.version, forHTTPHeaderField: Header.resumable)
        request.setValue(String(length), forHTTPHeaderField: Header.uploadLength)
        request.setValue(
            metadata(fileName: fileName, destination: destination),
            forHTTPHeaderField: Header.uploadMetadata
        )
        return request
    }

    /// The upload's URL rebuilt on the server the app already talks to. The `Location` header is
    /// untrusted: behind a proxy it can name another host or scheme, and the session cookie must
    /// never follow it there, so only its id is taken.
    static func uploadURL(serverURL: URL, location: String?) -> URL? {
        guard let id = location?.split(separator: "/").last.map(String.init),
              !id.isEmpty,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
        else { return nil }
        return serverURL.appendingPathComponent(APIPath.tusUpload).appendingPathComponent(id)
    }

    static func patchRequest(uploadURL: URL, offset: Int) -> URLRequest {
        var request = FilesService.makeRequest(url: uploadURL, method: .patch)
        request.setValue(Constants.version, forHTTPHeaderField: Header.resumable)
        request.setValue(Constants.offsetContentType, forHTTPHeaderField: HTTPHeaderField.contentType)
        request.setValue(String(offset), forHTTPHeaderField: Header.uploadOffset)
        return request
    }

    static func headRequest(uploadURL: URL) -> URLRequest {
        var request = FilesService.makeRequest(url: uploadURL, method: .head)
        request.setValue(Constants.version, forHTTPHeaderField: Header.resumable)
        return request
    }

    static func deleteRequest(uploadURL: URL) -> URLRequest {
        var request = FilesService.makeRequest(url: uploadURL, method: .delete)
        request.setValue(Constants.version, forHTTPHeaderField: Header.resumable)
        return request
    }

    static func offset(of response: HTTPURLResponse) -> Int? {
        response.value(forHTTPHeaderField: Header.uploadOffset).flatMap(Int.init)
    }

    /// The sentence the server gave when every byte arrived but the file could not be placed.
    /// Its presence means a retry cannot help.
    static func finalizeError(of response: HTTPURLResponse) -> String? {
        guard let raw = response.value(forHTTPHeaderField: Header.finalizeError) else { return nil }
        return raw.removingPercentEncoding ?? raw
    }
}
