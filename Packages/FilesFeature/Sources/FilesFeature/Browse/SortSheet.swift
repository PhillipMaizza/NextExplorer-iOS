import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let contentSpacing: CGFloat = .space24
    static let rowSpacing: CGFloat = .space12
    static let rowVerticalPadding: CGFloat = .space16
    static let horizontalPadding: CGFloat = .space24
    static let topPadding: CGFloat = .space24
    static let bottomPadding: CGFloat = .space24
    static let rowIconSize: CGFloat = .iconSmall
    static let radioSize: CGFloat = .iconSmall
    static let selectionAnimationDuration: Double = 0.2
    static let fullOpacity: Double = 1.0
    static let zeroOpacity: Double = 0.0
    static let toolbarButtonWidth: CGFloat = .iconMedium
    static let toolbarButtonHeight: CGFloat = .iconSmall
}

/// The single toolbar button that opens a screen's `SortSheet`. One look everywhere it
/// appears (Shared, User Management): a `primaryDS` sort glyph, disabled when there's nothing
/// to sort. Drop it inside a `ToolbarItem`.
struct SortToolbarButton: View {
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        #if os(macOS)
            // The Mac toolbar sizes and styles its own items; a hand sized icon and custom
            // button style made this one stand out from every other toolbar control.
            Button(action: action) {
                IconKit.sort
                    .foregroundStyle(Color.primaryDS)
            }
            .disabled(isDisabled)
            .accessibilityLabel(L10n.Common.sort)
            .help(L10n.Common.sort)
        #else
            Button(action: action) {
                IconKit.sort
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.toolbarButtonWidth, height: Constants.toolbarButtonHeight)
                    .foregroundStyle(Color.primaryDS)
            }
            .buttonStyle(DSHapticButtonStyle())
            .disabled(isDisabled)
            .accessibilityLabel(L10n.Common.sort)
        #endif
    }
}

extension ToolbarItemPlacement {
    /// Where a screen's sort button sits: leading on a Mac, so the toolbar search field keeps
    /// the trailing edge; trailing on iOS as before.
    static var sortControl: ToolbarItemPlacement {
        #if os(macOS)
            .navigation
        #else
            .primaryAction
        #endif
    }
}

/// Generic "Sort by" sheet: a field picker and a direction picker as radio lists in a
/// `DSDynamicHeightSheet`. Shared by Browse, Favorites, Downloads, Shared and User Management,
/// generalized over whatever option and direction enum each screen sorts by.
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
        DSDynamicHeightSheet {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            DSSheetHeader(
                icon: IconKit.sort,
                title: L10n.Sort.sheetTitle,
                closeAccessibilityLabel: L10n.Common.close,
                onClose: onDismiss
            )

            VStack(spacing: 0) {
                ForEach(options, id: \.self) { option in
                    radioRow(icon: optionIcon(option), title: optionTitle(option), isSelected: option == sortOption) {
                        onSelectOption(option)
                    }
                }
            }
            .dsCard()

            VStack(spacing: 0) {
                ForEach(directions, id: \.self) { direction in
                    radioRow(icon: directionIcon(direction), title: directionTitle(direction), isSelected: direction == sortDirection) {
                        onSelectDirection(direction)
                    }
                }
            }
            .dsCard()
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
                    .type(.body1(isSelected ? .semibold : .regular), style: .primaryOnSurface)
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
        .animation(.easeInOut(duration: Constants.selectionAnimationDuration), value: isSelected)
        .hapticFeedback(.selection, trigger: isSelected)
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SortSheet(
                options: BrowseFeature.SortOption.allCases,
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
