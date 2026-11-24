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

#if os(macOS)
    extension PermissionScope {
        var macTitle: String {
            self == .others ? L10n.Permissions.scopeEveryone : title
        }
    }

    extension PermissionRight {
        func macTitle(isDirectory: Bool) -> String {
            guard self == .execute else { return title }
            return isDirectory ? L10n.Permissions.rightOpen : L10n.Permissions.rightRun
        }
    }
#endif
