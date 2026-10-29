import CoreModels
import Foundation
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

/// The two links a share hands out, as the web builds them: the share page and the direct
/// file (or folder zip) endpoint.
extension Share {
    func shareLink(serverURL: URL) -> String {
        "\(Self.origin(of: serverURL))/share/\(shareToken)"
    }

    func directLink(serverURL: URL, mode: DirectLinkMode) -> String {
        let base = "\(Self.origin(of: serverURL))/api/share/\(shareToken)/file"
        return mode == .auto ? base : "\(base)?mode=\(mode.rawValue)"
    }

    private static func origin(of serverURL: URL) -> String {
        if let scheme = serverURL.scheme, let host = serverURL.host {
            let port = serverURL.port.map { ":\($0)" } ?? ""
            return "\(scheme)://\(host)\(port)"
        }
        return serverURL.absoluteString
    }
}
