public enum AuthClientConfiguration {
    /// Default session cookie name for NextExplorer's local auth path — assumes
    /// express-session's own default (`connect.sid`). Verify against a live server.
    public enum CookieName {
        public static let local = "connect.sid"
    }

    /// Custom URL scheme the OIDC mobile bridge redirects back to. Must match the backend's
    /// `OIDC_MOBILE_REDIRECT_URIS` allowlist (default `nextexplorer://oidc-callback`).
    /// `ASWebAuthenticationSession` intercepts this scheme itself, so it does not need to be
    /// registered in Info.plist (and registering it would let another app claim it).
    public static let oidcCallbackScheme = "nextexplorer"
}
