#if os(macOS)
    import AppKit
    import CoreModels
    import DesignSystem
    import Localization
    import StoreKit
    import SwiftUI

    private enum Metrics {
        static let iconSize: CGFloat = 128
        static let width: CGFloat = 520
        static let licensesWidth: CGFloat = 760
        static let licensesHeight: CGFloat = 520
        static let rowHeight: CGFloat = .size48
    }

    /// The Mac's About NextExplorer window (app menu). It works signed out too, unlike the
    /// Settings window, which shows the same content as its Info pane.
    public struct MacAboutView: View {
        public static let windowID = "about"

        /// Opens the tip jar in the main window, where the session lives.
        private let onTip: (@MainActor () -> Void)?

        public init(onTip: (@MainActor () -> Void)? = nil) {
            self.onTip = onTip
        }

        public var body: some View {
            MacAboutContent(onTip: onTip)
                .padding(.horizontal, .space32)
                .padding(.vertical, .space24)
                .frame(width: Metrics.width)
        }
    }

    /// The app icon beside its name, version and links, with the credits underneath, like a
    /// native Mac app's About pane.
    struct MacAboutContent: View {
        /// Opens the tip jar; the About window has no session of its own, so its owner supplies this.
        var onTip: (@MainActor () -> Void)?

        @Environment(\.requestReview) private var requestReview
        @Environment(\.openURL) private var openURL
        @State private var isShowingLicenses = false

        var body: some View {
            VStack(spacing: .space24) {
                HStack(spacing: .space24) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: Metrics.iconSize, height: Metrics.iconSize)
                        .accessibilityHidden(true)
                    info
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                actions
                credits
            }
            .sheet(isPresented: $isShowingLicenses) {
                MacLicensesSheet { isShowingLicenses = false }
                    .frame(width: Metrics.licensesWidth, height: Metrics.licensesHeight)
            }
        }

        private var info: some View {
            VStack(alignment: .leading, spacing: .space4) {
                Text(AppIdentity.name)
                    .type(.headline1)
                Text(AppDiagnostics.versionText)
                    .type(.body2(.regular), style: .secondary)
                    .textSelection(.enabled)
                VStack(alignment: .leading, spacing: .space2) {
                    link(L10n.Settings.rowOpenSourceLicenses) { isShowingLicenses = true }
                    link(L10n.Settings.rowPrivacyPolicy) { openURL(AppLinks.privacy) }
                    link(L10n.Settings.rowTermsOfUse) { openURL(AppLinks.terms) }
                }
                .padding(.top, .space8)
            }
        }

        private var actions: some View {
            VStack(spacing: .zero) {
                MacAboutRow(title: L10n.MacSettings.support, icon: IconKit.envelope) {
                    openURL(AppLinks.supportMail)
                }
                Rectangle()
                    .fill(Color.macLine)
                    .frame(height: .borderWidthHairline)
                MacAboutRow(title: L10n.Settings.rowRateApp, icon: IconKit.star) {
                    requestReview()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: .radiusCard, style: .continuous)
                    .fill(Color.macRow)
            )
            .clipShape(RoundedRectangle(cornerRadius: .radiusCard, style: .continuous))
        }

        private var credits: some View {
            VStack(spacing: .space8) {
                if let onTip {
                    Button(action: onTip) {
                        Text(L10n.Settings.creditsLikeApp).foregroundStyle(Color.secondaryText)
                            + Text(verbatim: " ")
                            + Text(L10n.Settings.creditsBuyCoffee).fontWeight(.semibold)
                    }
                    .buttonStyle(.macDS(.secondary, size: .small))
                }
                Text(L10n.Settings.creditsMadeBy)
                    .type(.body3(.regular), style: .secondary)
            }
            .multilineTextAlignment(.center)
        }

        private func link(_ title: String, action: @escaping () -> Void) -> some View {
            Button(title, action: action)
                .buttonStyle(.plain)
                .type(.body3(.semibold), style: .link)
                .pointerStyle(.link)
        }
    }

    private struct MacAboutRow: View {
        let title: String
        let icon: Image
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: .space12) {
                    Text(title)
                        .type(.body1(.semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    icon
                        .foregroundStyle(Color.secondaryText)
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, .space16)
                .frame(minHeight: Metrics.rowHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableButtonStyle())
        }
    }

    struct MacLicensesSheet: View {
        let onClose: () -> Void

        var body: some View {
            VStack(spacing: .zero) {
                Text(L10n.Licenses.navigationTitle)
                    .type(.label3)
                    .frame(maxWidth: .infinity, minHeight: Metrics.rowHeight)
                hairline
                MacLicensesView()
                hairline
                HStack {
                    Spacer()
                    Button(L10n.Common.close, action: onClose)
                        .buttonStyle(.macDS(.primary, size: .small))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.space12)
            }
            .background(Color.macCard)
            .onExitCommand(perform: onClose)
        }

        private var hairline: some View {
            Rectangle()
                .fill(Color.macLine)
                .frame(height: .borderWidthHairline)
        }
    }

    #Preview("About") {
        MacAboutView(onTip: {})
    }

    #Preview("About, dark") {
        MacAboutView(onTip: {})
            .environment(\.colorScheme, .dark)
    }

    #Preview("Licenses sheet") {
        MacLicensesSheet(onClose: {})
            .frame(width: 760, height: 520)
    }
#endif
