import ComposableArchitecture
import Foundation
import PhotosUI
import SwiftUI

/// The one app owned scratch folder every not yet uploaded file is copied into. Picker URLs
/// are security scoped and don't outlive their callback; `PhotosPickerItem` data and camera
/// captures have no URL at all until written somewhere. `UploadStagingClient` owns writing
/// into here, `discard` owns cleaning up.
enum UploadStagingLocation {
    static var directory: URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PendingUploads", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// Turns picker output (`fileImporter` URLs, `PhotosPickerItem`s, a camera capture) into
/// `PickedFile`s copied to `UploadStagingLocation`, and deletes those copies once they've been
/// uploaded, cancelled, or cleared. Small and specific to the upload flow on purpose — it is
/// not a general file system abstraction.
///
/// `stageDocuments` / `stagePhotos` return an `AsyncStream` so the review sheet fills in file
/// by file as each heavy item finishes copying, rather than blocking behind the whole batch.
/// Files that fail to copy are simply omitted from the stream.
public struct UploadStagingClient: Sendable {
    public var stageDocuments: @Sendable (_ urls: [URL]) -> AsyncStream<PickedFile>
    public var stagePhotos: @Sendable (_ items: [PhotosPickerItem]) -> AsyncStream<PickedFile>
    public var stageCameraCapture: @Sendable (_ url: URL) async -> PickedFile?
    public var discard: @Sendable (_ urls: [URL]) async -> Void

    public init(
        stageDocuments: @escaping @Sendable (_ urls: [URL]) -> AsyncStream<PickedFile>,
        stagePhotos: @escaping @Sendable (_ items: [PhotosPickerItem]) -> AsyncStream<PickedFile>,
        stageCameraCapture: @escaping @Sendable (_ url: URL) async -> PickedFile?,
        discard: @escaping @Sendable (_ urls: [URL]) async -> Void
    ) {
        self.stageDocuments = stageDocuments
        self.stagePhotos = stagePhotos
        self.stageCameraCapture = stageCameraCapture
        self.discard = discard
    }
}

extension UploadStagingClient: DependencyKey {
    public static let liveValue = UploadStagingClient(
        stageDocuments: { urls in
            AsyncStream { continuation in
                let task = Task {
                    let directory = UploadStagingLocation.directory
                    await withTaskGroup(of: PickedFile?.self) { group in
                        for url in urls {
                            group.addTask {
                                let didAccess = url.startAccessingSecurityScopedResource()
                                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                                let name = url.lastPathComponent
                                let temp = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
                                try? FileManager.default.removeItem(at: temp)
                                guard (try? FileManager.default.copyItem(at: url, to: temp)) != nil else { return nil }
                                let size = Int64((try? temp.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
                                return PickedFile(fileURL: temp, fileName: name, size: size)
                            }
                        }
                        for await file in group {
                            if let file { continuation.yield(file) }
                        }
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        },
        stagePhotos: { items in
            AsyncStream { continuation in
                let task = Task {
                    let directory = UploadStagingLocation.directory
                    let stamp = Int(Date().timeIntervalSince1970)
                    await withTaskGroup(of: PickedFile?.self) { group in
                        for (index, item) in items.enumerated() {
                            group.addTask {
                                guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
                                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
                                let name = "IMG_\(stamp)_\(index + 1).\(ext)"
                                let temp = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
                                guard (try? data.write(to: temp)) != nil else { return nil }
                                return PickedFile(fileURL: temp, fileName: name, size: Int64(data.count))
                            }
                        }
                        for await file in group {
                            if let file { continuation.yield(file) }
                        }
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        },
        stageCameraCapture: { url in
            let size = Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
            return PickedFile(fileURL: url, fileName: url.lastPathComponent, size: size)
        },
        discard: { urls in
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
        }
    )

    /// Benign no op default: staging yields nothing, `discard` is a no op. Suites that exercise
    /// staging behaviour override `stageDocuments` / `stagePhotos` with a stub that yields
    /// known `PickedFile`s.
    public static let testValue = UploadStagingClient(
        stageDocuments: { _ in AsyncStream<PickedFile> { $0.finish() } },
        stagePhotos: { _ in AsyncStream<PickedFile> { $0.finish() } },
        stageCameraCapture: { _ in nil },
        discard: { _ in }
    )

    public static let previewValue = testValue
}

public extension DependencyValues {
    var uploadStaging: UploadStagingClient {
        get { self[UploadStagingClient.self] }
        set { self[UploadStagingClient.self] = newValue }
    }
}
