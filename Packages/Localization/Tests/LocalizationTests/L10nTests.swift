import Foundation
@testable import Localization
import Testing

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

    @Test("every string resolves to real text, not its own key, in every language the app ships")
    func everyKeyResolvesInEveryLanguage() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Localization/Resources/Localizable.xcstrings")
        let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let strings = (catalog?["strings"] as? [String: Any]) ?? [:]
        #expect(strings.count > 1000)
        var unresolved: [String] = []
        for language in LocalizationOverride.supportedLanguages {
            LocalizationOverride.withLanguage(language) {
                for key in strings.keys where LocalizationOverride.bundle.localizedString(forKey: key, value: key, table: "Localizable") == key {
                    unresolved.append("\(language)/\(key)")
                }
            }
        }
        #expect(unresolved.isEmpty, "Unresolved: \(unresolved.sorted().prefix(20)) (\(unresolved.count) in all)")
    }

    @Test("layout direction follows the chosen language, else the system language")
    func layoutDirectionFollowsLanguage() {
        let rtl = LocalizationOverride.usesRightToLeftLayout
        #expect(rtl("ar", "en"))
        #expect(rtl("he", nil))
        #expect(!rtl("de", "ar"), "a language picked in the app wins over the system language")
        #expect(rtl(nil, "ar"), "an Arabic system with no in-app choice lays out right to left")
        #expect(rtl(nil, "he"))
        #expect(!rtl(nil, "en"))
        #expect(!rtl(nil, "pt-BR"))
        #expect(!rtl(nil, nil))
    }

    @Test("format accessors interpolate their arguments")
    func formatAccessors() {
        #expect(L10n.ChangePassword.errorMinLength(6) == "Use at least 6 characters.")
        #expect(L10n.Browse.searchNoMatchesInFolder("vac") == "No matches for “vac”.")
        #expect(L10n.DownloadQueue.barTitleOne("movie.mkv") == "Downloading movie.mkv")
        #expect(L10n.DownloadQueue.savedMany(3) == "3 items saved to Downloads")
    }
}
