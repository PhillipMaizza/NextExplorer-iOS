import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let height: CGFloat = .size48
    static let menuWidth: CGFloat = .size56
    static let iconSize: CGFloat = .iconSmall
    static let chevronSize: CGFloat = .iconXSmall
    static let dividerHeight: CGFloat = .size20
    static let dividerOpacity: Double = .opacityHalf
}

/// The share page's main action, a split button on the surface fill: the main half copies the
/// share link (or, once expired, opens Edit to set a new date); the arrow lists every link.
struct SharedCopyLinkButton: View {
    let share: Share
    let serverURL: URL
    let directLinkMode: DirectLinkMode
    let isExpired: Bool
    let onCopied: (String) -> Void
    let onSetNewDate: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: isExpired ? onSetNewDate : copyShareLink) {
                HStack(spacing: .space8) {
                    glyph(isExpired ? IconKit.calendar : IconKit.link, size: Constants.iconSize)
                    Text(isExpired ? L10n.Shared.setNewDate : L10n.Shared.copyLink)
                        .type(.body2(.semibold), style: .primaryOnSurface)
                }
                .frame(maxWidth: .infinity, minHeight: Constants.height)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableButtonStyle())

            Rectangle()
                .fill(Color.borderPrimary.opacity(Constants.dividerOpacity))
                .frame(width: .borderWidthHairline, height: Constants.dividerHeight)
                .accessibilityHidden(true)

            Menu {
                Button(action: copyShareLink) {
                    Label { Text(L10n.Shared.copyShareLink) } icon: { IconKit.link }
                }
                Button(action: copyDirectLink) {
                    Label {
                        Text(share.isDirectory ? L10n.Shared.copyFolderLink : L10n.Shared.copyFileLink)
                    } icon: {
                        IconKit.copy
                    }
                }
                if let url = URL(string: share.shareLink(serverURL: serverURL)) {
                    ShareLink(item: url) {
                        Label { Text(L10n.Common.share) } icon: { IconKit.share }
                    }
                }
            } label: {
                glyph(IconKit.chevronDown, size: Constants.chevronSize)
                    .fontWeight(.bold)
                    .frame(width: Constants.menuWidth, height: Constants.height)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(L10n.Shared.moreLinks)
        }
        .background(RoundedRectangle(cornerRadius: .radiusCard, style: .continuous).fill(Color.backgroundSecondary))
    }

    private func glyph(_ image: Image, size: CGFloat) -> some View {
        image
            .resizable().scaledToFit()
            .foregroundStyle(Color.accentText)
            .frame(width: size, height: size)
    }

    private func copyShareLink() {
        onCopied(share.copyShareLink(serverURL: serverURL))
    }

    private func copyDirectLink() {
        onCopied(share.copyDirectLink(serverURL: serverURL, mode: directLinkMode))
    }
}

#Preview("Copy button: live") {
    SharedCopyLinkButton(
        share: .previewCard(isDirectory: true),
        serverURL: URL(fileURLWithPath: "/"),
        directLinkMode: .auto,
        isExpired: false,
        onCopied: { _ in },
        onSetNewDate: {}
    )
    .padding()
    .background(Color.backgroundPrimary)
}

#Preview("Copy button: expired, dark") {
    SharedCopyLinkButton(
        share: .previewCard(isDirectory: true),
        serverURL: URL(fileURLWithPath: "/"),
        directLinkMode: .auto,
        isExpired: true,
        onCopied: { _ in },
        onSetNewDate: {}
    )
    .padding()
    .background(Color.backgroundPrimary)
    .preferredColorScheme(.dark)
}
