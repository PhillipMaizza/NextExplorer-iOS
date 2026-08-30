import AuthClient
import AuthFeature
import ComposableArchitecture
import DesignSystem
import SwiftUI

private enum Constants {
    static let destinationCrossFadeDuration: Double = 0.35
    /// After the login button's accent circle has flooded the screen, `AppView` holds that
    /// same accent fill and fades it out, uncovering the app that cross-faded in behind it.
    static let authFillFadeDuration: Double = 0.4
}

public struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    /// The launch splash sits on top of `destinationContent` and removes itself once its own
    /// animation has cleared — the reducer flips `destination` the moment auth resolves, the
    /// splash just holds the frame until then.
    @State private var isSplashPresented = true
    /// Opacity of the full-screen accent layer that takes over from `LoginFormView`'s
    /// expanding button circle, then fades to reveal the authenticated app.
    @State private var authFillOpacity: Double = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(store: StoreOf<AppFeature>) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            destinationContent

            if authFillOpacity > 0 {
                Color.accent
                    .ignoresSafeArea()
                    .opacity(authFillOpacity)
                    .allowsHitTesting(false)
                    .zIndex(2)
            }

            if isSplashPresented {
                SplashView(isReady: store.destination != .loading) {
                    isSplashPresented = false
                }
                .transition(.identity)
                .zIndex(3)
            }
        }
        .onChange(of: store.didAuthenticateFromLogin) { _, fromLogin in
            guard fromLogin, !reduceMotion else {
                authFillOpacity = 0
                return
            }
            // The login button's circle has just filled the screen with accent; pick that up
            // seamlessly, then fade it out over the app.
            authFillOpacity = 1
            withAnimation(.easeOut(duration: Constants.authFillFadeDuration)) {
                authFillOpacity = 0
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
