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

/// "Sort by" sheet for Browse: pick which field orders the listing and which direction,
/// self-sized the same way `SignOutConfirmationView` is (see `DynamicHeightSheet`).
struct BrowseSortSheet: View {
    let sortOption: BrowseFeature.SortOption
    let sortDirection: BrowseFeature.SortDirection
    let onSelectOption: (BrowseFeature.SortOption) -> Void
    let onSelectDirection: (BrowseFeature.SortDirection) -> Void
    let onDismiss: () -> Void

    var body: some View {
        DynamicHeightSheet {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            HStack {
                IconKit.arrowUpArrowDown
                    .resizable()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.headerIconSize, height: Constants.headerIconSize)
                    .padding(.bottom, .space8)

                Spacer()

                Button(action: onDismiss) {
                    IconKit.xmark
                        .resizable()
                        .foregroundStyle(Color.primaryDS)
                        .frame(width: Constants.closeIconSize, height: Constants.closeIconSize)
                        .padding(Constants.closeButtonPadding)
                        .background(Circle().fill(Color.backgroundSecondary))
                }
            }

            Text("Sort By").type(.headline3, style: .primary(for: .label))

            VStack(spacing: 0) {
                ForEach(BrowseFeature.SortOption.allCases, id: \.self) { option in
                    radioRow(icon: option.icon, title: option.title, isSelected: option == sortOption) {
                        onSelectOption(option)
                    }
                }
            }

            Divider()

            VStack(spacing: 0) {
                ForEach(BrowseFeature.SortDirection.allCases, id: \.self) { direction in
                    radioRow(icon: direction.icon, title: direction.title, isSelected: direction == sortDirection) {
                        onSelectDirection(direction)
                    }
                }
            }
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
        .padding(.bottom, Constants.bottomPadding)
    }

    private func radioRow(icon: Image?, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Constants.rowSpacing) {
                if let icon {
                    icon
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.secondaryDS)
                        .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                }
                Text(title)
                    .type(.body1(isSelected ? .semibold : .regular), style: .primary(for: .label))
                Spacer()
                // A plain opacity crossfade between the two icons, rather than
                // `.contentTransition(.symbolEffect(.replace))`: SF Symbols' built-in replace
                // effect has its own overshoot/bounce baked into the morph, which read as the
                // whole row (and sheet) visibly bouncing on every selection.
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
        .buttonStyle(.plain)
        .padding(.vertical, .space8)
        .animation(.easeInOut(duration: Constants.selectionAnimationDuration), value: isSelected)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            BrowseSortSheet(
                sortOption: .size,
                sortDirection: .descending,
                onSelectOption: { _ in },
                onSelectDirection: { _ in },
                onDismiss: {}
            )
        }
}
