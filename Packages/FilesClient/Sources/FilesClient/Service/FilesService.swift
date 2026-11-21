import CoreModels
import Foundation
import NetworkClient

/// Plain JSON REST calls against NextExplorer's file browsing endpoints
/// (`/api/browse`, `/api/search`, `/api/favorites`, `/api/volumes`). Auth is
/// implicit: the session cookie captured by `AuthClient` rides along on
/// every request via `HTTPCookieStorage.appSession`.
///
/// The endpoint surface is split by domain across `FilesService+*.swift` extensions
/// (Browse, Favorites, FileOperations, Shares, Permissions, Admin, Settings, PreviewCache);
/// this file holds only the shared request plumbing they all build on.
struct FilesService: Sendable {
    let networkClient: NetworkClient
    /// Deduplicates concurrent downloads that target the same cache file: e.g. a PDF's
    /// background thumbnail fetch and a tap to open of the same file. Without it both would
    /// download the bytes and then race on the `moveItem` into the shared slot.
    let downloadCoordinator = PreviewDownloadCoordinator()
    let uploadSettings = UploadSettingsMemo()
    /// The ETag each text file had when the editor last read or saved it, so a save can tell that
    /// someone else changed the file in between.
    let textEditorETags: TextEditorETagStore
    /// The account scope text editor ETags are filed under, read when an operation starts.
    let activeScope: @Sendable () -> String

    init(
        networkClient: NetworkClient,
        textEditorETags: TextEditorETagStore = TextEditorETagStore(),
        activeScope: @escaping @Sendable () -> String = { CacheAccountScope.current }
    ) {
        self.networkClient = networkClient
        self.textEditorETags = textEditorETags
        self.activeScope = activeScope
    }

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

    func performSend(_ request: URLRequest, isLowPriority: Bool = false) async throws -> (Data, HTTPURLResponse) {
        do {
            return isLowPriority
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

    /// For the endpoints that report progress while they work: copy and move
    /// (`POST /api/files/copy`, `/move`) and the archive ones (`POST /api/files/zip/compress`,
    /// `/extract`). Current backends answer 200 with an NDJSON stream (`start`, `progress`, then
    /// `done` carrying the result, or `error`; see `backend/src/utils/ndjsonStream.js`) instead of
    /// one JSON body, so the result is decoded from the `done` line. A plain JSON body from an
    /// older server still works. With `onProgress`, the stream is read as it arrives and each
    /// `progress` event reports how far the work is (0 to 1).
    func sendStreamedOperation<Response: Decodable>(
        _ request: URLRequest,
        decoding _: Response.Type,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Response {
        let (data, response): (Data, HTTPURLResponse)
        if let onProgress {
            let decoder = Self.makeDecoder()
            do {
                (data, response) = try await networkClient.sendStreamingLines(request) { line in
                    if let fraction = (try? decoder.decode(OperationStreamEvent.self, from: line))?.fraction {
                        onProgress(fraction)
                    }
                }
            } catch {
                throw Self.mapTransportError(error)
            }
        } else {
            (data, response) = try await performSend(request)
        }
        try Self.validateReportingMessage(data, response)
        return try Self.decodeStreamedOperation(Response.self, from: data)
    }

    static func decodeStreamedOperation<Response: Decodable>(_: Response.Type, from data: Data) throws -> Response {
        let decoder = makeDecoder()
        let events = data.split(separator: UInt8(ascii: "\n")).compactMap { line -> (OperationStreamEvent, Data)? in
            let lineData = Data(line)
            guard let event = try? decoder.decode(OperationStreamEvent.self, from: lineData),
                  event.type != nil else { return nil }
            return (event, lineData)
        }
        guard !events.isEmpty else {
            do {
                return try decoder.decode(Response.self, from: data)
            } catch {
                throw FilesClientError.decoding(error.localizedDescription)
            }
        }
        if let (failure, _) = events.last(where: { $0.0.type == OperationStreamEvent.errorType }) {
            guard let message = failure.message, !message.isEmpty else {
                throw FilesClientError.server(statusCode: HTTPStatus.internalServerError.rawValue)
            }
            throw FilesClientError.serverMessage(statusCode: HTTPStatus.internalServerError.rawValue, message: message)
        }
        guard let (_, doneLine) = events.last(where: { $0.0.type == OperationStreamEvent.doneType }) else {
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
        switch error as? NetworkError {
        case .offline: .offline
        case .timedOut: .timedOut
        case .clientCertificateRequired: .clientCertificateRequired
        case .clientCertificateRejected: .clientCertificateRejected
        default: .network(String(describing: error))
        }
    }

    static func validate(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case HTTPStatus.success:
            return
        case HTTPStatus.unauthorized:
            throw FilesClientError.sessionExpired
        case HTTPStatus.forbidden:
            throw FilesClientError.forbidden(message: nil)
        case HTTPStatus.tooManyRequests:
            throw FilesClientError.rateLimited
        default:
            throw FilesClientError.server(statusCode: response.statusCode)
        }
    }

    /// `isMutation` gives a server side operation that sends nothing until it finishes (transfer,
    /// delete, compress, extract, rename) the long budget and the `.timedOut` mapping.
    static func makeRequest(url: URL, method: HTTPMethod, isMutation: Bool = false) -> URLRequest {
        var request = URLRequest(url: url, method: method)
        request.setValue(MIMEType.json, forHTTPHeaderField: HTTPHeaderField.accept)
        return isMutation ? NetworkClient.markingAsMutation(request) : request
    }

    static func validateReportingMessage(_ data: Data, _ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case HTTPStatus.success:
            return
        case HTTPStatus.unauthorized:
            throw FilesClientError.sessionExpired
        case HTTPStatus.forbidden:
            throw FilesClientError.forbidden(message: errorMessage(from: data))
        case HTTPStatus.tooManyRequests:
            throw FilesClientError.rateLimited
        default:
            if let message = errorMessage(from: data) {
                throw FilesClientError.serverMessage(statusCode: response.statusCode, message: message)
            }
            throw FilesClientError.server(statusCode: response.statusCode)
        }
    }

    static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = object[ErrorBodyKey.error] as? [String: Any],
           let message = error[ErrorBodyKey.message] as? String
        {
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

    /// Appends each `/` separated segment of `path` to `base` as its own path component, so
    /// each is percent encoded individually and a name with `/` unsafe characters survives.
    /// An empty `path` yields `base` with a trailing slash: several wildcard routes
    /// (`/api/browse/`, `/api/usage/`) need that to mean "the root". Shared by every
    /// `/api/<route>/*` wildcard path endpoint.
    static func appendingPathSegments(of path: String, to base: URL) -> URL {
        let segments = path.split(separator: "/", omittingEmptySubsequences: true)
        guard !segments.isEmpty else { return base.appendingPathComponent("") }
        return segments.reduce(base) { $0.appendingPathComponent(String($1)) }
    }

    /// `dateModified`/`createdAt`/`updatedAt` cross the wire as `Date.toISOString()` output
    /// (millisecond fractional seconds), which the default `.iso8601` strategy rejects;
    /// `ServerTimestamp` reads it and falls back to whole seconds, so one such date never aborts a
    /// whole screen's decode. The decoder is built once: a big listing dates every entry.
    private static let sharedDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { keyedDecoder in
            let container = try keyedDecoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = ServerTimestamp.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid ISO8601 date: \(dateString)"
            )
        }
        return decoder
    }()

    static func makeDecoder() -> JSONDecoder {
        sharedDecoder
    }
}
