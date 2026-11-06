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

    public init(
        isUserVolumesEnabled: Bool = false,
        isVolumeUsageEnabled: Bool = false,
        isPersonalEnabled: Bool = false,
        editorExtensions: [String] = []
    ) {
        self.isUserVolumesEnabled = isUserVolumesEnabled
        self.isVolumeUsageEnabled = isVolumeUsageEnabled
        self.isPersonalEnabled = isPersonalEnabled
        self.editorExtensions = editorExtensions
    }

    private enum CodingKeys: String, CodingKey {
        case userVolumes
        case volumeUsage
        case personal
        case editor
    }

    private struct FlagSection: Decodable {
        let enabled: Bool
    }

    private struct EditorSection: Decodable {
        let extensions: [String]?
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
    }
}
