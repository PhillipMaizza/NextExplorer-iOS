import Foundation

/// Type safe accessors for the app's user facing strings, backed by the `Localizable` String
/// Catalog in this package. Keys are dotted and domain scoped
/// (`changePassword.navigationTitle`); the Swift API mirrors that as nested enums
/// (`L10n.ChangePassword.navigationTitle`). Strings reused across features live under
/// `L10n.Common`.
///
/// To add a string: add the entry to `Localizable.xcstrings`, then add the matching accessor
/// below.
public enum L10n {
    public enum Common {
        public static var cancel: String { tr("common.cancel") }
        public static var save: String { tr("common.save") }
        public static var retry: String { tr("common.retry") }
        public static var delete: String { tr("common.delete") }
        public static var remove: String { tr("common.remove") }
        public static var done: String { tr("common.done") }
        public static var ok: String { tr("common.ok") }
        public static var logOut: String { tr("common.logOut") }
    }

    public enum ChangePassword {
        public static var navigationTitle: String { tr("changePassword.navigationTitle") }
        public static var intro: String { tr("changePassword.intro") }
        public static var submitButton: String { tr("changePassword.submitButton") }
        public static var success: String { tr("changePassword.success") }
        public static var passwordsDontMatch: String { tr("changePassword.error.mismatch") }
        public static var currentPasswordField: String { tr("changePassword.field.currentPassword") }
        public static var newPasswordLabel: String { tr("changePassword.field.newPasswordLabel") }
        public static var confirmPasswordLabel: String { tr("changePassword.field.confirmPasswordLabel") }
        public static var confirmPasswordField: String { tr("changePassword.field.confirmPassword") }

        /// Placeholder and inline error both name the minimum length.
        public static func newPasswordPrompt(_ minimum: Int) -> String {
            tr("changePassword.field.newPasswordPrompt", minimum)
        }
        public static func minimumLength(_ minimum: Int) -> String {
            tr("changePassword.error.minLength", minimum)
        }
    }

    public enum Settings {
        public enum SignOut {
            public static var alertTitle: String { tr("settings.signOut.alertTitle") }
            public static var message: String { tr("settings.signOut.message") }
        }
    }
}

private func tr(_ key: String) -> String {
    String(localized: String.LocalizationValue(key), table: "Localizable", bundle: .module)
}

private func tr(_ key: String, _ arguments: any CVarArg...) -> String {
    String(format: tr(key), locale: .current, arguments: arguments)
}
