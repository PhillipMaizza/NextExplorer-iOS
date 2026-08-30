import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .iconMedium
    static let closeIconSize: CGFloat = .iconXSmall
    static let closeButtonPadding: CGFloat = .space8
    static let rowSpacing: CGFloat = .space8
    static let rowToTitleSpacing: CGFloat = .space16
    static let titleLineLimit = 2
}

/// The header every presented card sheet shares, modeled on the upload review sheet: a
/// leading accent-tinted icon and a trailing circular close button on one row, with an
/// optional `.headline3` title underneath.
///
/// Place it as the first child of the sheet's content stack; the stack's own spacing then
/// separates the header from the first field. Full-screen covers over media use
/// `DSCloseButton` (frosted) instead — this is for opaque card sheets only.
///
/// `closeAccessibilityLabel` defaults to the English "Close"; localized call sites pass
/// their own `L10n` string so DesignSystem stays free of an app copy dependency.
public struct DSSheetHeader: View {
    private let icon: Image
    private let title: String?
    private let tint: Color
    private let closeAccessibilityLabel: String
    private let onClose: () -> Void

    public init(
        icon: Image,
        title: String? = nil,
        tint: Color = .accent,
        closeAccessibilityLabel: String = "Close",
        onClose: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.tint = tint
        self.closeAccessibilityLabel = closeAccessibilityLabel
        self.onClose = onClose
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Constants.rowToTitleSpacing) {
            HStack(spacing: Constants.rowSpacing) {
                icon
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(tint)
                    .frame(width: Constants.iconSize, height: Constants.iconSize)

                Spacer(minLength: Constants.rowSpacing)

                Button(action: onClose) {
                    IconKit.close
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.primaryDS)
                        .frame(width: Constants.closeIconSize, height: Constants.closeIconSize)
                        .padding(Constants.closeButtonPadding)
                        .background(Circle().fill(Color.backgroundSecondary))
                }
                .buttonStyle(DSHapticButtonStyle())
                .accessibilityLabel(closeAccessibilityLabel)
            }

            if let title {
                Text(title)
                    .type(.headline3)
                    .foregroundColor(tint)
                    .lineLimit(Constants.titleLineLimit)
            }
        }
    }
}

#Preview("With title") {
    VStack(spacing: .space24) {
        DSSheetHeader(icon: IconKit.shareLink, title: "Edit Share Link", onClose: {})
        DSSheetHeader(icon: IconKit.folderFill, title: "A rather long folder name that wraps onto a second line", onClose: {})
    }
    .padding(.space24)
    .background(Color.backgroundPrimary)
}

#Preview("Icon only") {
    DSSheetHeader(icon: IconKit.upload, onClose: {})
        .padding(.space24)
        .background(Color.backgroundPrimary)
}
