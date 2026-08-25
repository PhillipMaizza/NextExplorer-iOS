import AuthClient
import AuthFeature
import ComposableArchitecture
import SwiftUI

public struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            switch store.state.destination {
            case .unauthenticated:
                if let scopedStore = store.scope(state: \.destination.unauthenticated, action: \.destination.unauthenticated) {
                    LoginFormView(store: scopedStore)
                }
            case .authenticated:
                if let scopedStore = store.scope(state: \.destination.authenticated, action: \.destination.authenticated) {
                    AuthenticatedView(store: scopedStore)
                }
            }
        }
        .task {
            store.send(.onAppear)
        }
    }
}

#Preview {
    AppView(
        store: Store(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.authClient = .previewValue
        }
    )
}
