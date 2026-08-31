import Foundation

/// The HTTP verbs this app's REST calls use. Raw values are the wire strings assigned to
/// `URLRequest.httpMethod`.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// Header field names, so a typo in `"Content-Type"` can't slip past the compiler.
public enum HTTPHeaderField {
    public static let contentType = "Content-Type"
    public static let accept = "Accept"
    public static let ifNoneMatch = "If-None-Match"
    public static let etag = "ETag"
}

/// Media types sent or accepted by the client.
public enum MIMEType {
    public static let json = "application/json"
    public static let octetStream = "application/octet-stream"
    public static let jpeg = "image/jpeg"

    public static func multipartFormData(boundary: String) -> String {
        "multipart/form-data; boundary=\(boundary)"
    }
}

public extension URLRequest {
    init(url: URL, method: HTTPMethod) {
        self.init(url: url)
        httpMethod = method.rawValue
    }

    /// `Content-Type: application/json` — the pair repeated before every JSON body.
    mutating func setJSONContentType() {
        setValue(MIMEType.json, forHTTPHeaderField: HTTPHeaderField.contentType)
    }
}
