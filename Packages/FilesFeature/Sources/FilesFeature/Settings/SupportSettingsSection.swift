import DesignSystem
import Localization
import StoreKit
import SwiftUI

private enum Constants {
    static let rowIconSize: CGFloat = .iconSmall
}

/// Hosted pages the app links to outside Settings' legal rows.
public enum AppLinks {
    public static let support = URL(string: "https://phillipmaizza.com/nextexplorer")!
}

/// Rate the app through the native App Store prompt, and reach the support site.
struct SupportSettingsSection: View {
    let filter: SettingsSearchFilter

    @Environment(\.requestReview) private var requestReview
    @Environment(\.openURL) private var openURL

    var body: some View {
        if filter.anyMatch([L10n.Settings.rowRateApp, L10n.Settings.rowSupport]) {
            Section {
                if filter.matches(L10n.Settings.rowRateApp) {
                    row(title: L10n.Settings.rowRateApp, icon: IconKit.star, trailing: nil) {
                        requestReview()
                    }
                }
                if filter.matches(L10n.Settings.rowSupport) {
                    row(title: L10n.Settings.rowSupport, icon: IconKit.help, trailing: IconKit.externalLink) {
                        openURL(AppLinks.support)
                    }
                }
            } header: {
                DSFieldLabel(L10n.Settings.sectionSupport)
                    .accessibilityAddTraits(.isHeader)
            }
            .listRowBackground(Color.backgroundSecondary)
        }
    }

    private func row(title: String, icon: Image, trailing: Image?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label {
                HStack {
                    Text(title).type(.body2(.regular), style: .primaryOnSurface)
                    Spacer()
                    if let trailing {
                        trailing
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(Color.secondaryDS)
                            .frame(width: .iconXSmall, height: .iconXSmall)
                    }
                }
            } icon: {
                icon
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
            }
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }
}

#Preview("Support section") {
    DSGroupedList {
        SupportSettingsSection(filter: SettingsSearchFilter(query: ""))
    }
    .listStyle(.insetGrouped)
}

#Preview("Support section, no match") {
    DSGroupedList {
        SupportSettingsSection(filter: SettingsSearchFilter(query: "zzz"))
    }
    .listStyle(.insetGrouped)
}
