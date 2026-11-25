/// Stable accessibility identifiers shared between the views that set them and the XCUITest
/// target that queries them. Identifiers stay constant across localizations, so tests never
/// key off translated visible text.
public enum AccessibilityIdentifiers {
    public enum Media {
        /// The player of a video or audio file, in the gallery and full screen.
        public static let player = "media.player"
    }

    public enum Tab {
        public static let browse = "tab.browse"
        public static let favorites = "tab.favorites"
        public static let shared = "tab.shared"
        public static let downloads = "tab.downloads"
        public static let settings = "tab.settings"
        public static let trash = "tab.trash"
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

    public enum Lock {
        public static let screen = "lock.screen"
        public static let unlockButton = "lock.unlockButton"
        public static let signOutButton = "lock.signOutButton"
        public static let problem = "lock.problem"
    }

    public enum Search {
        public static let field = "search.field"
        /// The Mac search panel's text field.
        public static let spotlightField = "search.spotlightField"
    }

    public enum Alert {
        public static let confirm = "alert.confirm"
    }

    public enum Toast {
        public static let message = "toast.message"
        public static let close = "toast.close"
    }

    public enum Offline {
        /// The select mode bar's Remove from Offline button.
        public static let removeSelection = "offline.removeSelection"
    }

    public enum Share {
        /// The system share sheet's host, which the app controls: the sheet's own list loads out of process.
        public static let sheet = "share.sheet"
    }

    public enum Shared {
        /// One circle in the people row, by `all`, `anyone` or `person.<id>`.
        public static func filter(_ suffix: String) -> String {
            "shared.filter.\(suffix)"
        }

        /// A share page's Delete, apart from the confirm button of the same name.
        public static let deleteShare = "shared.deleteShare"
        /// The Edit page's Save check in the navigation bar.
        public static let saveEdit = "shared.saveEdit"
        /// The Edit page's People row, which pushes the people picker.
        public static let editPeople = "shared.editPeople"
        public static let editLabel = "shared.editLabel"
    }

    public enum Browse {
        public static let uploadMenu = "browse.uploadMenu"
        public static let moreMenu = "browse.moreMenu"
        public static let gridSettingsButton = "browse.gridSettingsButton"
        public static let trashButton = "browse.trashButton"
        public static let peekCard = "browse.peekCard"
        /// Every type chip over a folder or search results, so row lookups can skip a chip named like a folder.
        public static let filterChip = "browse.filterChip"
    }

    public enum Settings {
        /// The active account row, which expands to reveal Change Password / Sign Out.
        public static let activeAccount = "settings.activeAccount"
        public static let languagePicker = "settings.languagePicker"
        public static let twoFactorRow = "settings.twoFactorRow"
        public static let requireSignInRow = "settings.requireSignInRow"
        public static let requireSignInToggle = "settings.requireSignInToggle"
        public static let apiTokensRow = "settings.apiTokensRow"
        public static let apiTokenNameField = "settings.apiTokenNameField"
        public static let twoFactorCodeField = "settings.twoFactorCodeField"
        /// The section pages the Settings root opens.
        public enum Page: String, CaseIterable, Sendable {
            case general
            case display
            case sharedFiles
            case storage
            case offline
            case administration
            case users
            case support
            case legal
            case licenses
        }

        /// A root row that opens one section page.
        public static func page(_ page: Page) -> String {
            "settings.page." + page.rawValue
        }
    }
}
