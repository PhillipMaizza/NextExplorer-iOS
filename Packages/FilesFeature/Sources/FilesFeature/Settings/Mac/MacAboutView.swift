#if os(macOS)
    import AppKit
    import DesignSystem
    import Localization
    import StoreKit
    import SwiftUI

    private enum Metrics {
        static let iconSize: CGFloat = 128
        static let columnSpacing: CGFloat = .space32
        static let infoSpacing: CGFloat = .space8
        static let linkSpacing: CGFloat = .space4
        static let sectionSpacing: CGFloat = .space24
        static let padding: CGFloat = .space32
        static let width: CGFloat = 520
        static let licensesWidth: CGFloat = 680
        static let licensesHeight: CGFloat = 520
    }

    /// The Mac's About NextExplorer window (app menu). It works signed out too, unlike the
    /// Settings window, which shows the same content as its Info pane.
    public struct MacAboutView: View {
        public static let windowID = "about"

        public init() {}

        public var body: some View {
            MacAboutContent()
                .padding(Metrics.padding)
                .frame(width: Metrics.width)
        }
    }

    /// The app icon beside its name, version and links, with the credits underneath, like a
    /// native Mac app's About pane.
    struct MacAboutContent: View {
        @Environment(\.requestReview) private var requestReview
        @Environment(\.openURL) private var openURL
        @State private var isShowingLicenses = false

        var body: some View {
            VStack(spacing: Metrics.sectionSpacing) {
                HStack(alignment: .top, spacing: Metrics.columnSpacing) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                        .accessibilityHidden(true)
                    info
                }
                .fixedSize()
                Text(L10n.Settings.creditsMadeBy)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .sheet(isPresented: $isShowingLicenses) {
                VStack(spacing: 0) {
                    MacLicensesView()
                    Divider()
                    HStack {
                        Spacer()
                        Button(L10n.Common.close) { isShowingLicenses = false }
                            .keyboardShortcut(.defaultAction)
                    }
                    .padding(Metrics.infoSpacing * 2)
                }
                .frame(width: Metrics.licensesWidth, height: Metrics.licensesHeight)
            }
        }

        private var info: some View {
            VStack(alignment: .leading, spacing: Metrics.infoSpacing) {
                Text(Self.appName)
                    .font(.title2.weight(.semibold))
                Text(Self.versionText)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                VStack(alignment: .leading, spacing: Metrics.linkSpacing) {
                    Button(L10n.Settings.rowOpenSourceLicenses) { isShowingLicenses = true }
                    Button(L10n.Settings.rowPrivacyPolicy) { openURL(AppLinks.privacy) }
                    Button(L10n.Settings.rowTermsOfUse) { openURL(AppLinks.terms) }
                }
                .buttonStyle(.link)
                .padding(.vertical, Metrics.infoSpacing)
                HStack {
                    Button(L10n.MacSettings.support) { openURL(AppLinks.support) }
                    Button(L10n.Settings.rowRateApp) { requestReview() }
                }
                .controlSize(.large)
            }
        }

        private static var appName: String {
            Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? ""
        }

        private static var versionText: String {
            let info = Bundle.main.infoDictionary
            let version = info?["CFBundleShortVersionString"] as? String ?? "-"
            let build = info?["CFBundleVersion"] as? String ?? "-"
            return L10n.Settings.appVersion(version, build)
        }
    }

    #Preview("About") {
        MacAboutView()
    }
#endif
