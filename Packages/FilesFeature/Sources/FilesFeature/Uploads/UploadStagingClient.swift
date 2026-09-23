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

    /// Copies one picked or dropped URL into `directory`. A folder (a Mac Finder drop) expands
    /// into its files, each named by its path under the folder ("Trip/Day 1/a.jpg"); the
    /// server's `relativePath` recreates those subfolders at the destination.
    static func stage(_ url: URL, into directory: URL) -> [PickedFile] {
        let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        guard isDirectory else {
            return copy(url, named: url.lastPathComponent, into: directory).map { [$0] } ?? []
        }
        let root = url.standardizedFileURL.path + "/"
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [PickedFile] = []
        for case let fileURL as URL in enumerator {
            guard (try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            let path = fileURL.standardizedFileURL.path
            guard path.hasPrefix(root) else { continue }
            let relativeName = url.lastPathComponent + "/" + path.dropFirst(root.count)
            if let file = copy(fileURL, named: relativeName, into: directory) {
                files.append(file)
            }
        }
        return files
    }

    private static func copy(_ source: URL, named name: String, into directory: URL) -> PickedFile? {
        let temp = directory.appendingPathComponent("\(UUID().uuidString)-\(source.lastPathComponent)")
        try? FileManager.default.removeItem(at: temp)
        guard (try? FileManager.default.copyItem(at: source, to: temp)) != nil else { return nil }
        let size = Int64((try? temp.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        return PickedFile(fileURL: temp, fileName: name, size: size)
    }
}

/// Turns picker output (`fileImporter` URLs, `PhotosPickerItem`s, a camera capture) into
/// `PickedFile`s copied to `UploadStagingLocation`, and deletes those copies once they've been
/// uploaded, cancelled, or cleared. Small and specific to the upload flow on purpose — it is
/// not a general file system abstraction.
///
/// `stageDocuments` / `stagePhotos` return an `AsyncStream` so the review sheet fills in file
/// by file as each heavy item finishes copying, rather than blocking behind the whole batch.
/// Files that fail to copy are omitted from the stream; the caller reconciles the count that
/// arrived against the count requested to surface how many were skipped.
public struct UploadStagingClient: Sendable {
    public var stageDocuments: @Sendable (_ urls: [URL]) -> AsyncStream<PickedFile>
    public var stagePhotos: @Sendable (_ items: [PhotosPickerItem]) -> AsyncStream<PickedFile>
    public var stageCameraCapture: @Sendable (_ url: URL) async -> PickedFile?
    public var discard: @Sendable (_ urls: [URL]) async -> Void
    /// Deletes staged files old enough that no queue or review sheet can still need them —
    /// the catch all for a temp file orphaned by a staging run cancelled mid copy.
    public var sweepStale: @Sendable () async -> Void

    public init(
        stageDocuments: @escaping @Sendable (_ urls: [URL]) -> AsyncStream<PickedFile>,
        stagePhotos: @escaping @Sendable (_ items: [PhotosPickerItem]) -> AsyncStream<PickedFile>,
        stageCameraCapture: @escaping @Sendable (_ url: URL) async -> PickedFile?,
        discard: @escaping @Sendable (_ urls: [URL]) async -> Void,
        sweepStale: @escaping @Sendable () async -> Void
    ) {
        self.stageDocuments = stageDocuments
        self.stagePhotos = stagePhotos
        self.stageCameraCapture = stageCameraCapture
        self.discard = discard
        self.sweepStale = sweepStale
    }
}

extension UploadStagingClient: DependencyKey {
    public static let liveValue = UploadStagingClient(
        stageDocuments: { urls in
            AsyncStream { continuation in
                let task = Task {
                    let directory = UploadStagingLocation.directory
                    await withTaskGroup(of: [PickedFile].self) { group in
                        for url in urls {
                            group.addTask {
                                let didAccess = url.startAccessingSecurityScopedResource()
                                defer {
                                    if didAccess {
                                        url.stopAccessingSecurityScopedResource()
                                    }
                                }
                                return UploadStagingLocation.stage(url, into: directory)
                            }
                        }
                        for await files in group {
                            for file in files {
                                continuation.yield(file)
                            }
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
                    // Each `loadTransferable(type: Data.self)` pulls a whole photo into memory.
                    // Cap how many are in flight at once so picking a large batch of ProRAW /
                    // HEIC shots doesn't hold all of them resident and trip a memory kill.
                    let maxConcurrent = 3
                    await withTaskGroup(of: PickedFile?.self) { group in
                        func addTask(index: Int) {
                            let item = items[index]
                            group.addTask {
                                guard let data = try? await item.loadTransferable(type: Data.self) else { return nil }
                                let ext = item.supportedContentTypes.first?.preferredFilenameExtension ?? "dat"
                                let name = "IMG_\(stamp)_\(index + 1).\(ext)"
                                let temp = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
                                guard (try? data.write(to: temp)) != nil else { return nil }
                                return PickedFile(fileURL: temp, fileName: name, size: Int64(data.count))
                            }
                        }

                        var nextIndex = 0
                        while nextIndex < min(maxConcurrent, items.count) {
                            addTask(index: nextIndex)
                            nextIndex += 1
                        }
                        for await file in group {
                            if let file {
                                continuation.yield(file)
                            }
                            if nextIndex < items.count {
                                addTask(index: nextIndex)
                                nextIndex += 1
                            }
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
        },
        sweepStale: {
            let cutoff = Date().addingTimeInterval(-staleStagingAge)
            let directory = UploadStagingLocation.directory
            let entries = (try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: []
            )) ?? []
            for url in entries {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified < cutoff {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    )

    /// Files older than this in `UploadStagingLocation` cannot belong to a live upload or an
    /// open review sheet, so `sweepStale` deletes them.
    private static let staleStagingAge: TimeInterval = 24 * 60 * 60

    /// Benign no op default: staging yields nothing, `discard` / `sweepStale` are no ops.
    /// Suites that exercise staging behaviour override `stageDocuments` / `stagePhotos` with a
    /// stub that yields known `PickedFile`s.
    public static let testValue = UploadStagingClient(
        stageDocuments: { _ in AsyncStream<PickedFile> { $0.finish() } },
        stagePhotos: { _ in AsyncStream<PickedFile> { $0.finish() } },
        stageCameraCapture: { _ in nil },
        discard: { _ in },
        sweepStale: {}
    )

    public static let previewValue = testValue
}

public extension DependencyValues {
    var uploadStaging: UploadStagingClient {
        get { self[UploadStagingClient.self] }
        set { self[UploadStagingClient.self] = newValue }
    }
}
