import AuthClient
import AuthFeature
import ComposableArchitecture
import DesignSystem
import SwiftUI

private enum Constants {
    static let destinationCrossFadeDuration: Double = 0.35
}

public struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    /// The launch splash sits on top of `destinationContent` and removes itself once its own
    /// animation has cleared — the reducer flips `destination` the moment auth resolves, the
    /// splash just holds the frame until then.
    @State private var isSplashPresented = true

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            destinationContent

            if isSplashPresented {
                SplashView(isReady: store.destination != .loading) {
                    isSplashPresented = false
                }
                .transition(.identity)
                .zIndex(1)
            }
        }
        .task {
            store.send(.onAppear)
        }
        .onChange(of: store.sessionDidExpire) { _, didExpire in
            guard didExpire else { return }
            store.send(.sessionExpiryDetected)
        }
    }

    @ViewBuilder
    private var destinationContent: some View {
        Group {
            switch store.destination {
            case .loading:
                Color.clear
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .backgroundGradient()
                    .ignoresSafeArea()

            case .unauthenticated:
                if let scopedStore = store.scope(state: \.destination.unauthenticated, action: \.destination.unauthenticated) {
                    LoginFormView(store: scopedStore, autoFocus: !isSplashPresented)
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
