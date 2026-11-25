import AuthClient
import AuthFeature
import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

extension AppFeature.State {
    /// A signed in session for previews of the windows and sheets the app shell hosts.
    static var previewSignedIn: Self {
        var state = Self()
        state.destination = .authenticated(AuthenticatedFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            user: User.preview
        ))
        return state
    }

    static var previewLocked: Self {
        var state = Self()
        state.destination = .locked(LockFeature.State(account: AccountSummary(
            id: "a",
            username: User.preview.username,
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            isActive: true,
            requireSignIn: RequireSignIn(),
            isLocked: true
        )))
        return state
    }
}

@MainActor
extension StoreOf<AppFeature> {
    static func previewSignedIn(addAccount: Bool = false) -> StoreOf<AppFeature> {
        var state = AppFeature.State.previewSignedIn
        if addAccount {
            state.addAccount = .init()
        }
        return Store(initialState: state) { AppFeature() } withDependencies: {
            $0.filesClient = .previewValue
            $0.authClient = .previewValue
        }
    }

    static func previewLocked() -> StoreOf<AppFeature> {
        Store(initialState: AppFeature.State.previewLocked) { AppFeature() } withDependencies: {
            $0.filesClient = .previewValue
            $0.authClient = .previewValue
        }
    }
}
