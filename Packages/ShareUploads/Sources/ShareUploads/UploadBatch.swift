import CoreModels
import FilesClient
import Foundation
import Localization
import UniformTypeIdentifiers

/// Why a shared item could not be prepared for upload.
public enum ShareUploadError: Error, Equatable, LocalizedError {
    /// The device cannot hold the staged copy of a file (the envelope doubles its size on disk).
    case insufficientSpace
    /// A folder was shared: the upload takes files only.
    case isFolder

    public var errorDescription: String? {
        switch self {
        case .insufficientSpace: L10n.ShareUpload.insufficientSpace
        case .isFolder: L10n.ShareUpload.causeFolder
        }
    }

    /// Whether `error`, or the error it wraps, says the device ran out of room (a full disk
    /// surfaces as a Cocoa error or as the POSIX one underneath it, depending on who threw).
    public static func isOutOfSpace(_ error: any Error) -> Bool {
        if let shareError = error as? ShareUploadError, shareError == .insufficientSpace {
            return true
        }
        let nsError = error as NSError
        switch nsError.domain {
        case NSCocoaErrorDomain where nsError.code == CocoaError.fileWriteOutOfSpace.rawValue,
             NSPOSIXErrorDomain where nsError.code == Int(ENOSPC) || nsError.code == Int(EDQUOT):
            return true
        default:
            break
        }
        guard let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError else { return false }
        return isOutOfSpace(underlying)
    }
}

enum DiskSpace {
    private enum Constants {
        static let bytesPerMebibyte: Int64 = 1_048_576
        static let reservedMebibytes: Int64 = 256
    }

    /// Left free on top of the file so staging never fills the device completely.
    static let reservedBytes: Int64 = Constants.reservedMebibytes * Constants.bytesPerMebibyte

    static func hasRoom(forBytes required: Int64, available: Int64?) -> Bool {
        guard let available else { return true }
        return available >= required + reservedBytes
    }

    /// What is free right now, without counting space the system might purge, so it is the
    /// conservative figure.
    static func availableCapacity(at directory: URL) -> Int64? {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    static func size(of fileURL: URL) -> Int64 {
        let values = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init) ?? 0
    }
}

/// The bytes envelopes being written right now will take. The volume's free space only drops as
/// they are written, so files staged in parallel would each see room that the others are about
/// to use: a file reserves its size here first, under a lock, and gives it back once written.
final class SpaceLedger: @unchecked Sendable {
    private let lock = NSLock()
    private var reservedBytes: Int64 = 0

    var inFlight: Int64 {
        lock.withLock { reservedBytes }
    }

    func reserve(_ bytes: Int64, available: Int64?) -> Bool {
        lock.withLock {
            guard DiskSpace.hasRoom(forBytes: reservedBytes + bytes, available: available) else { return false }
            reservedBytes += bytes
            return true
        }
    }

    func release(_ bytes: Int64) {
        lock.withLock { reservedBytes = max(0, reservedBytes - bytes) }
    }
}

/// Writes one envelope; `UploadRequest.make` in production.
typealias EnvelopeWriter = @Sendable (
    _ serverURL: URL, _ fileURL: URL, _ fileName: String, _ destination: String, _ envelopeURL: URL
) throws -> URLRequest

private enum EnvelopeConstants {
    static let contentTypeHeader = "Content-Type"
    static let envelopeExtension = "multipart"
}

/// One share's worth of files. Each file's envelope is written as soon as its bytes are readable
/// (`envelope(for:fileName:)`, safe from an item provider's callback), so only one copy of it
/// ever exists on disk, then `add`ed in the order the user picked them.
public struct UploadBatch: Sendable {
    public struct StagedFile: Sendable {
        let fileName: String
        let envelopeURL: URL
        let request: URLRequest

        /// Takes the envelope back out, for a file whose staging was cancelled after it was written.
        public func removeEnvelope() {
            try? FileManager.default.removeItem(at: envelopeURL)
        }

        var contentType: String {
            request.value(forHTTPHeaderField: EnvelopeConstants.contentTypeHeader) ?? ""
        }
    }

    public let id: String
    let directory: URL
    let credentials: SessionCredentials
    public let destination: String
    var availableCapacity: @Sendable (URL) -> Int64? = DiskSpace.availableCapacity
    var writeEnvelope: EnvelopeWriter = { serverURL, fileURL, fileName, destination, envelopeURL in
        try UploadRequest.make(
            serverURL: serverURL, fileURL: fileURL, fileName: fileName, destination: destination,
            envelopeURL: envelopeURL
        )
    }

    /// Seeds each staged picture's or PDF's thumbnail, so the app shows it before the server has
    /// made its own. A seam, like `writeEnvelope`.
    var thumbnailStore: LocalThumbnailStore = .liveValue
    var now: @Sendable () -> Date = { Date() }

    let ledger = SpaceLedger()
    private(set) var staged: [StagedFile] = []

    public var count: Int {
        staged.count
    }

    /// `false` once the batch was discarded.
    var exists: Bool {
        FileManager.default.fileExists(atPath: directory.path)
    }

    /// Writes `fileURL`'s upload envelope into the batch folder. `fileURL` may go right after.
    /// Throws `ShareUploadError.insufficientSpace` when the device cannot hold the copy, and
    /// `CancellationError` when the batch was discarded meanwhile (it is never recreated). Whatever
    /// goes wrong, no partial envelope stays behind.
    public func envelope(for fileURL: URL, fileName: String) throws -> StagedFile {
        guard exists else { throw CancellationError() }
        let size = DiskSpace.size(of: fileURL)
        guard ledger.reserve(size, available: availableCapacity(directory)) else {
            throw ShareUploadError.insufficientSpace
        }
        defer { ledger.release(size) }
        let envelopeURL = directory
            .appendingPathComponent("\(UUID().uuidString).\(EnvelopeConstants.envelopeExtension)")
        do {
            let request = try writeEnvelope(credentials.serverBaseURL, fileURL, fileName, destination, envelopeURL)
            thumbnailStore.seed(
                fileURL,
                UTType(filenameExtension: (fileName as NSString).pathExtension),
                LocalThumbnailStore.path(of: fileName, in: destination),
                credentials.accountID,
                now()
            )
            return StagedFile(fileName: fileName, envelopeURL: envelopeURL, request: request)
        } catch {
            try? FileManager.default.removeItem(at: envelopeURL)
            throw ShareUploadError.isOutOfSpace(error) ? ShareUploadError.insufficientSpace : error
        }
    }

    public mutating func add(_ file: StagedFile) {
        staged.append(file)
    }
}
