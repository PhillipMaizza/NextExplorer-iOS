import Foundation

/// The HTTP verbs this app's REST calls use. Raw values are the wire strings assigned to
/// `URLRequest.httpMethod`.
public enum HTTPMethod: String, Sendable {
    case get = "GET"
    case head = "HEAD"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

/// The HTTP status codes the client and its mocks name, so no bare number stands for one. A
/// struct of named codes rather than an `enum`: a pattern that names an enum case only matches
/// that enum, while these match a raw `Int` status through `~=`.
public struct HTTPStatus: RawRepresentable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let ok = HTTPStatus(rawValue: 200)
    public static let created = HTTPStatus(rawValue: 201)
    public static let noContent = HTTPStatus(rawValue: 204)
    public static let partialContent = HTTPStatus(rawValue: 206)
    public static let notModified = HTTPStatus(rawValue: 304)
    public static let unauthorized = HTTPStatus(rawValue: 401)
    public static let forbidden = HTTPStatus(rawValue: 403)
    public static let notFound = HTTPStatus(rawValue: 404)
    public static let conflict = HTTPStatus(rawValue: 409)
    public static let gone = HTTPStatus(rawValue: 410)
    public static let payloadTooLarge = HTTPStatus(rawValue: 413)
    public static let unprocessableContent = HTTPStatus(rawValue: 422)
    public static let locked = HTTPStatus(rawValue: 423)
    public static let tooManyRequests = HTTPStatus(rawValue: 429)
    public static let internalServerError = HTTPStatus(rawValue: 500)
    public static let insufficientStorage = HTTPStatus(rawValue: 507)

    /// Every 2xx code.
    public static let success = 200 ..< 300
    /// Every 4xx code.
    public static let clientError = 400 ..< 500
    /// Every 5xx code.
    public static let serverError = 500 ..< 600

    public static func == (code: Int, status: HTTPStatus) -> Bool {
        code == status.rawValue
    }

    public static func != (code: Int, status: HTTPStatus) -> Bool {
        code != status.rawValue
    }
}

/// Lets a `switch` over a status code, or a pattern on one, name the code.
public func ~= (status: HTTPStatus, code: Int) -> Bool {
    code == status.rawValue
}

public func ~= (status: HTTPStatus, code: Int?) -> Bool {
    code == status.rawValue
}

/// Header field names, so a typo in `"Content-Type"` can't slip past the compiler.
public enum HTTPHeaderField {
    public static let contentType = "Content-Type"
    public static let accept = "Accept"
    public static let ifNoneMatch = "If-None-Match"
    public static let etag = "ETag"
    public static let cookie = "Cookie"
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

    /// `Content-Type: application/json`; the pair repeated before every JSON body.
    mutating func setJSONContentType() {
        setValue(MIMEType.json, forHTTPHeaderField: HTTPHeaderField.contentType)
    }
}
