import CoreModels
import Foundation
import NetworkClient

/// Plain JSON REST calls against NextExplorer's file-browsing endpoints
/// (`/api/browse`, `/api/search`, `/api/favorites`, `/api/volumes`). Auth is
/// implicit: the session cookie captured by `AuthClient` rides along on
/// every request via the shared `HTTPCookieStorage`.
///
/// The endpoint surface is split by domain across `FilesService+*.swift` extensions
/// (Browse, Favorites, FileOperations, Shares, Permissions, Admin, Settings, PreviewCache);
/// this file holds only the shared request plumbing they all build on.
struct FilesService: Sendable {
    let networkClient: NetworkClient
    /// De-duplicates concurrent downloads that target the same cache file — e.g. a PDF's
    /// background thumbnail fetch and a tap-to-open of the same file. Without it both would
    /// download the bytes and then race on the `moveItem` into the shared slot.
    let downloadCoordinator = PreviewDownloadCoordinator()

    static func encode(_ body: some Encodable) throws -> Data {
        do {
            return try JSONEncoder().encode(body)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    func send<Response: Decodable>(_ request: URLRequest, decoding _: Response.Type) async throws -> Response {
        let (data, response) = try await performSend(request)
        try Self.validate(response)
        do {
            return try Self.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    func performSend(_ request: URLRequest, lowPriority: Bool = false) async throws -> (Data, HTTPURLResponse) {
        do {
            return lowPriority
                ? try await networkClient.lowPrioritySend(request)
                : try await networkClient.send(request)
        } catch {
            throw Self.mapTransportError(error)
        }
    }

    /// Like `send`, but a non 2xx response whose body carries a message becomes
    /// `.serverMessage` rather than a bare `.server(statusCode:)`. The admin user management
    /// endpoints return meaningful validation text ("Email already in use.", etc.).
    func sendReportingMessage<Response: Decodable>(
        _ request: URLRequest, decoding _: Response.Type
    ) async throws -> Response {
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
        do {
            return try Self.makeDecoder().decode(Response.self, from: data)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    /// For the archive endpoints (`POST /api/files/zip/compress` and `/extract`). Current backends
    /// answer 200 with an NDJSON progress stream (`start`, `progress`, then `done` carrying the
    /// item, or `error`; see `backend/src/utils/ndjsonStream.js`) instead of one JSON body, so the
    /// result is decoded from the `done` line. A plain JSON body from an older server still works.
    func sendArchiveOperation<Response: Decodable>(
        _ request: URLRequest, decoding _: Response.Type
    ) async throws -> Response {
        let (data, response) = try await performSend(request)
        try Self.validateReportingMessage(data, response)
        return try Self.decodeArchiveOperation(Response.self, from: data)
    }

    static func decodeArchiveOperation<Response: Decodable>(_: Response.Type, from data: Data) throws -> Response {
        let decoder = makeDecoder()
        let events = data.split(separator: UInt8(ascii: "\n")).compactMap { line -> (ArchiveStreamEvent, Data)? in
            let lineData = Data(line)
            guard let event = try? decoder.decode(ArchiveStreamEvent.self, from: lineData), event.type != nil else { return nil }
            return (event, lineData)
        }
        guard !events.isEmpty else {
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw FilesClientError.decoding(error.localizedDescription)
            }
        }
        if let (failure, _) = events.last(where: { $0.0.type == ArchiveStreamEvent.errorType }) {
            guard let message = failure.message, !message.isEmpty else {
                throw FilesClientError.server(statusCode: 500)
            }
            throw FilesClientError.serverMessage(statusCode: 500, message: message)
        }
        guard let (_, doneLine) = events.last(where: { $0.0.type == ArchiveStreamEvent.doneType }) else {
            throw FilesClientError.decoding("The server ended the operation without a result.")
        }
        do {
            return try decoder.decode(Response.self, from: doneLine)
        } catch {
            throw FilesClientError.decoding(error.localizedDescription)
        }
    }

    /// Maps a raw error from the transport layer to a `FilesClientError`, preserving the
    /// `.offline` classification `NetworkClient` already made so callers can fall back to a
    /// cached copy instead of showing a generic network failure.
    static func mapTransportError(_ error: Error) -> FilesClientError {
        if let networkError = error as? NetworkError, networkError == .offline {
            return .offline
        }
        return .network(String(describing: error))
    }

    static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 401:
            throw FilesClientError.sessionExpired
        case 403:
            throw FilesClientError.forbidden(message: nil)
        case 429:
            throw FilesClientError.rateLimited
        default:
            throw FilesClientError.server(statusCode: response.statusCode)
        }
    }

    static func makeRequest(url: URL, method: HTTPMethod) -> URLRequest {
        var request = URLRequest(url: url, method: method)
        request.setValue(MIMEType.json, forHTTPHeaderField: HTTPHeaderField.accept)
        return request
    }

    static func validateReportingMessage(_ data: Data, _ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200 ..< 300:
            return
        case 401:
            throw FilesClientError.sessionExpired
        case 403:
            throw FilesClientError.forbidden(message: errorMessage(from: data))
        case 429:
            throw FilesClientError.rateLimited
        default:
            if let message = errorMessage(from: data) {
                throw FilesClientError.serverMessage(statusCode: response.statusCode, message: message)
            }
            throw FilesClientError.server(statusCode: response.statusCode)
        }
    }

    /// NextExplorer's error handler wraps operational errors as `{ error: { message } }`; the
    /// auth middleware uses a bare `{ error: "..." }` string; a few legacy routes use
    /// `{ message }`. Accept all three.
    static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object[ErrorBodyKey.error] as? [String: Any], let message = error[ErrorBodyKey.message] as? String {
            return message
        }
        if let error = object[ErrorBodyKey.error] as? String {
            return error
        }
        if let message = object[ErrorBodyKey.message] as? String {
            return message
        }
        return nil
    }

    /// Appends each `/`-separated segment of `path` to `base` as its own path component, so
    /// each is percent-encoded individually and a name with `/`-unsafe characters survives.
    /// An empty `path` yields `base` with a trailing slash — several wildcard routes
    /// (`/api/browse/`, `/api/usage/`) need that to mean "the root". Shared by every
    /// `/api/<route>/*` wildcard-path endpoint.
    static func appendingPathSegments(of path: String, to base: URL) -> URL {
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !segments.isEmpty else { return base.appendingPathComponent("") }
        return segments.reduce(base) { $0.appendingPathComponent(String($1)) }
    }

    /// `dateModified`/`createdAt`/`updatedAt` cross the wire as `Date.toISOString()`
    /// output (millisecond fractional seconds); the default `.iso8601` strategy's
    /// formatter rejects the fractional part, so fractional seconds must be opted in.
    ///
    /// Both the formatter and the fully configured decoder are built once and shared. A big
    /// browse listing carries a `dateModified` on every entry; allocating an
    /// `ISO8601DateFormatter` (and a `JSONDecoder`) per field, or per request, was pure
    /// overhead on large directories. `ISO8601DateFormatter` is documented as safe to use for
    /// parsing from multiple threads even though it is not marked `Sendable`.
    private nonisolated(unsafe) static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Fallback for a whole second date (no fractional part). The backend always emits
    /// millisecond fractions via `toISOString()`, but one non fractional date anywhere must
    /// not abort a whole screen's decode.
    private nonisolated(unsafe) static let iso8601FormatterNoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let sharedDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { keyedDecoder in
            let container = try keyedDecoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }
            if let date = iso8601FormatterNoFractional.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid ISO8601 date: \(dateString)")
        }
        return decoder
    }()

    static func makeDecoder() -> JSONDecoder {
        sharedDecoder
    }
}
