import Foundation
import UniformTypeIdentifiers

/// Reads what another app shared (Photos, Files, Finder) as files, in their original form: the
/// provider's own first file type is its highest fidelity one (a photo's HEIC or RAW original
/// rather than a JPEG copy, a video's original rather than a transcode), so nothing is compressed.
public enum SharedItemLoader {
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

    /// Stages one shared item into `batch` and returns it, or `nil` for an item with no file.
    /// The provider's temporary copy only lives for its callback, so the envelope is written there.
    public static func stage(_ provider: NSItemProvider, in batch: UploadBatch) async throws -> UploadBatch.StagedFile? {
        guard let type = preferredType(registered: provider.registeredTypeIdentifiers) else { return nil }
        if type.conforms(to: .fileURL), !type.conforms(to: .data) {
            return try await stageFileURL(provider, in: batch)
        }
        let suggestedName = provider.suggestedName
        return try await withCheckedThrowingContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, error in
                guard let url else {
                    continuation.resume(throwing: error ?? CocoaError(.fileReadUnknown))
                    return
                }
                do {
                    let name = fileName(fileURL: url, suggestedName: suggestedName, type: type)
                    try continuation.resume(returning: batch.envelope(for: url, fileName: name))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Finder and Files hand over a file URL rather than the bytes.
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
        return try batch.envelope(for: url, fileName: url.lastPathComponent)
    }
}
