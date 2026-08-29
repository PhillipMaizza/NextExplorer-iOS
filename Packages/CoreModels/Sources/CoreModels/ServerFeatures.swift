import Foundation

/// The subset of `GET /api/features` this app consumes. Every flag defaults to `false`, so a
/// server that omits a section reads as "feature off". Verified against
/// `backend/src/routes/features.js`, where each flag is a `{ enabled: Bool }` object and the
/// office sections are `{ enabled: Bool, extensions: [String] }`.
public struct ServerFeatures: Equatable, Sendable, Decodable {
    public let isUserVolumesEnabled: Bool
    public let isVolumeUsageEnabled: Bool
    public let office: OfficeEditors

    public init(
        isUserVolumesEnabled: Bool = false,
        isVolumeUsageEnabled: Bool = false,
        office: OfficeEditors = OfficeEditors()
    ) {
        self.isUserVolumesEnabled = isUserVolumesEnabled
        self.isVolumeUsageEnabled = isVolumeUsageEnabled
        self.office = office
    }

    /// `@Shared(.inMemory(...))` key: the flags `MainTabFeature` fetches once per session so
    /// the browse tab can decide whether to offer an office editor for a document.
    public static let sharedKey = "serverFeatures"

    /// The two independent web-based office editors the backend can proxy. A given server
    /// runs one, the other, both, or neither.
    public struct OfficeEditors: Equatable, Sendable {
        public let isOnlyOfficeEnabled: Bool
        public let onlyOfficeExtensions: [String]
        public let isCollaboraEnabled: Bool
        public let collaboraExtensions: [String]

        public init(
            isOnlyOfficeEnabled: Bool = false,
            onlyOfficeExtensions: [String] = [],
            isCollaboraEnabled: Bool = false,
            collaboraExtensions: [String] = []
        ) {
            self.isOnlyOfficeEnabled = isOnlyOfficeEnabled
            self.onlyOfficeExtensions = onlyOfficeExtensions
            self.isCollaboraEnabled = isCollaboraEnabled
            self.collaboraExtensions = collaboraExtensions
        }
    }

    private enum CodingKeys: String, CodingKey {
        case userVolumes
        case volumeUsage
        case onlyoffice
        case collabora
    }

    private struct FlagSection: Decodable {
        let enabled: Bool
    }

    private struct OfficeSection: Decodable {
        let enabled: Bool
        let extensions: [String]?
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let userVolumes = try container.decodeIfPresent(FlagSection.self, forKey: .userVolumes)
        let volumeUsage = try container.decodeIfPresent(FlagSection.self, forKey: .volumeUsage)
        isUserVolumesEnabled = userVolumes?.enabled ?? false
        isVolumeUsageEnabled = volumeUsage?.enabled ?? false

        let onlyOffice = try container.decodeIfPresent(OfficeSection.self, forKey: .onlyoffice)
        let collabora = try container.decodeIfPresent(OfficeSection.self, forKey: .collabora)
        office = OfficeEditors(
            isOnlyOfficeEnabled: onlyOffice?.enabled ?? false,
            onlyOfficeExtensions: onlyOffice?.extensions ?? [],
            isCollaboraEnabled: collabora?.enabled ?? false,
            collaboraExtensions: collabora?.extensions ?? []
        )
    }
}
