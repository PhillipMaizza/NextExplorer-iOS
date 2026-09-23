#if os(macOS)
    import FilesFeature
    import Localization
    import StoreKit
    import SwiftUI

    /// Mac menu bar additions: a native App Store rating prompt in the app menu, and the support
    /// site in place of the default Help item (the app ships no help book).
    struct NextExplorerCommands: Commands {
        var body: some Commands {
            CommandGroup(after: .appInfo) {
                RateAppButton()
            }
            CommandGroup(replacing: .help) {
                SupportButton()
            }
        }
    }

    /// `requestReview` is only reachable through the environment, so the menu item is a view.
    private struct RateAppButton: View {
        @Environment(\.requestReview) private var requestReview

        var body: some View {
            Button(L10n.Menu.rateApp) { requestReview() }
        }
    }

    private struct SupportButton: View {
        @Environment(\.openURL) private var openURL

        var body: some View {
            Button(L10n.Menu.support) { openURL(AppLinks.support) }
        }
    }
#endif
