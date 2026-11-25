import CoreModels
import Foundation

extension SettingsFeature.State {
    /// A signed in admin on an example server, for previews.
    static var preview: Self {
        Self(
            serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
            user: User.previewAdmin
        )
    }

    static var previewRequiringSignIn: Self {
        let state = preview
        state.$accounts.withLock {
            $0 = [
                AccountSummary(
                    id: SessionCredentials.accountID(serverURL: state.serverURL, username: state.user.username),
                    username: state.user.username,
                    serverURL: state.serverURL,
                    isActive: true,
                    requireSignIn: RequireSignIn()
                ),
            ]
        }
        return state
    }
}
