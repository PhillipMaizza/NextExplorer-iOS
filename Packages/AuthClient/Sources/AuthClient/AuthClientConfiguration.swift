public enum AuthClientConfiguration {
    /// Default session cookie name for NextExplorer's local auth path — assumes
    /// express-session's own default (`connect.sid`). Verify against a live server.
    public enum CookieName {
        public static let local = "connect.sid"
    }
}
