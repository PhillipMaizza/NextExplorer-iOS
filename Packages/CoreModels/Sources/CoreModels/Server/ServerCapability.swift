import Foundation

/// One optional program a server can use, from `GET /api/capabilities` (admin only). The server
/// also knows what each program enables, but leaves that out of the reply.
public struct ServerCapability: Equatable, Sendable, Decodable, Identifiable {
    public let name: String
    public let isAvailable: Bool
    /// The version the program printed, `nil` when it is missing or said none.
    public let version: String?
    /// `false` when the server does not use the program in its current setup (rsync with the streaming
    /// transfer engine), so its absence costs nothing.
    public let isUsed: Bool
    /// The package that provides it, for an admin installing it.
    public let installPackage: String?
    /// Archive formats the installed archive tool cannot read, such as `rar`.
    public let missingFormats: [String]

    public var id: String {
        name
    }

    public init(
        name: String,
        isAvailable: Bool,
        version: String? = nil,
        isUsed: Bool = true,
        installPackage: String? = nil,
        missingFormats: [String] = []
    ) {
        self.name = name
        self.isAvailable = isAvailable
        self.version = version
        self.isUsed = isUsed
        self.installPackage = installPackage
        self.missingFormats = missingFormats
    }

    private enum CodingKeys: String, CodingKey {
        case name, version, used, install, missingFormats
        case available
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        isAvailable = try container.decodeIfPresent(Bool.self, forKey: .available) ?? false
        version = try container.decodeIfPresent(String.self, forKey: .version)
        isUsed = try container.decodeIfPresent(Bool.self, forKey: .used) ?? true
        installPackage = try container.decodeIfPresent(String.self, forKey: .install)
        missingFormats = try container.decodeIfPresent([String].self, forKey: .missingFormats) ?? []
    }
}

public struct ServerCapabilitiesEnvelope: Decodable, Sendable {
    public let capabilities: [ServerCapability]
}
