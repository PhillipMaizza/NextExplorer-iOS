import Foundation

/// The subset of `GET /api/features` this app consumes. Every flag defaults to `false`, so a
/// server that omits a section reads as "feature off". Verified against
/// `backend/src/routes/features.js`, where each flag is a `{ enabled: Bool }` object.
public struct ServerFeatures: Equatable, Sendable, Decodable {
    public let isUserVolumesEnabled: Bool
    public let isVolumeUsageEnabled: Bool
    /// `personal.enabled` (`USER_DIR_ENABLED`): each account has a private folder reached through
    /// the logical `personal` path, which the root volume listing never includes.
    public let isPersonalEnabled: Bool
    /// `editor.extensions` (`EDITOR_EXTENSIONS`): extra file types the server lets the text editor
    /// open, on top of `EditableTextFiles.defaultExtensions`. Lowercased, without the dot.
    public let editorExtensions: [String]
    /// `uploads.maxChunkSizeBytes` (`MAX_CHUNK_SIZE_MIB`): the ceiling for the chunk size an admin can set.
    public let maxUploadChunkSizeBytes: Int?
    /// `search.index.enabled`, and `search.index.lockedBy` when `SEARCH_INDEX` decided it.
    public let isSearchIndexEnabled: Bool
    public let searchIndexLockedBy: String?
    /// `folderSize.mode`, and `folderSize.lockedBy` when `FOLDER_SIZE_MODE` decided it.
    public let folderSizeMode: FolderSizeMode
    public let folderSizeLockedBy: String?

    public init(
        isUserVolumesEnabled: Bool = false,
        isVolumeUsageEnabled: Bool = false,
        isPersonalEnabled: Bool = false,
        editorExtensions: [String] = [],
        maxUploadChunkSizeBytes: Int? = nil,
        isSearchIndexEnabled: Bool = false,
        searchIndexLockedBy: String? = nil,
        folderSizeMode: FolderSizeMode = .off,
        folderSizeLockedBy: String? = nil
    ) {
        self.isUserVolumesEnabled = isUserVolumesEnabled
        self.isVolumeUsageEnabled = isVolumeUsageEnabled
        self.isPersonalEnabled = isPersonalEnabled
        self.editorExtensions = editorExtensions
        self.maxUploadChunkSizeBytes = maxUploadChunkSizeBytes
        self.isSearchIndexEnabled = isSearchIndexEnabled
        self.searchIndexLockedBy = searchIndexLockedBy
        self.folderSizeMode = folderSizeMode
        self.folderSizeLockedBy = folderSizeLockedBy
    }

    private enum CodingKeys: String, CodingKey {
        case userVolumes
        case volumeUsage
        case personal
        case editor
        case uploads
        case search
        case folderSize
    }

    private struct FlagSection: Decodable {
        let enabled: Bool
    }

    private struct EditorSection: Decodable {
        let extensions: [String]?
    }

    private struct UploadsSection: Decodable {
        let maxChunkSizeBytes: Int?
    }

    private struct SearchSection: Decodable {
        struct Index: Decodable {
            let enabled: Bool?
            let lockedBy: String?
        }

        let index: Index?
    }

    private struct FolderSizeSection: Decodable {
        let mode: String?
        let lockedBy: String?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let userVolumes = try container.decodeIfPresent(FlagSection.self, forKey: .userVolumes)
        let volumeUsage = try container.decodeIfPresent(FlagSection.self, forKey: .volumeUsage)
        isUserVolumesEnabled = userVolumes?.enabled ?? false
        isVolumeUsageEnabled = volumeUsage?.enabled ?? false
        isPersonalEnabled = try container.decodeIfPresent(FlagSection.self, forKey: .personal)?.enabled ?? false
        let editor = try? container.decodeIfPresent(EditorSection.self, forKey: .editor)
        editorExtensions = (editor?.extensions ?? []).map { $0.lowercased() }
        maxUploadChunkSizeBytes = (try? container.decodeIfPresent(UploadsSection.self, forKey: .uploads))?
            .maxChunkSizeBytes
        let searchIndex = (try? container.decodeIfPresent(SearchSection.self, forKey: .search))?.index
        isSearchIndexEnabled = searchIndex?.enabled ?? false
        searchIndexLockedBy = searchIndex?.lockedBy
        let folderSize = try? container.decodeIfPresent(FolderSizeSection.self, forKey: .folderSize)
        folderSizeMode = folderSize?.mode.flatMap(FolderSizeMode.init(rawValue:)) ?? .off
        folderSizeLockedBy = folderSize?.lockedBy
    }
}
