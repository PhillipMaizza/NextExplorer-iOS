import Foundation
import Testing
@testable import Localization

struct L10nTests {

    @Test("every accessor resolves to a catalog entry, not the raw key")
    func accessorsResolve() {
        let pairs: [(key: String, value: String)] = [
            ("common.cancel", L10n.Common.cancel),
            ("common.save", L10n.Common.save),
            ("common.retry", L10n.Common.retry),
            ("common.delete", L10n.Common.delete),
            ("common.remove", L10n.Common.remove),
            ("common.done", L10n.Common.done),
            ("common.ok", L10n.Common.ok),
            ("common.logOut", L10n.Common.logOut),
            ("changePassword.navigationTitle", L10n.ChangePassword.navigationTitle),
            ("changePassword.intro", L10n.ChangePassword.intro),
            ("changePassword.submitButton", L10n.ChangePassword.submitButton),
            ("changePassword.success", L10n.ChangePassword.success),
            ("changePassword.error.mismatch", L10n.ChangePassword.passwordsDontMatch),
            ("changePassword.field.currentPassword", L10n.ChangePassword.currentPasswordField),
            ("changePassword.field.newPasswordLabel", L10n.ChangePassword.newPasswordLabel),
            ("changePassword.field.confirmPasswordLabel", L10n.ChangePassword.confirmPasswordLabel),
            ("changePassword.field.confirmPassword", L10n.ChangePassword.confirmPasswordField),
            ("settings.signOut.alertTitle", L10n.Settings.SignOut.alertTitle),
            ("settings.signOut.message", L10n.Settings.SignOut.message),
        ]
        for pair in pairs {
            #expect(!pair.value.isEmpty)
            #expect(pair.value != pair.key, "\(pair.key) did not resolve")
        }
    }

    @Test("format accessors interpolate their argument")
    func formatAccessorsInterpolate() {
        #expect(L10n.ChangePassword.minimumLength(6) == "Use at least 6 characters.")
        #expect(L10n.ChangePassword.newPasswordPrompt(6) == "At least 6 characters")
    }

    @Test("known values match the English source")
    func englishValues() {
        #expect(L10n.Common.cancel == "Cancel")
        #expect(L10n.Common.retry == "Try Again")
        #expect(L10n.ChangePassword.navigationTitle == "Change Password")
        #expect(L10n.Settings.SignOut.alertTitle == "Sign Out?")
    }
}
