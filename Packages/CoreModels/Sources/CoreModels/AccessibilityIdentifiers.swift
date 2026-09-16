/// Stable accessibility identifiers shared between the views that set them and the XCUITest
/// target that queries them. Identifiers stay constant across localizations, so tests never
/// key off translated visible text.
public enum AccessibilityIdentifiers {
    public enum Tab {
        public static let browse = "tab.browse"
        public static let favorites = "tab.favorites"
        public static let shared = "tab.shared"
        public static let downloads = "tab.downloads"
        public static let settings = "tab.settings"
    }

    public enum Login {
        public static let hostField = "login.hostField"
        public static let testConnectionButton = "login.testConnectionButton"
        public static let emailField = "login.emailField"
        public static let passwordField = "login.passwordField"
        public static let passwordFieldVisible = "login.passwordFieldVisible"
        public static let submitButton = "login.submitButton"
    }

    public enum Search {
        public static let field = "search.field"
    }

    public enum Browse {
        public static let uploadMenu = "browse.uploadMenu"
        public static let moreMenu = "browse.moreMenu"
    }
}
