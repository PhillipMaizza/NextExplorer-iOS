import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let circleSize: CGFloat = 50
    static let ringWidth: CGFloat = 2
    static let ringGap: CGFloat = 3
    static let iconSize: CGFloat = .size18
    static let itemWidth: CGFloat = 52
    static let badgeHeight: CGFloat = .size18
    static let badgeBorder: CGFloat = 2
    static let badgeOffset = CGSize(width: 3, height: 2)
    static let allFillOpacity: Double = 0.2
    static let compactCircleSize: CGFloat = .size40
    static let compactIconSize: CGFloat = .iconSmall
    static let compactItemWidth: CGFloat = .size48
    static let dimmedOpacity: Double = .opacityDim
}

/// The filter row above the Shared list: All, Anyone, then each person with the number of
/// items they appear on. Tapping one narrows the list to it; tapping it again clears it. On By
/// me, people who share an item join the pick (`SharedFeature.State.filter(afterTapping:in:)`).
struct SharedPeopleRail: View {
    let options: [SharedFeature.FilterOption]
    let selection: SharedFeature.Filter
    let onSelect: (SharedFeature.Filter) -> Void
    /// Smaller circles for the Mac strip above the table.
    var isCompact = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: .space12) {
                ForEach(options) { option in
                    SharedRailButton(
                        option: option,
                        isSelected: isSelected(option.filter),
                        isCompact: isCompact,
                        onTap: { onSelect(option.filter) }
                    )
                }
            }
            .padding(.horizontal, .space16)
        }
        .scrollClipDisabled()
    }

    private func isSelected(_ filter: SharedFeature.Filter) -> Bool {
        guard let id = filter.personID, case let .people(picked) = selection else {
            return filter == selection
        }
        return picked.contains(id)
    }
}

private struct SharedRailButton: View {
    let option: SharedFeature.FilterOption
    let isSelected: Bool
    let isCompact: Bool
    let onTap: () -> Void

    private var innerSize: CGFloat {
        (isCompact ? Constants.compactCircleSize : Constants.circleSize) - 2 * (Constants.ringWidth + Constants.ringGap)
    }

    private var label: String {
        switch option.filter {
        case .all: L10n.Shared.filterAll
        case .anyone: L10n.Shared.filterAnyone
        case .people: option.name
        }
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: .space4) {
                circle
                    .frame(width: innerSize, height: innerSize)
                    .padding(Constants.ringGap)
                    .overlay {
                        Circle().strokeBorder(
                            isSelected ? Color.accent : Color.clear,
                            lineWidth: Constants.ringWidth
                        )
                    }
                    .padding(Constants.ringWidth)
                    .overlay(alignment: .bottomTrailing) { countBadge }
                Text(label)
                    .type(.caption(isSelected ? .bold : .regular), style: isSelected ? .primaryOnSurface : .secondary)
                    .lineLimit(1)
                    .help(option.name)
            }
            .frame(width: isCompact ? Constants.compactItemWidth : Constants.itemWidth)
            .contentShape(Rectangle())
            .opacity(option.isDimmed ? Constants.dimmedOpacity : 1)
        }
        .buttonStyle(DSPressableButtonStyle())
        .accessibilityLabel(option.filter.personID == nil ? label : option.name)
        .accessibilityValue(L10n.Shared.itemCount(option.count))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(AccessibilityIdentifiers.Shared.filter(option.filter.identifierSuffix))
    }

    @ViewBuilder
    private var circle: some View {
        switch option.filter {
        case .all:
            Circle()
                .fill(Color.accent.opacity(Constants.allFillOpacity))
                .overlay { glyph(IconKit.squareGrid, tint: Color.accentText) }
        case .anyone:
            glyph(IconKit.web, tint: Color.secondaryDS)
                .frame(width: innerSize, height: innerSize)
                .overlay {
                    Circle().strokeBorder(Color.borderPrimary, lineWidth: .borderWidthHairline)
                }
        case .people:
            AvatarView.person(option.name, size: innerSize)
        }
    }

    private func glyph(_ image: Image, tint: Color) -> some View {
        image
            .resizable().scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .frame(
                width: isCompact ? Constants.compactIconSize : Constants.iconSize,
                height: isCompact ? Constants.compactIconSize : Constants.iconSize
            )
    }

    private var countBadge: some View {
        Text(verbatim: "\(option.count)")
            .type(.caption(.bold))
            .foregroundStyle(Color.primaryInverted)
            .padding(.horizontal, .space4)
            .frame(minWidth: Constants.badgeHeight, minHeight: Constants.badgeHeight)
            .background(Capsule().fill(Color.primaryDS))
            .overlay(Capsule().strokeBorder(Color.backgroundPrimary, lineWidth: Constants.badgeBorder))
            .offset(Constants.badgeOffset)
            .accessibilityHidden(true)
    }
}

extension SharedFeature.Filter {
    /// The one person a people row circle stands for.
    var personID: String? {
        if case let .people(ids) = self, ids.count == 1 {
            return ids.first
        }
        return nil
    }

    var identifierSuffix: String {
        switch self {
        case .all: "all"
        case .anyone: "anyone"
        case let .people(ids): "person.\(ids.sorted().joined(separator: "."))"
        }
    }
}

private let previewOptions: [SharedFeature.FilterOption] = [
    .init(filter: .all, name: "", count: 6),
    .init(filter: .anyone, name: "", count: 4),
    .init(filter: .people(["u1"]), name: "Anna Moreau", count: 2),
    .init(filter: .people(["u2"]), name: "Jonas Keller", count: 2),
    .init(filter: .people(["u3"]), name: "Lea Sato", count: 1, isDimmed: true),
]

#Preview("Rail: All") {
    SharedPeopleRail(options: previewOptions, selection: .all, onSelect: { _ in })
        .padding(.vertical)
        .background(Color.backgroundPrimary)
}

#Preview("Rail: Anyone, dark") {
    SharedPeopleRail(options: previewOptions, selection: .anyone, onSelect: { _ in })
        .padding(.vertical)
        .background(Color.backgroundPrimary)
        .preferredColorScheme(.dark)
}

#Preview("Rail: two people") {
    SharedPeopleRail(options: previewOptions, selection: .people(["u1", "u2"]), onSelect: { _ in })
        .padding(.vertical)
        .background(Color.backgroundPrimary)
}

#Preview("Rail: compact, dark") {
    SharedPeopleRail(options: previewOptions, selection: .people(["u1"]), onSelect: { _ in }, isCompact: true)
        .padding(.vertical)
        .background(Color.backgroundPrimary)
        .preferredColorScheme(.dark)
}
