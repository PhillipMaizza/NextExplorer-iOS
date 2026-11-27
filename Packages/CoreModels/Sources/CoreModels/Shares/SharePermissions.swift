import Foundation

public struct SharePermissions: Equatable, Sendable, Codable {
    public var canDownload: Bool
    public var canDelete: Bool
    public var canCreateFolders: Bool
    public var canCreateFiles: Bool
    public var canUpload: Bool
    public var showsVersions: Bool
    public var canDownloadVersions: Bool

    public init(
        canDownload: Bool = true,
        canDelete: Bool = true,
        canCreateFolders: Bool = true,
        canCreateFiles: Bool = true,
        canUpload: Bool = true,
        showsVersions: Bool = false,
        canDownloadVersions: Bool = false
    ) {
        self.canDownload = canDownload
        self.canDelete = canDelete
        self.canCreateFolders = canCreateFolders
        self.canCreateFiles = canCreateFiles
        self.canUpload = canUpload
        self.showsVersions = showsVersions
        self.canDownloadVersions = canDownloadVersions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        canDownload = try container.decodeIfPresent(Bool.self, forKey: .canDownload) ?? true
        canDelete = try container.decodeIfPresent(Bool.self, forKey: .canDelete) ?? true
        canCreateFolders = try container.decodeIfPresent(Bool.self, forKey: .canCreateFolders) ?? true
        canCreateFiles = try container.decodeIfPresent(Bool.self, forKey: .canCreateFiles) ?? true
        canUpload = try container.decodeIfPresent(Bool.self, forKey: .canUpload) ?? true
        showsVersions = try container.decodeIfPresent(Bool.self, forKey: .showsVersions) ?? false
        canDownloadVersions = try container.decodeIfPresent(Bool.self, forKey: .canDownloadVersions) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(canDownload, forKey: .canDownload)
        try container.encode(canDelete, forKey: .canDelete)
        try container.encode(canCreateFolders, forKey: .canCreateFolders)
        try container.encode(canCreateFiles, forKey: .canCreateFiles)
        try container.encode(canUpload, forKey: .canUpload)
        try container.encode(showsVersions, forKey: .showsVersions)
        try container.encode(showsVersions && canDownloadVersions, forKey: .canDownloadVersions)
    }

    private enum CodingKeys: String, CodingKey {
        case canDownload = "allowDownload"
        case canDelete = "allowDelete"
        case canCreateFolders = "allowCreateFolder"
        case canCreateFiles = "allowCreateFile"
        case canUpload = "allowUpload"
        case showsVersions = "versionsVisible"
        case canDownloadVersions = "versionsDownload"
    }

    public static func defaults(for target: ShareTarget) -> SharePermissions {
        SharePermissions(showsVersions: target == .users, canDownloadVersions: target == .users)
    }

    public func effective(for accessMode: ShareAccessMode) -> SharePermissions {
        guard accessMode == .readonly else { return self }
        var permissions = self
        permissions.canDelete = false
        permissions.canCreateFolders = false
        permissions.canCreateFiles = false
        permissions.canUpload = false
        return permissions
    }

    var allowsEveryChange: Bool {
        canDownload && canDelete && canCreateFolders && canCreateFiles && canUpload
    }
}

public enum ShareAccessChoice: CaseIterable, Hashable, Sendable {
    case viewOnly
    case canDownload
    case canEdit
    case custom

    public init(accessMode: ShareAccessMode, permissions: SharePermissions) {
        switch accessMode {
        case .readonly:
            self = permissions.canDownload ? .canDownload : .viewOnly
        case .readwrite:
            self = permissions.allowsEveryChange ? .canEdit : .custom
        }
    }

    public static func options(isDirectory: Bool, current: ShareAccessChoice) -> [ShareAccessChoice] {
        isDirectory || current == .custom ? allCases : [.viewOnly, .canDownload, .canEdit]
    }

    public var accessMode: ShareAccessMode {
        switch self {
        case .viewOnly, .canDownload: .readonly
        case .canEdit, .custom: .readwrite
        }
    }

    public func applied(to permissions: SharePermissions, from previous: ShareAccessChoice) -> SharePermissions {
        var permissions = permissions
        switch self {
        case .viewOnly:
            permissions.canDownload = false
        case .canDownload:
            permissions.canDownload = true
        case .canEdit:
            permissions.canDownload = true
            permissions.canDelete = true
            permissions.canCreateFolders = true
            permissions.canCreateFiles = true
            permissions.canUpload = true
        case .custom:
            permissions = permissions.effective(for: previous.accessMode)
        }
        return permissions
    }
}
