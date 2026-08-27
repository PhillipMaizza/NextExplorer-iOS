import AuthClient
import AuthFeature
import ComposableArchitecture
import SwiftUI

private enum Constants {
    static let destinationCrossFadeDuration: Double = 0.35
}

public struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        Group {
            switch store.destination {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .backgroundGradient()
                    .transition(.opacity)

            case .unauthenticated:
                if let scopedStore = store.scope(state: \.destination.unauthenticated, action: \.destination.unauthenticated) {
                    LoginFormView(store: scopedStore)
                        .transition(.opacity)
                }

            case .authenticated:
                if let scopedStore = store.scope(state: \.destination.authenticated, action: \.destination.authenticated) {
                    AuthenticatedView(store: scopedStore)
                        .transition(.opacity)
                }
            }
        }
        .animation(.easeInOut(duration: Constants.destinationCrossFadeDuration), value: store.destination)
        .task {
            store.send(.onAppear)
        }
        .onChange(of: store.sessionDidExpire) { _, didExpire in
            guard didExpire else { return }
            store.send(.sessionExpiryDetected)
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
