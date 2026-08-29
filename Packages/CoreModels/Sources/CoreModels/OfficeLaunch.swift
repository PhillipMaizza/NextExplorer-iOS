import Foundation

/// Everything the client needs to host an ONLYOFFICE editing session, from
/// `POST /api/onlyoffice/config`. The Document Server itself fetches and saves the file
/// (via signed URLs baked into `config`), so the app only has to load the editor.
public struct OnlyOfficeLaunch: Equatable, Sendable {
    /// The ONLYOFFICE Document Server origin. `web-apps/apps/api/documents/api.js` under it
    /// is the script that renders the editor.
    public let documentServerURL: URL

    /// The `config` object handed verbatim to `DocsAPI.DocEditor`. Kept as raw JSON because
    /// it carries a server-signed `token` that must not be reshaped.
    public let configJSON: Data

    public init(documentServerURL: URL, configJSON: Data) {
        self.documentServerURL = documentServerURL
        self.configJSON = configJSON
    }
}

/// From `POST /api/collabora/config`. `url` is a complete Collabora Online iframe URL with
/// `WOPISrc` and `access_token` already in its query string, ready to load directly.
public struct CollaboraLaunch: Equatable, Sendable {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }
}
