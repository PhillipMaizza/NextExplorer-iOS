import ComposableArchitecture
import DesignSystem
import SwiftUI
#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

struct AppLockLifecycle: ViewModifier {
    let store: StoreOf<AppFeature>
    @Environment(\.scenePhase) private var scenePhase

    #if os(iOS)
        private static let leftNotification = UIApplication.didEnterBackgroundNotification
        private static let returnedNotification = UIApplication.willEnterForegroundNotification
    #elseif os(macOS)
        private static let leftNotification = NSApplication.didResignActiveNotification
        private static let returnedNotification = NSApplication.didBecomeActiveNotification
    #endif

    private var isCovered: Bool {
        #if os(iOS)
            scenePhase != .active && store.shouldCoverWhenInactive
        #elseif os(macOS)
            false
        #endif
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isCovered {
                    PrivacyCover()
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: Self.leftNotification)) { _ in
                store.send(.appLeft)
            }
            .onReceive(NotificationCenter.default.publisher(for: Self.returnedNotification)) { _ in
                store.send(.appReturned)
            }
    }
}

struct PrivacyCover: View {
    var body: some View {
        IconKit.lock
            .resizable()
            .scaledToFit()
            .frame(width: .iconLarge, height: .iconLarge)
            .foregroundStyle(Color.secondaryDS)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .backgroundGradient()
            .accessibilityHidden(true)
    }
}

#Preview("Privacy cover") {
    PrivacyCover()
}
