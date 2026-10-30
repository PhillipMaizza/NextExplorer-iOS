import SwiftUI

private enum Metrics {
    static let valueSpacing: CGFloat = .space4
    static let chevronSize: CGFloat = .iconXSmall
}

/// A grouped list row with a menu picker: label on the leading side, current value on the
/// trailing side. On iOS it is exactly a menu style `Picker`, which a `List` already lays out
/// that way; a Mac grouped list is a plain stack, so the Mac draws the row itself, with the
/// value in the same type as a `DSNavigationRow` detail.
public struct DSMenuPickerRow<Selection: Hashable, Options: View, RowLabel: View>: View {
    @Binding private var selection: Selection
    private let value: String
    private let options: Options
    private let label: RowLabel

    /// `value` is the current selection's title, shown as the Mac row's trailing detail.
    public init(
        selection: Binding<Selection>,
        value: String,
        @ViewBuilder options: () -> Options,
        @ViewBuilder label: () -> RowLabel
    ) {
        _selection = selection
        self.value = value
        self.options = options()
        self.label = label()
    }

    public var body: some View {
        #if os(macOS)
            // The whole row is the menu's label, so a click anywhere across it opens the menu.
            Menu {
                Picker(selection: $selection) {
                    options
                } label: {
                    label
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack {
                    label
                    Spacer(minLength: .space16)
                    HStack(spacing: Metrics.valueSpacing) {
                        Text(value).type(.body2(.regular), style: .secondary)
                        IconKit.chevronUpDown
                            .resizable()
                            .scaledToFit()
                            .fontWeight(.semibold)
                            .frame(width: Metrics.chevronSize, height: Metrics.chevronSize)
                            .foregroundStyle(Color.secondaryDS)
                    }
                }
                .fullRowHitArea()
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
        #else
            Picker(selection: $selection) {
                options
            } label: {
                label
            }
            .pickerStyle(.menu)
        #endif
    }
}

#Preview("Menu picker rows") {
    @Previewable @State var size = "Medium"
    @Previewable @State var appearance = "System"
    DSGroupedList {
        Section {
            DSMenuPickerRow(selection: $appearance, value: appearance) {
                ForEach(["System", "Light", "Dark"], id: \.self) { Text($0).tag($0) }
            } label: {
                Label { Text(verbatim: "Appearance") } icon: { IconKit.darkMode }
            }
            DSMenuPickerRow(selection: $size, value: size) {
                ForEach(["Small", "Medium", "Large"], id: \.self) { Text($0).tag($0) }
            } label: {
                Label { Text(verbatim: "Thumbnail Size") } icon: { IconKit.squareGrid }
            }
        }
    }
    .tint(Color.secondaryDS)
}
