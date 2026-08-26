import Foundation

/// Mirrors `GET /api/metadata/*`, confirmed against `backend/src/routes/metadata.js`. Unlike
/// `FileItem`, `path` here is the item's *own full* logical path (`resolved.relativePath`),
/// not its parent directory. There is no owner/group/permissions data anywhere in this
/// response — the real server simply doesn't expose OS-level file ownership, only what's
/// below.
public struct FileMetadata: Codable, Equatable, Sendable {
    public let path: String
    public let name: String
    public let kind: String
    public let size: Int64
    public let dateModified: Date
    public let dateCreated: Date
    public let directory: DirectorySummary?
    public let image: ImageMetadata?
    public let video: VideoMetadata?

    public var isDirectory: Bool { kind == "directory" }

    public init(
        path: String,
        name: String,
        kind: String,
        size: Int64,
        dateModified: Date,
        dateCreated: Date,
        directory: DirectorySummary? = nil,
        image: ImageMetadata? = nil,
        video: VideoMetadata? = nil
    ) {
        self.path = path
        self.name = name
        self.kind = kind
        self.size = size
        self.dateModified = dateModified
        self.dateCreated = dateCreated
        self.directory = directory
        self.image = image
        self.video = video
    }

    /// Only present for directories: a recursive scan of everything inside, capped
    /// server-side at 200,000 visited entries (`truncated` flags when that cap was hit).
    public struct DirectorySummary: Codable, Equatable, Sendable {
        public let totalSize: Int64
        public let fileCount: Int
        public let dirCount: Int
        public let truncated: Bool

        public init(totalSize: Int64, fileCount: Int, dirCount: Int, truncated: Bool) {
            self.totalSize = totalSize
            self.fileCount = fileCount
            self.dirCount = dirCount
            self.truncated = truncated
        }
    }

    /// Only present for image files: `sharp` dimensions plus best-effort EXIF (absent
    /// entirely when the file has none, individual fields absent when EXIF lacks them).
    public struct ImageMetadata: Codable, Equatable, Sendable {
        public let width: Int?
        public let height: Int?
        public let orientation: Int?
        public let cameraMake: String?
        public let cameraModel: String?
        public let lensModel: String?
        public let software: String?
        public let dateTaken: Date?
        public let gps: GPSCoordinate?

        public init(
            width: Int? = nil,
            height: Int? = nil,
            orientation: Int? = nil,
            cameraMake: String? = nil,
            cameraModel: String? = nil,
            lensModel: String? = nil,
            software: String? = nil,
            dateTaken: Date? = nil,
            gps: GPSCoordinate? = nil
        ) {
            self.width = width
            self.height = height
            self.orientation = orientation
            self.cameraMake = cameraMake
            self.cameraModel = cameraModel
            self.lensModel = lensModel
            self.software = software
            self.dateTaken = dateTaken
            self.gps = gps
        }

        public struct GPSCoordinate: Codable, Equatable, Sendable {
            public let lat: Double
            public let lon: Double

            public init(lat: Double, lon: Double) {
                self.lat = lat
                self.lon = lon
            }
        }
    }

    /// Only present for video files: dimensions/duration probed via `ffprobe`.
    public struct VideoMetadata: Codable, Equatable, Sendable {
        public let width: Int?
        public let height: Int?
        public let duration: Double?

        public init(width: Int? = nil, height: Int? = nil, duration: Double? = nil) {
            self.width = width
            self.height = height
            self.duration = duration
        }
    }
}
