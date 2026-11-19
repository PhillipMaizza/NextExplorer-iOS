import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let circleSize: CGFloat = .size40
    static let nameWidth: CGFloat = .size56
    static let rowSpacing: CGFloat = .space12
}

/// Who a share reaches, in the item sheet: a globe and a line for a public link, otherwise each
/// person as a circle with their name under it, the last name on its own line, plus a `+N` for
/// names not resolved yet.
struct SharedPeopleCircles: View {
    let badge: SharedFeature.ShareBadge

    var body: some View {
        if badge.isAnyone {
            HStack(spacing: .space12) {
                SharedIconCircle(icon: IconKit.web)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(L10n.Shared.anyoneWithLink).type(.body2(.semibold), style: .primaryOnSurface)
                    Text(L10n.Shared.noAccountNeeded).type(.body3(.regular), style: .secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        } else {
            DSFlowLayout(horizontalSpacing: .space12, verticalSpacing: Constants.rowSpacing) {
                ForEach(badge.people) { person in
                    circle(
                        AvatarView(
                            displayName: person.name,
                            size: Constants.circleSize,
                            tint: Color.categorical(for: person.name)
                        ),
                        caption: Self.nameLines(of: person.name)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(person.name)
                }
                if badge.unnamedCount > 0 {
                    circle(
                        AvatarLabel(
                            text: L10n.Shared.moreRecipients(badge.unnamedCount),
                            size: Constants.circleSize,
                            color: Color.primaryInverted
                        )
                        .background(Circle().fill(Color.secondaryDS)),
                        caption: nil
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func circle(_ avatar: some View, caption: String?) -> some View {
        VStack(spacing: .space4) {
            avatar.frame(width: Constants.circleSize, height: Constants.circleSize)
            if let caption {
                Text(caption)
                    .type(.caption(.regular), style: .secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .frame(width: Constants.nameWidth)
    }

    /// The first name, then the rest on a second line, so two people who share a first name
    /// and initials still read apart.
    static func nameLines(of name: String) -> String {
        let parts = name.split(separator: " ", maxSplits: 1)
        return parts.map(String.init).joined(separator: "\n")
    }
}

private func peoplePreview(_ badge: SharedFeature.ShareBadge) -> some View {
    SharedPeopleCircles(badge: badge)
        .padding()
        .background(Color.backgroundSecondary)
        .padding()
        .background(Color.backgroundPrimary)
}

#Preview("People: anyone") {
    peoplePreview(SharedFeature.ShareBadge(id: "a", isAnyone: true, people: [], unnamedCount: 0, expiry: nil))
}

#Preview("People: named and unresolved") {
    peoplePreview(SharedFeature.ShareBadge(
        id: "p",
        isAnyone: false,
        people: Share.previewShareableUsers.prefix(6).map {
            SharedFeature.Person(id: $0.id, name: $0.displayName ?? $0.username)
        },
        unnamedCount: 2,
        expiry: nil
    ))
}

#Preview("People: dark") {
    peoplePreview(SharedFeature.ShareBadge(
        id: "d",
        isAnyone: false,
        people: [SharedFeature.Person(id: "u4", name: "Jonas Keller")],
        unnamedCount: 0,
        expiry: nil
    ))
    .preferredColorScheme(.dark)
}
