import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Photos

/// Where Save to Device puts a file: pictures and videos Photos accepts go to the photo library,
/// everything else goes through the system Save to Files panel.
public enum DeviceSaveDestination: Equatable, Sendable {
    case photos(isVideo: Bool)
    case files

    private static let photoKinds: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "tif", "tiff", "dng"]
    private static let videoKinds: Set<String> = ["mov", "mp4", "m4v"]

    public static func destination(forKind kind: String) -> DeviceSaveDestination {
        let kind = kind.lowercased()
        if photoKinds.contains(kind) {
            return .photos(isVideo: false)
        }
        return videoKinds.contains(kind) ? .photos(isVideo: true) : .files
    }
}

public enum DeviceSaveError: Error, Equatable, Sendable {
    case photosAccessDenied
    case photosSaveFailed
}

/// What a copy that leaves the app needs from the device: staging the downloaded file under its real
/// name, adding it to Photos (add only permission), and removing a staged copy nobody exported.
/// The app keeps nothing once the file has gone to Photos or Files.
public struct DeviceSaver: Sendable {
    public var saveToPhotos: @Sendable (_ url: URL, _ isVideo: Bool) async throws -> Void
    public var stage: @Sendable (_ temporaryURL: URL, _ fileName: String) throws -> URL
    public var discard: @Sendable (_ urls: [URL]) -> Void
    /// Everything still staged, for a sign out, an account removal and the next launch after a kill.
    public var discardAll: @Sendable () -> Void

    public init(
        saveToPhotos: @escaping @Sendable (URL, Bool) async throws -> Void,
        stage: @escaping @Sendable (URL, String) throws -> URL,
        discard: @escaping @Sendable ([URL]) -> Void,
        discardAll: @escaping @Sendable () -> Void = {}
    ) {
        self.saveToPhotos = saveToPhotos
        self.stage = stage
        self.discard = discard
        self.discardAll = discardAll
    }
}

extension DeviceSaver: DependencyKey {
    private static let stagingFolderName = SessionScratchLocation.deviceSaveStaging

    private static var stagingRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(stagingFolderName, isDirectory: true)
    }

    public static let liveValue = DeviceSaver(
        saveToPhotos: { url, isVideo in
            let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard status == .authorized || status == .limited else { throw DeviceSaveError.photosAccessDenied }
            do {
                try await PHPhotoLibrary.shared().performChanges {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: isVideo ? .video : .photo, fileURL: url, options: nil)
                }
            } catch {
                throw DeviceSaveError.photosSaveFailed
            }
        },
        stage: { temporaryURL, fileName in
            let fileManager = FileManager.default
            let folder = stagingRoot.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(SafeFileName.component(fileName))
            try fileManager.moveItem(at: temporaryURL, to: destination)
            return destination
        },
        discard: { urls in
            for url in urls {
                try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
            }
        },
        discardAll: {
            try? FileManager.default.removeItem(at: stagingRoot)
        }
    )

    public static let testValue = DeviceSaver(
        saveToPhotos: { _, _ in throw DeviceSaveError.photosSaveFailed },
        stage: { url, _ in url },
        discard: { _ in }
    )
}

public extension DependencyValues {
    var deviceSaver: DeviceSaver {
        get { self[DeviceSaver.self] }
        set { self[DeviceSaver.self] = newValue }
    }
}
