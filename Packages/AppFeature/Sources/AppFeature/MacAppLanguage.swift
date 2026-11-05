#if os(macOS)
    import AppStorageKeys
    import Localization
    import SwiftUI

    public extension View {
        /// For a Mac window outside `AppView` (Settings, extra Browse windows, About): rebuilds
        /// it when the app language changes, with the chosen locale and reading direction, so it
        /// never stays in the previous language. The TCA state lives outside the view tree.
        func followsAppLanguage() -> some View {
            modifier(AppLanguageFollower())
        }
    }

    private struct AppLanguageFollower: ViewModifier {
        @AppStorage(AppStorageKeys.appLanguage) private var appLanguage = ""

        func body(content: Content) -> some View {
            let language = appLanguage.isEmpty ? nil : appLanguage
            content
                .environment(\.locale, language.map(Locale.init(identifier:)) ?? .autoupdatingCurrent)
                .environment(\.layoutDirection, language.map(LocalizationOverride.isRTL) == true ? .rightToLeft : .leftToRight)
                .id(appLanguage)
        }
    }

    #Preview {
        Text(verbatim: "Follows the app language")
            .padding()
            .followsAppLanguage()
    }
#endif
