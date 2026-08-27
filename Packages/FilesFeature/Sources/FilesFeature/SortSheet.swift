import DesignSystem
import SwiftUI

private enum Constants {
    static let headerIconSize: CGFloat = .iconMedium
    static let closeIconSize: CGFloat = .iconXSmall
    static let closeButtonPadding: CGFloat = .space8
    static let contentSpacing: CGFloat = .space16
    static let rowSpacing: CGFloat = .space12
    static let rowVerticalPadding: CGFloat = .space8
    static let horizontalPadding: CGFloat = .space24
    static let topPadding: CGFloat = .space24
    static let bottomPadding: CGFloat = .space24
    static let rowIconSize: CGFloat = .iconSmall
    static let radioSize: CGFloat = .iconSmall
    static let selectionAnimationDuration: Double = 0.2
    static let fullOpacity: Double = 1.0
    static let zeroOpacity: Double = 0.0
}

/// Generic "Sort by" sheet shared by Favorites and Downloads — same shape as the
/// Browse-specific `BrowseSortSheet`, generalized over whatever option/direction enum each
/// screen sorts by, so the two don't need their own near-identical copy of this UI.
struct SortSheet<Option: Hashable, Direction: Hashable>: View {
    let options: [Option]
    let directions: [Direction]
    let sortOption: Option
    let sortDirection: Direction
    let optionIcon: (Option) -> Image
    let optionTitle: (Option) -> String
    let directionIcon: (Direction) -> Image
    let directionTitle: (Direction) -> String
    let onSelectOption: (Option) -> Void
    let onSelectDirection: (Direction) -> Void
    let onDismiss: () -> Void

    var body: some View {
        DynamicHeightSheet {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            HStack {
                IconKit.sort
                    .resizable()
                    .foregroundStyle(Color.accent)
                    .frame(width: Constants.headerIconSize, height: Constants.headerIconSize)
                    .padding(.bottom, .space8)

                Spacer()

                Button(action: onDismiss) {
                    IconKit.close
                        .resizable()
                        .foregroundStyle(Color.primaryDS)
                        .frame(width: Constants.closeIconSize, height: Constants.closeIconSize)
                        .padding(Constants.closeButtonPadding)
                        .background(Circle().fill(Color.backgroundSecondary))
                }
                .buttonStyle(DSHapticButtonStyle())
            }

            Text("Sort By").type(.headline3, style: .link)

            VStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    radioRow(icon: optionIcon(option), title: optionTitle(option), isSelected: option == sortOption) {
                        onSelectOption(option)
                    }
                }
            }

            Divider()

            VStack(spacing: 0) {
                ForEach(directions, id: \.self) { direction in
                    radioRow(icon: directionIcon(direction), title: directionTitle(direction), isSelected: direction == sortDirection) {
                        onSelectDirection(direction)
                    }
                }
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
        .padding(.bottom, Constants.bottomPadding)
    }

    private func radioRow(icon: Image, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Constants.rowSpacing) {
                icon
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                Text(title)
                    .type(.body1(isSelected ? .semibold : .regular), style: .primary(for: .label))
                Spacer()
                ZStack {
                    IconKit.radioUnselected
                        .resizable()
                        .foregroundStyle(Color.secondaryDS)
                        .opacity(isSelected ? Constants.zeroOpacity : Constants.fullOpacity)
                    IconKit.radioSelected
                        .resizable()
                        .foregroundStyle(Color.accent)
                        .opacity(isSelected ? Constants.fullOpacity : Constants.zeroOpacity)
                }
                .frame(width: Constants.radioSize, height: Constants.radioSize)
            }
            .padding(.vertical, Constants.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSHapticButtonStyle())
        .padding(.vertical, .space8)
        .animation(.easeInOut(duration: Constants.selectionAnimationDuration), value: isSelected)
        .hapticFeedback(.selection, trigger: isSelected)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SortSheet(
                options: FavoritesFeature.SortOption.allCases,
                directions: BrowseFeature.SortDirection.allCases,
                sortOption: .name,
                sortDirection: .ascending,
                optionIcon: { $0.icon },
                optionTitle: { $0.title },
                directionIcon: { $0.icon },
                directionTitle: { $0.title },
                onSelectOption: { _ in },
                onSelectDirection: { _ in },
                onDismiss: {}
            )
        }
}
