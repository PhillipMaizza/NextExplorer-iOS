import Foundation
import UniformTypeIdentifiers

/// Reads what another app shared (Photos, Files, Finder) as files, in their original form: the
/// provider's own first file type is its highest fidelity one (a photo's HEIC or RAW original
/// rather than a JPEG copy, a video's original rather than a transcode), so nothing is compressed.
public enum SharedItemLoader {
    enum StagingMode: Equatable {
        /// The provider hands over the file's bytes.
        case representation
        /// The provider hands over a file URL (Finder, Files) to read the file from.
        case fileURL
    }

    /// The type to ask `provider` for, or `nil` when it carries no file (a link, plain text).
    public static func preferredType(registered identifiers: [String]) -> UTType? {
        let types = identifiers.compactMap(UTType.init)
        let media = types.first { $0.conforms(to: .image) || $0.conforms(to: .movie) || $0.conforms(to: .audio) }
        if let media {
            return media
        }
        return types.first { $0.conforms(to: .data) && !$0.conforms(to: .url) && !$0.conforms(to: .plainText) }
            ?? types.first { $0.conforms(to: .fileURL) }
    }

    /// The file URL type itself conforms to `public.data`, so it is told apart by its own
    /// conformance: asking it for a file representation would upload the URL's text.
    static func stagingMode(for type: UTType) -> StagingMode {
        type.conforms(to: .fileURL) ? .fileURL : .representation
    }

    /// The types to stage for one item. A Live Photo is two files, the still and its paired movie,
    /// and both are wanted; anything else is its one preferred type.
    static func stagingTypes(registered identifiers: [String]) -> [UTType] {
        let types = identifiers.compactMap(UTType.init)
        guard types.contains(where: { $0.conforms(to: .livePhoto) }) else {
            return preferredType(registered: identifiers).map { [$0] } ?? []
        }
        let still = types.first { $0.conforms(to: .image) }
        let movie = types.first { $0.conforms(to: .movie) }
        return [still, movie].compactMap { $0 }
    }

    /// The paired movie shares the still's name, with the movie's own extension.
    static func pairedMovieName(stillName: String, movieType: UTType) -> String {
        let base = (stillName as NSString).deletingPathExtension
        guard let fileExtension = movieType.preferredFilenameExtension else { return base }
        return "\(base).\(fileExtension)"
    }

    /// The name to upload under: the file's own name when it has an extension, else the provider's
    /// suggested name with the type's extension (Photos suggests "IMG_0042" for an IMG_0042.HEIC).
    public static func fileName(fileURL: URL, suggestedName: String?, type: UTType) -> String {
        if !fileURL.pathExtension.isEmpty, !fileURL.deletingPathExtension().lastPathComponent.isEmpty {
            return fileURL.lastPathComponent
        }
        let base = suggestedName.flatMap { $0.isEmpty ? nil : $0 } ?? fileURL.deletingPathExtension().lastPathComponent
        guard let fileExtension = type.preferredFilenameExtension, (base as NSString).pathExtension.isEmpty else {
            return base
        }
        return "\(base).\(fileExtension)"
    }

    /// Stages one shared item into `batch` and returns its main file, or `nil` for an item with no
    /// file. This leaves a Live Photo's paired movie behind: use `stageAll` to keep both.
    public static func stage(_ provider: NSItemProvider, in batch: UploadBatch) async throws -> UploadBatch.StagedFile? {
        guard let type = preferredType(registered: provider.registeredTypeIdentifiers) else { return nil }
        return try await stage(provider, type: type, in: batch, pairedWith: nil)
    }

    /// Stages every file one shared item stands for: the file itself, plus a Live Photo's paired
    /// movie under the still's name. Empty for an item with no file (a link, plain text).
    public static func stageAll(_ provider: NSItemProvider, in batch: UploadBatch) async throws -> [UploadBatch.StagedFile] {
        var staged: [UploadBatch.StagedFile] = []
        do {
            for type in stagingTypes(registered: provider.registeredTypeIdentifiers) {
                let stillName = type.conforms(to: .movie) ? staged.first?.fileName : nil
                if let file = try await stage(provider, type: type, in: batch, pairedWith: stillName) {
                    staged.append(file)
                }
            }
        } catch {
            // A Live Photo is all or nothing: a still without its movie would not be the photo.
            for file in staged {
                try? FileManager.default.removeItem(at: file.envelopeURL)
            }
            throw error
        }
        return staged
    }

    /// The provider's temporary copy only lives for its callback, so the envelope is written there.
    private static func stage(
        _ provider: NSItemProvider, type: UTType, in batch: UploadBatch, pairedWith stillName: String?
    ) async throws -> UploadBatch.StagedFile? {
        if stagingMode(for: type) == .fileURL {
            return try await stageFileURL(provider, in: batch)
        }
        let suggestedName = provider.suggestedName
        let flag = CancelFlag()
        let file: UploadBatch.StagedFile = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, error in
                    guard let url else {
                        continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                        return
                    }
                    continuation.resume(with: Result {
                        let name = stillName.map { pairedMovieName(stillName: $0, movieType: type) }
                            ?? fileName(fileURL: url, suggestedName: suggestedName, type: type)
                        return try writeEnvelope(for: url, fileName: name, in: batch, flag: flag)
                    })
                }
            }
        } onCancel: {
            flag.cancel()
        }
        return try discardingIfCancelled(file)
    }

    /// A cancellation that lands just as the envelope was finished still takes it back out.
    private static func discardingIfCancelled(_ file: UploadBatch.StagedFile?) throws -> UploadBatch.StagedFile? {
        guard let file, Task.isCancelled else { return file }
        try? FileManager.default.removeItem(at: file.envelopeURL)
        throw CancellationError()
    }

    /// Finder and Files hand over a file URL rather than the bytes. The file may live in iCloud
    /// or another file provider and still be a placeholder, so it is read through a coordinator.
    private static func stageFileURL(_ provider: NSItemProvider, in batch: UploadBatch) async throws -> UploadBatch.StagedFile? {
        let loaded: URL? = try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadObject(ofClass: URL.self) { url, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: url)
                }
            }
        }
        guard let url = loaded, url.isFileURL else { return nil }
        return try await stageFile(at: url, in: batch, access: .live)
    }

    /// Writes the envelope unless the staging was cancelled or the batch discarded, and takes it
    /// back out when the cancellation or the discard lands while it was being written.
    private static func writeEnvelope(
        for url: URL, fileName: String, in batch: UploadBatch, flag: CancelFlag
    ) throws -> UploadBatch.StagedFile {
        try flag.throwIfCancelled()
        let file = try batch.envelope(for: url, fileName: fileName)
        if flag.isCancelled || !batch.exists {
            try? FileManager.default.removeItem(at: file.envelopeURL)
            throw CancellationError()
        }
        return file
    }

    static func stageFile(at url: URL, in batch: UploadBatch, access: FileAccess) async throws -> UploadBatch.StagedFile? {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        try Task.checkCancellation()
        let flag = CancelFlag()
        let file: UploadBatch.StagedFile = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    continuation.resume(with: Result {
                        try flag.throwIfCancelled()
                        return try access.read(url) { readURL in
                            try writeEnvelope(for: readURL, fileName: url.lastPathComponent, in: batch, flag: flag)
                        }
                    })
                }
            }
        } onCancel: {
            flag.cancel()
        }
        return try discardingIfCancelled(file)
    }
}

/// A coordinated read or a provider callback runs on a queue where the task's own cancellation
/// can't be seen: the cancellation handler sets this instead.
private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func cancel() {
        lock.withLock { cancelled = true }
    }

    func throwIfCancelled() throws {
        if isCancelled {
            throw CancellationError()
        }
    }
}
