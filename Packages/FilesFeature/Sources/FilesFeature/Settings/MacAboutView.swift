#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 420
        static let height: CGFloat = 660
        static let logoSize: CGFloat = 72
        static let headerSpacing: CGFloat = .space8
        static let headerTopPadding: CGFloat = .space24
        static let rowIconSize: CGFloat = .iconSmall
    }

    /// The Mac's About NextExplorer window (app menu): who made it, the version, and the
    /// support, legal and license links the Settings window no longer carries.
    public struct MacAboutView: View {
        public static let windowID = "about"

        public init() {}

        public var body: some View {
            NavigationStack {
                DSGroupedList {
                    Section {
                        header
                    }
                    SupportSettingsSection(filter: SettingsSearchFilter(query: ""))
                    LegalSettingsSection(filter: SettingsSearchFilter(query: ""))
                    Section {
                        NavigationLink {
                            LicensesView()
                        } label: {
                            Label {
                                Text(L10n.Settings.rowOpenSourceLicenses).type(.body2(.regular), style: .primaryOnSurface)
                            } icon: {
                                IconKit.document
                                    .resizable()
                                    .scaledToFit()
                                    .foregroundStyle(Color.secondaryDS)
                                    .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                            }
                            .fullRowHitArea()
                        }
                    } header: {
                        DSFieldLabel(L10n.Settings.sectionLicenses)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                .groupedListUsesNativeForm()
                .scrollContentBackground(.hidden)
                .backgroundGradient()
                .navigationTitle(L10n.Menu.about)
            }
            .frame(width: Metrics.width, height: Metrics.height)
            .tint(Color.accent)
        }

        private var header: some View {
            VStack(spacing: Metrics.headerSpacing) {
                IconKit.logo
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.logoSize, height: Metrics.logoSize)
                    .accessibilityHidden(true)
                Text(Self.appName)
                    .type(.headline3, style: .primaryOnSurface)
                Text(Self.versionText)
                    .type(.body3(.regular), style: .tertiary)
                Text(L10n.Settings.creditsMadeBy)
                    .type(.body3(.regular), style: .tertiary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, Metrics.headerTopPadding)
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
