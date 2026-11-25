import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = .size64
    static let folderGlyphSize: CGFloat = .superIcon
    static let expiredOpacity: Double = .opacityHalf
}

/// The top of the item sheet: the item's icon, a title and one line under it, centered. Sits in
/// its own clear list row so it scrolls with the facts below.
struct SharedDetailHero: View {
    let share: Share
    let iconName: String
    let title: String
    let subtitle: String
    let serverURL: URL
    let isByMe: Bool
    let isExpired: Bool

    var body: some View {
        VStack(spacing: .space4) {
            SharedItemIcon(
                share: share,
                name: iconName,
                serverURL: serverURL,
                isByMe: isByMe,
                folderGlyphSize: Constants.folderGlyphSize
            )
            .frame(width: Constants.iconSize, height: Constants.iconSize)
            .opacity(isExpired ? Constants.expiredOpacity : 1)
            .accessibilityHidden(true)

            Text(title)
                .type(.headline4, style: .primaryOnSurface)
                .multilineTextAlignment(.center)
                .padding(.top, .space4)
            Text(subtitle)
                .type(.body3(.regular), style: .secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    /// `Work/Roadmap` as `/Work/Roadmap`: the item's full path as the server stores it.
    static func fullPath(of share: Share) -> String? {
        guard let path = share.trimmedSourcePath, !path.isEmpty else { return nil }
        return "/" + path
    }

    /// The full path and every share's downloads together, for an item with several shares.
    static func summary(of item: SharedFeature.Item) -> String {
        let downloads = L10n.Shared.downloadCount(item.downloadCount)
        guard let path = fullPath(of: item.shares[0]) else { return downloads }
        return L10n.Shared.statusStep(path, downloads)
    }
}

#Preview("Hero: folder") {
    SharedDetailHero(
        share: .previewCard(isDirectory: true),
        iconName: "Team Roadmap",
        title: "Team Roadmap",
        subtitle: "/Work/Team Roadmap",
        serverURL: URL(fileURLWithPath: "/"),
        isByMe: true,
        isExpired: false
    )
    .padding()
    .background(Color.backgroundPrimary)
}

#Preview("Hero: expired file, dark") {
    SharedDetailHero(
        share: .previewCard(expiresAt: Date().addingTimeInterval(-3600), sourcePath: "Design/Brand/Logo final.png"),
        iconName: "Logo final.png",
        title: "Logo final.png",
        subtitle: "/Design/Brand/Logo final.png",
        serverURL: URL(fileURLWithPath: "/"),
        isByMe: true,
        isExpired: true
    )
    .padding()
    .background(Color.backgroundPrimary)
    .preferredColorScheme(.dark)
}
