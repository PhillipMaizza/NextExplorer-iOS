#if os(iOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let tileSpacing: CGFloat = .space12
        static let tilePadding: CGFloat = .space16
        static let tileContentSpacing: CGFloat = .space4
        static let selectedFillOpacity: Double = 0.16
        static let indicatorSize: CGFloat = .size20
        /// Glyphs are sized as type, not stretched into a square, so wide ones (people) keep their weight.
        static let glyphPointSize: CGFloat = .iconSmall
        static let glyphColumn: CGFloat = .iconMedium
        static let rowSpacing: CGFloat = .space16
        static let textIndent: CGFloat = glyphColumn + rowSpacing
        /// The list's own side inset, so glyphs line up with the lock and the People row below.
        static let rowSideInset: CGFloat = .space16 + .space4
        static let rowInsets = EdgeInsets(
            top: .space12,
            leading: rowSideInset,
            bottom: .space12,
            trailing: rowSideInset
        )
    }

    /// One pick out of a few described options: rows with a check on iPhone, side by side tiles
    /// where the sheet is wide enough to compare them at a glance.
    struct EditShareChoices<Option: Hashable>: View {
        let options: [Option]
        let selection: Option
        let title: (Option) -> String
        let hint: (Option) -> String
        let icon: (Option) -> Image
        let onSelect: (Option) -> Void

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass

        var body: some View {
            if horizontalSizeClass == .regular {
                HStack(spacing: Constants.tileSpacing) {
                    ForEach(options, id: \.self) { option in
                        EditShareChoiceTile(
                            title: title(option),
                            hint: hint(option),
                            icon: icon(option),
                            isSelected: option == selection,
                            action: { onSelect(option) }
                        )
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .clearRow()
            } else {
                ForEach(options, id: \.self) { option in
                    EditShareChoiceRow(
                        title: title(option),
                        hint: hint(option),
                        icon: icon(option),
                        isSelected: option == selection,
                        action: { onSelect(option) }
                    )
                }
            }
        }
    }

    /// A described option as a list row: glyph, title and check on one line, what it means
    /// underneath, lined up with the title.
    private struct EditShareChoiceRow: View {
        let title: String
        let hint: String
        let icon: Image
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: .space2) {
                    HStack(spacing: Constants.rowSpacing) {
                        icon
                            .font(.system(size: Constants.glyphPointSize))
                            .foregroundStyle(Color.tertiaryDS)
                            .frame(width: Constants.glyphColumn)
                        Text(title).type(.body2(.semibold), style: .primaryOnSurface)
                        Spacer(minLength: .space8)
                        EditShareCheck(isSelected: isSelected)
                    }
                    Text(hint)
                        .type(.body3(.regular), style: .secondary)
                        .padding(.leading, Constants.textIndent)
                        .padding(.trailing, Constants.indicatorSize + Constants.rowSpacing)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableButtonStyle())
            .listRowInsets(Constants.rowInsets)
            .alignmentGuide(.listRowSeparatorLeading) { _ in Constants.textIndent }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .hapticFeedback(.selection, trigger: isSelected)
        }
    }

    /// The pick mark of both layouts: a hollow ring crossfading into a filled accent circle with
    /// its check knocked out, which pops as it lands.
    private struct EditShareCheck: View {
        let isSelected: Bool

        var body: some View {
            ZStack {
                IconKit.radioUnselected
                    .resizable()
                    .foregroundStyle(Color.secondaryDS)
                    .opacity(isSelected ? 0 : 1)
                IconKit.checkmarkCircleFill
                    .resizable()
                    .foregroundStyle(Color.accent)
                    .opacity(isSelected ? 1 : 0)
                    .symbolEffect(.bounce, value: isSelected)
            }
            .frame(width: Constants.indicatorSize, height: Constants.indicatorSize)
            .animation(DSMotion.stateFade, value: isSelected)
            .accessibilityHidden(true)
        }
    }

    /// A described option as a card: glyph and check on top, title and what it means below.
    private struct EditShareChoiceTile: View {
        let title: String
        let hint: String
        let icon: Image
        let isSelected: Bool
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                VStack(alignment: .leading, spacing: Constants.tileContentSpacing) {
                    HStack {
                        icon
                            .font(.system(size: Constants.glyphPointSize))
                            .foregroundStyle(isSelected ? Color.accentText : Color.tertiaryDS)
                        Spacer(minLength: .space8)
                        EditShareCheck(isSelected: isSelected)
                    }
                    Text(title).type(.body2(.semibold), style: .primaryOnSurface)
                    Text(hint).type(.body3(.regular), style: .secondary)
                }
                .padding(Constants.tilePadding)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(
                    RoundedRectangle(cornerRadius: .radiusCard, style: .continuous)
                        .fill(isSelected
                            ? Color.accent.opacity(Constants.selectedFillOpacity)
                            : Color.backgroundSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: .radiusCard, style: .continuous)
                        .strokeBorder(isSelected ? Color.accent : Color.clear, lineWidth: .borderWidthFocused)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .animation(DSMotion.stateFade, value: isSelected)
            .hapticFeedback(.selection, trigger: isSelected)
        }
    }

    private struct ChoicesPreview: View {
        @State private var mode = ShareAccessMode.readwrite

        var body: some View {
            DSGroupedList {
                Section {
                    EditShareChoices(
                        options: ShareAccessMode.allCases,
                        selection: mode,
                        title: \.title,
                        hint: { $0.hint(isDirectory: true) },
                        icon: \.icon,
                        onSelect: { mode = $0 }
                    )
                }
            }
            .sharedSheetList()
        }
    }

    #Preview("Rows") {
        ChoicesPreview()
    }

    #Preview("Tiles, dark") {
        ChoicesPreview()
            .environment(\.horizontalSizeClass, .regular)
            .preferredColorScheme(.dark)
    }

    #Preview("Rows, large type") {
        ChoicesPreview()
            .dynamicTypeSize(.accessibility2)
    }
#endif
