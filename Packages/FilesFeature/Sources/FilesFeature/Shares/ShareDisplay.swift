import CoreModels
import Localization

/// Presentation titles for the share enums. Kept out of `CoreModels` so the model layer
/// stays free of user-facing copy.
extension ShareAccessMode {
    var title: String {
        switch self {
        case .readonly: L10n.AccessMode.readonly
        case .readwrite: L10n.AccessMode.readwrite
        }
    }
}

extension ShareTarget {
    var title: String {
        switch self {
        case .anyone: L10n.ShareTarget.anyone
        case .users: L10n.ShareTarget.users
        }
    }
}

extension DirectLinkMode {
    var title: String {
        switch self {
        case .auto: L10n.DirectLinkMode.auto
        case .inline: L10n.DirectLinkMode.inline
        case .raw: L10n.DirectLinkMode.raw
        case .download: L10n.DirectLinkMode.download
        }
    }
}
