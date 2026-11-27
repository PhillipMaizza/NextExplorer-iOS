import CoreModels
import DesignSystem
import Localization
import SwiftUI

enum SharePermissionSwitch: CaseIterable, Hashable {
    case download
    case delete
    case createFolders
    case createFiles
    case upload

    static func options(isDirectory: Bool) -> [Self] {
        isDirectory ? allCases : [.download]
    }

    var keyPath: WritableKeyPath<SharePermissions, Bool> {
        switch self {
        case .download: \.canDownload
        case .delete: \.canDelete
        case .createFolders: \.canCreateFolders
        case .createFiles: \.canCreateFiles
        case .upload: \.canUpload
        }
    }

    var title: String {
        switch self {
        case .download: L10n.Common.download
        case .delete: L10n.CreateShare.permissionDelete
        case .createFolders: L10n.CreateShare.permissionCreateFolders
        case .createFiles: L10n.CreateShare.permissionCreateFiles
        case .upload: L10n.CreateShare.permissionUpload
        }
    }

    var icon: Image {
        #if os(macOS)
            switch self {
            case .download: IconKit.macDownload
            case .delete: IconKit.macTrash
            case .createFolders: IconKit.macNewFolder
            case .createFiles: IconKit.macNewFile
            case .upload: IconKit.macUpload
            }
        #else
            switch self {
            case .download: IconKit.download
            case .delete: IconKit.delete
            case .createFolders: IconKit.newFolder
            case .createFiles: IconKit.newFile
            case .upload: IconKit.upload
            }
        #endif
    }
}

extension Share {
    var accessChoice: ShareAccessChoice {
        ShareAccessChoice(accessMode: accessMode, permissions: permissions)
    }
}

extension ShareAccessChoice {
    var title: String {
        switch self {
        case .viewOnly: L10n.CreateShare.accessViewOnly
        case .canDownload: L10n.CreateShare.accessCanDownload
        case .canEdit: L10n.CreateShare.accessCanEdit
        case .custom: L10n.EditShare.custom
        }
    }

    func hint(isDirectory: Bool) -> String {
        switch self {
        case .viewOnly: L10n.CreateShare.accessViewOnlyHint
        case .canDownload: L10n.CreateShare.accessCanDownloadHint
        case .canEdit: isDirectory ? L10n.CreateShare.accessCanEditHint : L10n.CreateShare.accessCanEditFileHint
        case .custom: L10n.CreateShare.accessCustomHint
        }
    }

    var icon: Image {
        #if os(macOS)
            switch self {
            case .viewOnly: IconKit.macEye
            case .canDownload: IconKit.macDownload
            case .canEdit: IconKit.macPencil
            case .custom: IconKit.macSliders
            }
        #else
            switch self {
            case .viewOnly: IconKit.eye
            case .canDownload: IconKit.download
            case .canEdit: IconKit.pencil
            case .custom: IconKit.sliders
            }
        #endif
    }
}
