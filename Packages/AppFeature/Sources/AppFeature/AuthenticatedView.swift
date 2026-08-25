import ComposableArchitecture
import CoreModels
import FilesClient
import FilesFeature
import SwiftUI

public struct AuthenticatedView: View {
    @Bindable var store: StoreOf<AuthenticatedFeature>

    public init(store: StoreOf<AuthenticatedFeature>) {
        self.store = store
    }

    public var body: some View {
        MainTabView(store: store.scope(state: \.mainTab, action: \.mainTab))
    }
}

#Preview {
    AuthenticatedView(
        store: Store(
            initialState: AuthenticatedFeature.State(
                serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
                user: User(id: "preview-user", username: "jdoe", email: "jane.doe@example.com", displayName: "Jane Doe", roles: [])
            )
        ) {
            AuthenticatedFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    )
}
