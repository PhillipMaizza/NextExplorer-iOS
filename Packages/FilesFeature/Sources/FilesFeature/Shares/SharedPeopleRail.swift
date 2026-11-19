import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let circleSize: CGFloat = 50
    static let ringWidth: CGFloat = 2
    static let ringGap: CGFloat = 3
    static let iconSize: CGFloat = 18
    static let itemWidth: CGFloat = 52
    static let badgeHeight: CGFloat = 18
    static let badgeBorder: CGFloat = 2
    static let badgeOffset = CGSize(width: 3, height: 2)
    static let allFillOpacity: Double = 0.2
}

/// The filter row above the Shared list: All, Anyone, then each person with the number of
/// items they appear on. Tapping one narrows the list to it; tapping it again clears it.
struct SharedPeopleRail: View {
    let options: [SharedFeature.FilterOption]
    let selection: SharedFeature.Filter
    let onSelect: (SharedFeature.Filter) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: .space12) {
                ForEach(options) { option in
                    SharedRailButton(
                        option: option,
                        isSelected: option.filter == selection,
                        // Tapping the active filter again clears it back to All.
                        onTap: { onSelect(option.filter == selection ? .all : option.filter) }
                    )
                }
            }
            .padding(.horizontal, .space16)
        }
        .scrollClipDisabled()
    }
}

private struct SharedRailButton: View {
    let option: SharedFeature.FilterOption
    let isSelected: Bool
    let onTap: () -> Void

    private var innerSize: CGFloat {
        Constants.circleSize - 2 * (Constants.ringWidth + Constants.ringGap)
    }

    private var label: String {
        switch option.filter {
        case .all: L10n.Shared.filterAll
        case .anyone: L10n.Shared.filterAnyone
        case .person: option.name.split(separator: " ").first.map(String.init) ?? option.name
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
            }
            .frame(width: Constants.itemWidth)
            .contentShape(Rectangle())
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
        case .person:
            AvatarView(displayName: option.name, size: innerSize, tint: Color.categorical(for: option.name))
        }
    }

    private func glyph(_ image: Image, tint: Color) -> some View {
        image
            .resizable().scaledToFit()
            .fontWeight(.semibold)
            .foregroundStyle(tint)
            .frame(width: Constants.iconSize, height: Constants.iconSize)
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
    var personID: String? {
        if case let .person(id) = self {
            return id
        }
        return nil
    }

    var identifierSuffix: String {
        switch self {
        case .all: "all"
        case .anyone: "anyone"
        case let .person(id): "person.\(id)"
        }
    }
}

private let previewOptions: [SharedFeature.FilterOption] = [
    .init(filter: .all, name: "", count: 6),
    .init(filter: .anyone, name: "", count: 4),
    .init(filter: .person("u1"), name: "Anna Moreau", count: 2),
    .init(filter: .person("u2"), name: "Jonas Keller", count: 2),
    .init(filter: .person("u3"), name: "Lea Sato", count: 1),
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

#Preview("Rail: person") {
    SharedPeopleRail(options: previewOptions, selection: .person("u2"), onSelect: { _ in })
        .padding(.vertical)
        .background(Color.backgroundPrimary)
}
