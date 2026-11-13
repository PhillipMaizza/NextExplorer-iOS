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

    /// How a provider hands over one type's file: `NSItemProvider.loadFileRepresentation` in
    /// production, a stand in in tests.
    typealias RepresentationLoader = (
        _ type: UTType, _ completion: @escaping @Sendable (URL?, Bool, (any Error)?) -> Void
    ) -> Progress?

    /// Stages every file one shared item stands for: the file itself, plus a Live Photo's paired
    /// movie under the still's name. Empty for an item with no file (a link, plain text).
    /// `onFraction` reports how much of the item has been read, 0 to 1, across all its files.
    public static func stageAll(
        _ provider: NSItemProvider,
        in batch: UploadBatch,
        onFraction: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> [UploadBatch.StagedFile] {
        let types = stagingTypes(registered: provider.registeredTypeIdentifiers)
        let suggestedName = provider.suggestedName
        var staged: [UploadBatch.StagedFile] = []
        do {
            for (position, type) in types.enumerated() {
                let stillName = type.conforms(to: .movie) ? staged.first?.fileName : nil
                let file: UploadBatch.StagedFile? = if stagingMode(for: type) == .fileURL {
                    try await stageFileURL(provider, in: batch)
                } else {
                    try await stageRepresentation(
                        type: type, suggestedName: suggestedName, pairedWith: stillName, in: batch,
                        load: { provider.loadFileRepresentation(for: $0, openInPlace: false, completionHandler: $1) },
                        onFraction: { onFraction(overallFraction(position: position, count: types.count, fraction: $0))
                        }
                    )
                }
                if let file {
                    staged.append(file)
                }
            }
        } catch {
            // A Live Photo is all or nothing: a still without its movie would not be the photo.
            for file in staged {
                file.removeEnvelope()
            }
            throw error
        }
        return staged
    }

    /// Where one file of an item's `count` files being at `fraction` puts the whole item.
    static func overallFraction(position: Int, count: Int, fraction: Double) -> Double {
        guard count > 0 else { return 0 }
        return (Double(position) + fraction) / Double(count)
    }

    /// The provider's temporary copy only lives for its callback, so the envelope is written there.
    /// Cancelling stops the copy itself, not just the wait for it.
    static func stageRepresentation(
        type: UTType,
        suggestedName: String?,
        pairedWith stillName: String?,
        in batch: UploadBatch,
        load: RepresentationLoader,
        onFraction: @escaping @Sendable (Double) -> Void
    ) async throws -> UploadBatch.StagedFile {
        let loading = CancellableLoad()
        let file: UploadBatch.StagedFile = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                guard loading.install(continuation) else { return }
                let progress = load(type) { url, _, error in
                    guard let url else {
                        loading.finish(.failure(error ?? CocoaError(.fileReadUnknown)))
                        return
                    }
                    guard loading.isActive else { return }
                    loading.finish(Result {
                        let name = stillName.map { pairedMovieName(stillName: $0, movieType: type) }
                            ?? fileName(fileURL: url, suggestedName: suggestedName, type: type)
                        let file = try batch.envelope(for: url, fileName: name)
                        guard loading.isActive, batch.exists else {
                            file.removeEnvelope()
                            throw CancellationError()
                        }
                        return file
                    })
                }
                loading.attach(progress, onFraction: onFraction)
            }
        } onCancel: {
            loading.cancel()
        }
        return try discardingIfCancelled(file)
    }

    /// A cancellation that lands just as the envelope was finished still takes it back out.
    private static func discardingIfCancelled(_ file: UploadBatch.StagedFile) throws -> UploadBatch.StagedFile {
        guard Task.isCancelled else { return file }
        file.removeEnvelope()
        throw CancellationError()
    }

    /// Finder and Files hand over a file URL rather than the bytes. The file may live in iCloud
    /// or another file provider and still be a placeholder, so it is read through a coordinator.
    private static func stageFileURL(_ provider: NSItemProvider, in batch: UploadBatch) async throws -> UploadBatch
        .StagedFile?
    {
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
            file.removeEnvelope()
            throw CancellationError()
        }
        return file
    }

    /// Throws `ShareUploadError.isFolder` for a folder and `fileNoSuchFile` for a path with nothing
    /// behind it: an item is never dropped without the user being told.
    static func stageFile(at url: URL, in batch: UploadBatch, access: FileAccess) async throws -> UploadBatch.StagedFile
    {
        let isScoped = url.startAccessingSecurityScopedResource()
        defer {
            if isScoped {
                url.stopAccessingSecurityScopedResource()
            }
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw CocoaError(.fileNoSuchFile)
        }
        guard !isDirectory.boolValue else { throw ShareUploadError.isFolder }
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
