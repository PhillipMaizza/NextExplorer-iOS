import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let circleSize: CGFloat = .size40
    static let nameWidth: CGFloat = .size56
    static let rowSpacing: CGFloat = .space12
    /// Past this many people the rest wait behind the Show More circle.
    static let collapsedLimit = 10
    static let toggleGlyphSize: CGFloat = .iconSmall
    static let toggleFillOpacity: Double = 0.2
}

/// Who a share reaches, in the item sheet: a globe and a line for a public link, otherwise each
/// person as a circle with their name under it, the last name on its own line. A recipient whose
/// name has not resolved shows as Someone. Past ten, an accent circle shows everyone or folds back.
struct SharedPeopleCircles: View {
    let badge: SharedFeature.ShareBadge

    @State private var isExpanded = false

    /// Named people first, then one entry per unresolved recipient.
    private var entries: [SharedFeature.Person?] {
        badge.people.map(Optional.some) + Array(repeating: nil, count: badge.unnamedCount)
    }

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
            people
        }
    }

    private var people: some View {
        let entries = entries
        let canCollapse = entries.count > Constants.collapsedLimit
        let shown = canCollapse && !isExpanded ? Array(entries.prefix(Constants.collapsedLimit)) : entries
        return DSFlowLayout(horizontalSpacing: .space12, verticalSpacing: Constants.rowSpacing) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, person in
                if let person {
                    circle(
                        AvatarView.person(person.name, size: Constants.circleSize),
                        caption: Self.nameLines(of: person.name)
                    )
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(person.name)
                } else {
                    circle(SharedIconCircle(icon: IconKit.person), caption: L10n.Shared.sharedByUnknown)
                        .accessibilityElement(children: .combine)
                }
            }
            if canCollapse {
                toggle(hiddenCount: entries.count - shown.count)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// `+N` with Show More while folded, a chevron with Show Less once everyone shows.
    private func toggle(hiddenCount: Int) -> some View {
        Button {
            withAnimation(DSMotion.disclosure) { isExpanded.toggle() }
        } label: {
            circle(
                Circle()
                    .fill(Color.accent.opacity(Constants.toggleFillOpacity))
                    .overlay {
                        if isExpanded {
                            IconKit.chevronUp
                                .resizable().scaledToFit()
                                .fontWeight(.semibold)
                                .frame(width: Constants.toggleGlyphSize, height: Constants.toggleGlyphSize)
                        } else {
                            Text(L10n.Shared.moreRecipients(hiddenCount)).type(.body3(.bold))
                        }
                    }
                    .foregroundStyle(Color.accentText),
                caption: isExpanded ? L10n.Shared.showLess : L10n.Shared.showMore,
                isCaptionBold: true
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(DSPressableButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isExpanded ? L10n.Shared.showLess : L10n.Shared.showMore)
        .accessibilityAddTraits(.isButton)
    }

    /// `isCaptionBold` marks the Show More circle as a button among the names.
    private func circle(_ avatar: some View, caption: String?, isCaptionBold: Bool = false) -> some View {
        VStack(spacing: .space4) {
            avatar.frame(width: Constants.circleSize, height: Constants.circleSize)
            if let caption {
                Text(caption)
                    .type(.caption(isCaptionBold ? .bold : .regular), style: .secondary)
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

@MainActor
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
            SharedFeature.Person(id: $0.id, name: $0.displayLabel)
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

#Preview("People: more than ten") {
    peoplePreview(SharedFeature.ShareBadge(
        id: "m",
        isAnyone: false,
        people: (1 ... 14).map { SharedFeature.Person(id: "u\($0)", name: "Person \($0)") },
        unnamedCount: 1,
        expiry: nil
    ))
}
