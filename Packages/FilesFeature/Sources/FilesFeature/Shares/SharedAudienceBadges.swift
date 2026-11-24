import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let avatarSize: CGFloat = 22
    static let avatarOverlap: CGFloat = -.size6
    static let avatarRing: CGFloat = .size2
    static let maxAvatars = 3
    static let globeSize: CGFloat = .iconXSmall
    static let expiredOpacity: Double = 0.45
}

/// Who an item's shares reach: its public link as a globe circle, live first, then each people
/// share as its own avatar stack.
struct SharedAudienceBadgeRow: View {
    let badges: [SharedFeature.ShareBadge]
    var ringColor = Color.backgroundSecondary

    private var linkBadge: SharedFeature.ShareBadge? {
        let links = badges.filter(\.isAnyone)
        return links.first { $0.expiry != .expired } ?? links.first
    }

    var body: some View {
        HStack(spacing: .space4) {
            if let linkBadge {
                SharedLinkCircle(isExpired: linkBadge.expiry == .expired)
            }
            ForEach(badges.filter { !$0.isAnyone }) { SharedPeopleStack(badge: $0, ringColor: ringColor) }
        }
        .fixedSize()
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
/// Overlapping avatars for one share's people, with a grey `+N` past the first few.
struct SharedPeopleStack: View {
    let badge: SharedFeature.ShareBadge
    /// The surface behind the row, drawn as a ring so overlapping avatars read apart.
    var ringColor = Color.backgroundSecondary

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
                AvatarView.person(person.name, size: Constants.avatarSize)
                    .overlay(Circle().strokeBorder(ringColor, lineWidth: Constants.avatarRing))
                    .accessibilityLabel(person.name)
            }
            if hiddenCount > 0 {
                AvatarLabel(
                    text: L10n.Shared.moreRecipients(hiddenCount),
                    size: Constants.avatarSize,
                    color: Color.primaryInverted
                )
                .background(Circle().fill(Color.secondaryDS))
                .overlay(Circle().strokeBorder(ringColor, lineWidth: Constants.avatarRing))
            }
        }
    }
}

private func badgesPreview(expiry: SharedFeature.ExpiryNotice?) -> some View {
    SharedAudienceBadgeRow(badges: [
        SharedFeature.ShareBadge(id: "a", isAnyone: true, people: [], unnamedCount: 0, expiry: expiry),
        SharedFeature.ShareBadge(
            id: "p",
            isAnyone: false,
            people: Share.previewShareableUsers.prefix(4).map {
                SharedFeature.Person(id: $0.id, name: $0.displayLabel)
            },
            unnamedCount: 1,
            expiry: expiry
        ),
    ])
    .padding()
    .background(Color.backgroundSecondary)
}

#Preview("Badges: live") {
    badgesPreview(expiry: nil)
}

#Preview("Badges: expired, dark") {
    badgesPreview(expiry: .expired)
        .preferredColorScheme(.dark)
}
