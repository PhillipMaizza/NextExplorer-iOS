import CoreModels
import Localization

extension PermissionScope {
    var title: String {
        switch self {
        case .owner: L10n.Permissions.scopeOwner
        case .group: L10n.Permissions.scopeGroup
        case .others: L10n.Permissions.scopeOthers
        }
    }
}

extension PermissionRight {
    var title: String {
        switch self {
        case .read: L10n.Permissions.rightRead
        case .write: L10n.Permissions.rightWrite
        case .execute: L10n.Permissions.rightExecute
        }
    }
}
