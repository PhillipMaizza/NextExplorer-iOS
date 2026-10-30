import AuthClient
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
            user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe")
        ))
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
}
