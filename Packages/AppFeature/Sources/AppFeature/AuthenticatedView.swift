import ComposableArchitecture
import DesignSystem
import SwiftUI

public struct AuthenticatedView: View {
    @Bindable var store: StoreOf<AuthenticatedFeature>

    public init(store: StoreOf<AuthenticatedFeature>) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: .space16) {
            Spacer()

            VStack(spacing: .space4) {
                Text("You're in").type(.headline1, style: .primary)
                Text(store.username).type(.body1, style: .secondary)
                if let host = store.serverURL.host {
                    Text(host).type(.label1, style: .secondary)
                }
            }

            Spacer()

            Button {
                store.send(.signOutButtonTapped)
            } label: {
                if store.isSigningOut {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Text("Sign Out").type(.body2).frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.bordered)
            .disabled(store.isSigningOut)
        }
        .padding(.space16)
        .background(Color.backgroundPrimary)
    }
}

#Preview {
    AuthenticatedView(
        store: Store(
            initialState: AuthenticatedFeature.State(
                serverURL: URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/"),
                username: "phillip"
            )
        ) {
            AuthenticatedFeature()
        }
    )
}
