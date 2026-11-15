import Foundation

/// The `uploads` object of `GET /api/settings` (admin only). Mirrors `sanitizeUploads` in the
/// backend's `settingsService.js`: chunked uploads and the auto fallback are mutually exclusive.
public struct UploadSettings: Equatable, Sendable, Codable {
    public static let bytesPerMiB = 1024 * 1024
    public static let minChunkSizeMiB = 1
    public static let fallbackMaxChunkSizeMiB = 512
    public static let defaultChunkSizeMiB = 8

    public var isChunkedEnabled: Bool
    public var isChunkedAutoFallback: Bool
    public var chunkSizeBytes: Int

    public init(
        isChunkedEnabled: Bool = false,
        isChunkedAutoFallback: Bool = false,
        chunkSizeBytes: Int = defaultChunkSizeMiB * bytesPerMiB
    ) {
        self.isChunkedEnabled = isChunkedEnabled
        self.isChunkedAutoFallback = isChunkedAutoFallback
        self.chunkSizeBytes = chunkSizeBytes
    }

    private enum CodingKeys: String, CodingKey {
        case chunkedEnabled, chunkedAutoFallback, chunkSizeBytes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = UploadSettings()
        isChunkedEnabled = try container.decodeIfPresent(Bool.self, forKey: .chunkedEnabled)
            ?? defaults.isChunkedEnabled
        isChunkedAutoFallback = try container.decodeIfPresent(Bool.self, forKey: .chunkedAutoFallback)
            ?? defaults.isChunkedAutoFallback
        chunkSizeBytes = try container.decodeIfPresent(Int.self, forKey: .chunkSizeBytes) ?? defaults.chunkSizeBytes
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(isChunkedEnabled, forKey: .chunkedEnabled)
        try container.encode(isChunkedAutoFallback, forKey: .chunkedAutoFallback)
        try container.encode(chunkSizeBytes, forKey: .chunkSizeBytes)
    }

    /// The chunk size in whole MiB, kept within `1...maxMiB` the way the web page does.
    public func chunkSizeMiB(maxMiB: Int) -> Int {
        guard chunkSizeBytes > 0 else { return min(Self.defaultChunkSizeMiB, maxMiB) }
        let mib = Int((Double(chunkSizeBytes) / Double(Self.bytesPerMiB)).rounded())
        return max(Self.minChunkSizeMiB, min(maxMiB, mib))
    }
}

/// The `ffmpeg` object of `GET /api/settings`. An empty path means the server's default binary.
public struct FFmpegSettings: Equatable, Sendable, Codable {
    public var ffmpegPath: String
    public var ffprobePath: String

    public init(ffmpegPath: String = "", ffprobePath: String = "") {
        self.ffmpegPath = ffmpegPath
        self.ffprobePath = ffprobePath
    }

    private enum CodingKeys: String, CodingKey {
        case ffmpegPath, ffprobePath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ffmpegPath = try container.decodeIfPresent(String.self, forKey: .ffmpegPath) ?? ""
        ffprobePath = try container.decodeIfPresent(String.self, forKey: .ffprobePath) ?? ""
    }

    /// The server only accepts absolute paths; an empty field is allowed and clears the override.
    public var isValid: Bool {
        [ffmpegPath, ffprobePath].allSatisfy { $0.isEmpty || $0.hasPrefix("/") }
    }

    /// Encoded as `null` when empty, which is how the web page clears an override.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if ffmpegPath.isEmpty {
            try container.encodeNil(forKey: .ffmpegPath)
        } else {
            try container.encode(ffmpegPath, forKey: .ffmpegPath)
        }
        if ffprobePath.isEmpty {
            try container.encodeNil(forKey: .ffprobePath)
        } else {
            try container.encode(ffprobePath, forKey: .ffprobePath)
        }
    }
}

/// How far a folder size count goes (`folderSize.mode`).
public enum FolderSizeMode: String, CaseIterable, Sendable, Codable {
    case off
    case shallow
    case full
}

/// The folders a background feature (folder sizes, the search index) is told to leave alone.
/// `environmentExcludedPaths` come from the server's environment and cannot be edited here.
public struct ExcludedPaths: Equatable, Sendable, Decodable {
    public var paths: [String]
    public var environmentPaths: [String]

    public init(paths: [String] = [], environmentPaths: [String] = []) {
        self.paths = paths
        self.environmentPaths = environmentPaths
    }

    private enum CodingKeys: String, CodingKey {
        case excludedPaths, environmentExcludedPaths
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        paths = try container.decodeIfPresent([String].self, forKey: .excludedPaths) ?? []
        environmentPaths = try container.decodeIfPresent([String].self, forKey: .environmentExcludedPaths) ?? []
    }

    /// Adds a path the way the web page does: leading slashes dropped, blanks and duplicates
    /// (including paths the environment already excludes) ignored, the list kept sorted.
    public func adding(_ rawPath: String) -> [String] {
        let path = String(rawPath.trimmingCharacters(in: .whitespacesAndNewlines).drop(while: { $0 == "/" }))
        guard !path.isEmpty, !paths.contains(path), !environmentPaths.contains(path) else { return paths }
        return (paths + [path]).sorted { $0.localizedCompare($1) == .orderedAscending }
    }
}

/// The `searchIndex` object of `GET /api/settings`.
public struct SearchIndexSettings: Equatable, Sendable, Decodable {
    public var isEnabled: Bool
    public var excluded: ExcludedPaths

    public init(isEnabled: Bool = false, excluded: ExcludedPaths = ExcludedPaths()) {
        self.isEnabled = isEnabled
        self.excluded = excluded
    }

    private enum CodingKeys: String, CodingKey {
        case enabled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        excluded = try ExcludedPaths(from: decoder)
    }
}

/// The `folderSize` object of `GET /api/settings`.
public struct FolderSizeSettings: Equatable, Sendable, Decodable {
    public var mode: FolderSizeMode
    public var excluded: ExcludedPaths

    public init(mode: FolderSizeMode = .off, excluded: ExcludedPaths = ExcludedPaths()) {
        self.mode = mode
        self.excluded = excluded
    }

    private enum CodingKeys: String, CodingKey {
        case mode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decodeIfPresent(String.self, forKey: .mode)
        mode = raw.flatMap(FolderSizeMode.init(rawValue:)) ?? .off
        excluded = try ExcludedPaths(from: decoder)
    }
}

/// What `PATCH /api/settings` is sent. Only the sections set are encoded, and the server merges
/// each one, so a switch can move without touching the excluded paths and the other way round.
public struct SystemSettingsPatch: Equatable, Sendable, Encodable {
    public var uploads: UploadSettings?
    public var ffmpeg: FFmpegPatch?
    public var searchIndex: SearchIndexPatch?
    public var folderSize: FolderSizePatch?
    public var activity: ActivitySettings?
    public var trash: TrashSettings?
    public var versions: VersionsSettings?

    public init(
        uploads: UploadSettings? = nil,
        ffmpeg: FFmpegPatch? = nil,
        searchIndex: SearchIndexPatch? = nil,
        folderSize: FolderSizePatch? = nil,
        activity: ActivitySettings? = nil,
        trash: TrashSettings? = nil,
        versions: VersionsSettings? = nil
    ) {
        self.uploads = uploads
        self.ffmpeg = ffmpeg
        self.searchIndex = searchIndex
        self.folderSize = folderSize
        self.activity = activity
        self.trash = trash
        self.versions = versions
    }

    /// Only the paths that changed are sent, because the server checks every path it is sent
    /// (it must exist and be executable), including one the admin did not touch. A path left
    /// `nil` is not sent, and an empty one is sent as `null` to clear it.
    public struct FFmpegPatch: Equatable, Sendable, Encodable {
        public var ffmpegPath: String?
        public var ffprobePath: String?

        public init(ffmpegPath: String? = nil, ffprobePath: String? = nil) {
            self.ffmpegPath = ffmpegPath
            self.ffprobePath = ffprobePath
        }

        private enum CodingKeys: String, CodingKey {
            case ffmpegPath, ffprobePath
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            for (key, path) in [(CodingKeys.ffmpegPath, ffmpegPath), (.ffprobePath, ffprobePath)] {
                guard let path else { continue }
                if path.isEmpty {
                    try container.encodeNil(forKey: key)
                } else {
                    try container.encode(path, forKey: key)
                }
            }
        }
    }

    public struct SearchIndexPatch: Equatable, Sendable, Encodable {
        public var enabled: Bool?
        public var excludedPaths: [String]?

        public init(enabled: Bool? = nil, excludedPaths: [String]? = nil) {
            self.enabled = enabled
            self.excludedPaths = excludedPaths
        }
    }

    public struct FolderSizePatch: Equatable, Sendable, Encodable {
        public var mode: FolderSizeMode?
        public var excludedPaths: [String]?

        public init(mode: FolderSizeMode? = nil, excludedPaths: [String]? = nil) {
            self.mode = mode
            self.excludedPaths = excludedPaths
        }
    }
}
