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
        public static let clientCertificateButton = "login.clientCertificateButton"
        public static let identifierField = "login.identifierField"
        public static let passwordField = "login.passwordField"
        public static let passwordFieldVisible = "login.passwordFieldVisible"
        public static let submitButton = "login.submitButton"
        public static let codeField = "login.codeField"
        public static let codeSubmitButton = "login.codeSubmitButton"
        public static let codeModeButton = "login.codeModeButton"
        public static let diagnosticsButton = "login.diagnosticsButton"
    }

    public enum Search {
        public static let field = "search.field"
    }

    public enum Browse {
        public static let uploadMenu = "browse.uploadMenu"
        public static let moreMenu = "browse.moreMenu"
    }

    public enum Settings {
        /// The active account row, which expands to reveal Change Password / Sign Out.
        public static let activeAccount = "settings.activeAccount"
        /// The app language picker in the Mac Settings window.
        public static let languagePicker = "settings.languagePicker"
        public static let twoFactorRow = "settings.twoFactorRow"
        public static let apiTokensRow = "settings.apiTokensRow"
        public static let apiTokenNameField = "settings.apiTokenNameField"
        public static let twoFactorCodeField = "settings.twoFactorCodeField"
        /// A root row that opens one section page ("general", "offline", ...).
        public static func page(_ name: String) -> String {
            "settings.page." + name
        }
    }
}
