#if os(macOS)
    import AppKit
    import CoreModels
    import DesignSystem
    import Localization
    import StoreKit
    import SwiftUI

    private enum Metrics {
        static let iconSize: CGFloat = 88
        static let contentWidth: CGFloat = 520
        static let windowWidth: CGFloat = 600
        static let settingsTopInset: CGFloat = .space48
    }

    /// The Mac's About NextExplorer window (app menu). It works signed out too, unlike the
    /// Settings window and its Info pane.
    public struct MacAboutView: View {
        public static let windowID = "about"

        private let onTip: (@MainActor () -> Void)?
        @State private var isShowingLicenses = false

        public init(onTip: (@MainActor () -> Void)? = nil) {
            self.onTip = onTip
        }

        public var body: some View {
            MacAboutContent(onTip: onTip) { isShowingLicenses = true }
                .padding(.space32)
                .frame(width: Metrics.windowWidth)
                .macLicensesSheet(isPresented: $isShowingLicenses)
        }
    }

    struct MacSettingsInfoPane: View {
        let onTip: @MainActor () -> Void
        let onLicenses: () -> Void

        var body: some View {
            ScrollView {
                MacAboutContent(onTip: onTip, onLicenses: onLicenses)
                    .padding(.top, Metrics.settingsTopInset)
                    .padding(.bottom, .space32)
                    .padding(.horizontal, .space40)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    struct MacAboutContent: View {
        var onTip: (@MainActor () -> Void)?
        let onLicenses: () -> Void

        @Environment(\.requestReview) private var requestReview
        @Environment(\.openURL) private var openURL

        var body: some View {
            VStack(spacing: .space24) {
                identity
                VStack(spacing: .space16) {
                    MacFormGroup {
                        if let onTip {
                            MacFormRow {
                                MacFormIconLabel(L10n.Settings.creditsLikeApp, icon: IconKit.coffee)
                            } control: {
                                Button(L10n.Settings.creditsBuyCoffee, action: onTip)
                                    .buttonStyle(.macDS(.primary, size: .small))
                            }
                        }
                        MacFormLinkRow(L10n.Settings.rowRateApp, icon: IconKit.star) { requestReview() }
                        MacFormLinkRow(L10n.MacSettings.support, icon: IconKit.macSidebarHelp, destination: .external) {
                            openURL(AppLinks.supportMail)
                        }
                    }
                    MacFormGroup {
                        MacFormLinkRow(L10n.Settings.rowPrivacyPolicy, icon: IconKit.shield, destination: .external) {
                            openURL(AppLinks.privacy)
                        }
                        MacFormLinkRow(L10n.Settings.rowTermsOfUse, icon: IconKit.document, destination: .external) {
                            openURL(AppLinks.terms)
                        }
                        MacFormLinkRow(L10n.Settings.rowOpenSourceLicenses, icon: IconKit.kindCode, action: onLicenses)
                    }
                    Text(L10n.Settings.creditsMadeBy)
                        .type(.body3(.regular), style: .secondary)
                }
                .frame(maxWidth: Metrics.contentWidth)
            }
        }

        private var identity: some View {
            VStack(spacing: .space12) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                    .accessibilityHidden(true)
                VStack(spacing: .space4) {
                    Text(AppIdentity.name).type(.display)
                    Text(AppDiagnostics.versionText)
                        .type(.body2(.regular), style: .secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    #Preview("About") {
        MacAboutView(onTip: {})
    }

    #Preview("About, dark") {
        MacAboutView(onTip: {})
            .environment(\.colorScheme, .dark)
    }

    #Preview("About, no tip jar") {
        MacAboutView()
    }

    #Preview("Settings Info") {
        MacSettingsInfoPane(onTip: {}, onLicenses: {})
            .previewCanvas(.settingsWindow)
            .background(Color.macCard)
    }
#endif
