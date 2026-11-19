import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let iconSize: CGFloat = 36
    static let folderGlyphSize: CGFloat = 30
    static let avatarSize: CGFloat = 22
    static let avatarOverlap: CGFloat = -6
    static let avatarRing: CGFloat = 2
    static let maxAvatars = 3
    static let globeSize: CGFloat = 12
    static var dividerInset: CGFloat {
        .space16 + iconSize + .space12
    }

    static let sharerAvatarSize: CGFloat = 20
    static let badgeGroupSpacing: CGFloat = 4
    static let expiredOpacity: Double = 0.45
    static let deletingOpacity: Double = 0.4
}

/// One shared file or folder on the Shared list: icon, name and parent folder, who each share
/// reaches in the top right corner (By me) or the sharer under the name (With me), and the
/// nearest countdown on its own line. Fully expired items fade. Tap toggles the share details.
struct SharedItemRow: View {
    let item: SharedFeature.Item
    let serverURL: URL
    let isByMe: Bool
    let isDeleting: Bool
    /// A hairline above the row, inset to the text, between items.
    var showsDivider = false
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: .space12) {
                SharedItemIcon(share: item.shares[0], name: item.name, serverURL: serverURL, isByMe: isByMe)
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                    .opacity(item.isExpired ? Constants.expiredOpacity : 1)

                VStack(alignment: .leading, spacing: .space4) {
                    HStack(alignment: .top, spacing: .space8) {
                        Text(item.name)
                            .type(.body2(.semibold), style: .primaryOnSurface)
                            .lineLimit(2)
                            .opacity(item.isExpired ? Constants.expiredOpacity : 1)
                        Spacer(minLength: .space4)
                        if isByMe {
                            HStack(spacing: Constants.badgeGroupSpacing) {
                                if let linkBadge {
                                    SharedLinkCircle(isExpired: linkBadge.expiry == .expired)
                                }
                                ForEach(peopleBadges) { SharedPeopleStack(badge: $0) }
                            }
                            .fixedSize()
                        }
                    }
                    locationText
                    if !isByMe, let sharer = item.badges.first?.people.first {
                        AvatarView(
                            displayName: sharer.name,
                            size: Constants.sharerAvatarSize,
                            tint: Color.categorical(for: sharer.name)
                        )
                        .opacity(item.isExpired ? Constants.expiredOpacity : 1)
                        .accessibilityLabel(sharer.name)
                    }
                    if let daysLeft {
                        Text(L10n.Shared.daysLeft(daysLeft))
                            .type(.caption(.semibold), style: .warning)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, .space16)
            .padding(.vertical, .space16)
            .overlay(alignment: .top) {
                if showsDivider {
                    Divider().padding(.leading, Constants.dividerInset)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressableButtonStyle())
        .opacity(isDeleting ? Constants.deletingOpacity : 1)
        .disabled(isDeleting)
    }

    @ViewBuilder
    private var locationText: some View {
        if let location = item.location {
            Text(Self.pathText(location))
                .type(.body3(.regular), style: .secondary)
                .lineLimit(1)
                .truncationMode(.head)
        }
    }

    /// `Work/Roadmap` as `Work › Roadmap`, joined through the localized step format.
    private static func pathText(_ location: String) -> String {
        let parts = location.split(separator: "/").map(String.init)
        return parts.dropFirst().reduce(parts.first ?? location) { L10n.Shared.pathStep($0, $1) }
    }

    /// The public link on this item, live first, drawn as a globe circle before the people.
    private var linkBadge: SharedFeature.ShareBadge? {
        let links = item.badges.filter(\.isAnyone)
        return links.first { $0.expiry != .expired } ?? links.first
    }

    private var peopleBadges: [SharedFeature.ShareBadge] {
        item.badges.filter { !$0.isAnyone }
    }

    /// The soonest countdown among the shares still live.
    private var daysLeft: Int? {
        item.badges.compactMap { badge -> Int? in
            if case let .daysLeft(days) = badge.expiry {
                return days
            }
            return nil
        }
        .min()
    }
}

/// Folder glyph, a real thumbnail for a By me image, otherwise the per format type icon.
struct SharedItemIcon: View {
    let share: Share
    let name: String
    let serverURL: URL
    let isByMe: Bool

    var body: some View {
        if share.isDirectory {
            IconKit.folderFill
                .resizable().scaledToFit()
                .foregroundStyle(Color.accentText)
                .frame(width: Constants.folderGlyphSize, height: Constants.folderGlyphSize)
        } else if let thumbnailPath {
            ThumbnailImage(
                serverURL: serverURL,
                path: thumbnailPath,
                signature: "\(share.updatedAt.timeIntervalSince1970)",
                fallbackIcon: IconKit.document,
                fallbackKind: kind,
                iconTint: Color.secondaryDS
            )
            .clipShape(RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous))
        } else {
            FileTypeIcon(kind: kind)
        }
    }

    private var kind: String {
        (name as NSString).pathExtension
    }

    /// Only By me carries the full path, and only images have a server thumbnail.
    private var thumbnailPath: String? {
        guard isByMe, let path = share.sourcePath, !path.isEmpty,
              FileItem.isImageKind(kind) || FileItem.isRawImageKind(kind) else { return nil }
        return path
    }
}

/// A public link as a circle the size of an avatar, red when it has expired.
private struct SharedLinkCircle: View {
    let isExpired: Bool

    var body: some View {
        IconKit.web
            .resizable().scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(isExpired ? Color.negative : Color.secondaryDS)
            .frame(width: Constants.globeSize, height: Constants.globeSize)
            .frame(width: Constants.avatarSize, height: Constants.avatarSize)
            .background(Circle().fill(Color.backgroundPrimary))
            .opacity(isExpired ? Constants.expiredOpacity : 1)
            .accessibilityLabel(L10n.Shared.anyoneWithLink)
    }
}

/// The recipients of one share as overlapping avatars, with a `+N` for the rest.
private struct SharedPeopleStack: View {
    let badge: SharedFeature.ShareBadge

    private var shownPeople: ArraySlice<SharedFeature.Person> {
        badge.people.prefix(Constants.maxAvatars)
    }

    private var hiddenCount: Int {
        badge.people.count - shownPeople.count + badge.unnamedCount
    }

    var body: some View {
        avatars
            .opacity(badge.expiry == .expired ? Constants.expiredOpacity : 1)
            .accessibilityElement(children: .combine)
    }

    private var avatars: some View {
        HStack(spacing: Constants.avatarOverlap) {
            ForEach(shownPeople) { person in
                AvatarView(
                    displayName: person.name,
                    size: Constants.avatarSize,
                    tint: Color.categorical(for: person.name)
                )
                .overlay(Circle().strokeBorder(Color.backgroundSecondary, lineWidth: Constants.avatarRing))
                .accessibilityLabel(person.name)
            }
            if hiddenCount > 0 {
                AvatarLabel(
                    text: L10n.Shared.moreRecipients(hiddenCount),
                    size: Constants.avatarSize,
                    color: Color.primaryInverted
                )
                .background(Circle().fill(Color.secondaryDS))
                .overlay(Circle().strokeBorder(Color.backgroundSecondary, lineWidth: Constants.avatarRing))
            }
        }
    }
}

@MainActor
private func itemRowsPreview(segment: SharedFeature.Segment) -> some View {
    var state = SharedFeature.State(serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"))
    state.now = Date()
    state.userNames = Dictionary(uniqueKeysWithValues: Share.previewShareableUsers.map { (
        $0.id,
        $0.displayName ?? $0.username
    ) })
    state.byMe = IdentifiedArray(uniqueElements: Share.previewSharedByMe)
    state.withMe = IdentifiedArray(uniqueElements: Share.previewSharedWithMe)
    let items = state.items(for: segment)
    return ScrollView {
        VStack(spacing: 0) {
            ForEach(items) { item in
                SharedItemRow(
                    item: item,
                    serverURL: state.serverURL,
                    isByMe: segment == .byMe,
                    isDeleting: false,
                    onToggle: {}
                )
                Divider()
            }
        }
        .background(Color.backgroundSecondary)
    }
    .background(Color.backgroundPrimary)
}

#Preview("Rows: By me") {
    itemRowsPreview(segment: .byMe)
}

#Preview("Rows: By me, dark") {
    itemRowsPreview(segment: .byMe)
        .preferredColorScheme(.dark)
}

#Preview("Rows: With me") {
    itemRowsPreview(segment: .withMe)
}
