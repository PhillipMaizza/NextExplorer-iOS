import Foundation

/// The subset of `GET /api/features` this app consumes. Every flag defaults to `false`, so a
/// server that predates a flag — or omits its section — reads as "feature off". Confirmed
/// against `backend/src/routes/features.js`, where each flag is a `{ enabled: Bool }` object.
public struct ServerFeatures: Equatable, Sendable, Decodable {
    public let isUserVolumesEnabled: Bool

    public init(isUserVolumesEnabled: Bool = false) {
        self.isUserVolumesEnabled = isUserVolumesEnabled
    }

    private enum CodingKeys: String, CodingKey {
        case userVolumes
    }

    private struct FlagSection: Decodable {
        let enabled: Bool
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let userVolumes = try container.decodeIfPresent(FlagSection.self, forKey: .userVolumes)
        isUserVolumesEnabled = userVolumes?.enabled ?? false
    }
}
