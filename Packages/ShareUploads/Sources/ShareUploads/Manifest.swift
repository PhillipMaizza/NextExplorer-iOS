import Foundation

/// Why an upload did not go through, as far as the user can act on it.
public enum UploadFailureCause: String, Codable, CaseIterable, Sendable {
    /// 401: the session cookie was refused, so the user has to sign in again.
    case unauthorized
    /// 403: signed in, but not allowed to add files to that folder.
    case forbidden
    /// 507 or 413: the server cannot hold the file.
    case serverFull
    case network
    case other

    private enum StatusCode {
        static let unauthorized = 401
        static let forbidden = 403
        static let payloadTooLarge = 413
        static let insufficientStorage = 507
    }

    private static let networkErrors: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
        .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed,
        .cannotLoadFromNetwork, .secureConnectionFailed,
    ]

    /// An HTTP status wins over the transport error; a 2xx with no usable reply counts as `other`.
    static func classify(statusCode: Int?, error: (any Error)?) -> UploadFailureCause {
        switch statusCode {
        case StatusCode.unauthorized: return .unauthorized
        case StatusCode.forbidden: return .forbidden
        case StatusCode.payloadTooLarge, StatusCode.insufficientStorage: return .serverFull
        default: break
        }
        if let code = (error as? URLError)?.code, networkErrors.contains(code) {
            return .network
        }
        return .other
    }
}

enum UploadResult: Equatable, Sendable {
    case success
    case failure(UploadFailureCause)
    /// No event ever arrived for the file, so it was reported as failed. Unlike a real failure,
    /// the upload may still have gone through: a late event replaces this.
    case abandoned

    private static let successToken = "ok"
    private static let abandonedToken = "abandoned"

    var token: String {
        switch self {
        case .success: Self.successToken
        case .abandoned: Self.abandonedToken
        case let .failure(cause): cause.rawValue
        }
    }

    init?(token: String) {
        if token == Self.successToken {
            self = .success
        } else if token == Self.abandonedToken {
            self = .abandoned
        } else if let cause = UploadFailureCause(rawValue: token) {
            self = .failure(cause)
        } else {
            return nil
        }
    }

    var cause: UploadFailureCause? {
        switch self {
        case .success: nil
        case .abandoned: .other
        case let .failure(cause): cause
        }
    }
}

/// What a batch was for, kept beside its envelopes, plus one result file per finished upload
/// (files rather than one shared list, so two processes finishing tasks never overwrite each other).
struct Manifest: Codable, Equatable {
    /// `SessionCredentials.accountID`: signing that account out cancels the batch.
    var accountID: String
    var destination: String
    var fileNames: [String]
    /// Each file's envelope, by the same index.
    var envelopes: [String]
    /// Each envelope's content type header (it carries the boundary), so a failed file can be sent again.
    var contentTypes: [String]
    var serverURL: URL
    /// When the batch was handed to the system (or last retried).
    var startedAt: Date

    private enum Constants {
        static let markerPermissions: mode_t = 0o600
    }

    private static let fileName = "manifest.json"
    private static let resultsFolder = "results"
    private static let finishedMarker = "finished"

    func save(in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(self).write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }

    static func load(from directory: URL) -> Manifest? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(fileName)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Manifest.self, from: data)
    }

    /// Records one upload's result and returns every result so far, by file index.
    @discardableResult
    static func record(index: Int, result: UploadResult, in directory: URL) -> [Int: UploadResult] {
        let folder = directory.appendingPathComponent(resultsFolder, isDirectory: true)
        // Never recreates the batch folder: a batch that was removed stays removed.
        guard FileManager.default.fileExists(atPath: directory.path) else { return [:] }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try? Data(result.token.utf8).write(to: folder.appendingPathComponent(String(index)), options: .atomic)
        return results(in: directory)
    }

    /// Marks the batch as alive: another process (the app) treats a recently touched manifest as
    /// still being started and leaves it alone.
    static func touch(_ directory: URL, at date: Date) {
        try? FileManager.default.setAttributes(
            [.modificationDate: date], ofItemAtPath: directory.appendingPathComponent(fileName).path
        )
    }

    static func touchedAt(_ directory: URL) -> Date? {
        let values = try? directory.appendingPathComponent(fileName).resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    static func results(in directory: URL) -> [Int: UploadResult] {
        let folder = directory.appendingPathComponent(resultsFolder, isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        var results: [Int: UploadResult] = [:]
        for name in names {
            guard
                let index = Int(name),
                let data = try? Data(contentsOf: folder.appendingPathComponent(name)),
                let token = String(data: data, encoding: .utf8),
                let result = UploadResult(token: token)
            else { continue }
            results[index] = result
        }
        return results
    }

    static func clearResults(_ indices: [Int], in directory: URL) {
        let folder = directory.appendingPathComponent(resultsFolder, isDirectory: true)
        for index in indices {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(String(index)))
        }
    }

    /// Claims the right to finish the batch: the marker is created exclusively, so of two processes
    /// finishing the last uploads at once exactly one gets `true` and posts the notification.
    static func claim(_ directory: URL) -> Bool {
        let descriptor = open(markerURL(directory).path, O_CREAT | O_EXCL | O_WRONLY, Constants.markerPermissions)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    static func releaseClaim(_ directory: URL) {
        try? FileManager.default.removeItem(at: markerURL(directory))
    }

    /// When the batch was finished, or `nil` while it has not been.
    static func claimedAt(_ directory: URL) -> Date? {
        let values = try? markerURL(directory).resourceValues(forKeys: [.contentModificationDateKey])
        return values?.contentModificationDate
    }

    private static func markerURL(_ directory: URL) -> URL {
        directory.appendingPathComponent(finishedMarker)
    }
}

/// One file that did not go through.
public struct FailedUpload: Equatable, Sendable {
    public var name: String
    public var cause: UploadFailureCause
}

public struct BatchOutcome: Equatable, Sendable {
    public var batchID: String
    public var accountID: String
    public var host: String
    public var destination: String
    public var uploaded: Int
    public var failures: [FailedUpload]

    public var failedNames: [String] {
        failures.map(\.name)
    }
}
