import Foundation
import Testing
@testable import Localization

struct L10nTests {

    @Test("a spread of accessors resolve to real catalog entries, not the raw key")
    func accessorsResolve() {
        let pairs: [(key: String, value: String)] = [
            ("common.cancel", L10n.Common.cancel),
            ("common.retry", L10n.Common.retry),
            ("common.logOut", L10n.Common.logOut),
            ("tab.browse", L10n.Tab.browse),
            ("browse.navigationTitle", L10n.Browse.navigationTitle),
            ("browse.action.getInfo", L10n.Browse.actionGetInfo),
            ("changePassword.navigationTitle", L10n.ChangePassword.navigationTitle),
            ("changePassword.error.mismatch", L10n.ChangePassword.errorMismatch),
            ("settings.signOut.alertTitle", L10n.Settings.signOutAlertTitle),
            ("shared.navigationTitle", L10n.Shared.navigationTitle),
            ("userManagement.navigationTitle", L10n.UserManagement.navigationTitle),
            ("userDetail.dangerZone.removeUser", L10n.UserDetail.dangerZoneRemoveUser),
            ("error.network", L10n.Error.network),
            ("login.submit", L10n.Login.submit),
        ]
        for pair in pairs {
            #expect(!pair.value.isEmpty)
            #expect(pair.value != pair.key, "\(pair.key) did not resolve")
        }
    }

    @Test("format accessors interpolate their arguments")
    func formatAccessors() {
        #expect(L10n.ChangePassword.errorMinLength(6) == "Use at least 6 characters.")
        #expect(L10n.Browse.searchNoMatchesInFolder("vac") == "No matches for “vac”.")
        #expect(L10n.Browse.progressDownloadingIndexed(2, 5) == "Downloading 2 of 5…")
        #expect(L10n.Browse.downloadSavedAllTo(3, "iCloud") == "Saved 3 items to iCloud")
    }

    @Test("known values match the English source")
    func englishValues() {
        #expect(L10n.Common.cancel == "Cancel")
        #expect(L10n.Tab.settings == "Settings")
        #expect(L10n.Settings.signOutAlertTitle == "Sign Out?")
    }
}
