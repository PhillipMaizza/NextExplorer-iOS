#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacPickerList<Row: Identifiable, RowLabel: View>: View {
        let rows: [Row]
        @Binding var selection: Row.ID?
        let onOpen: (Row) -> Void
        @ViewBuilder let label: (Row) -> RowLabel
        @FocusState private var isFocused: Bool

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: .zero) {
                        ForEach(rows) { row in
                            rowView(row)
                        }
                    }
                }
                .focusable()
                .focused($isFocused)
                .focusEffectDisabled()
                .onKeyPress(.downArrow) { move(by: 1, proxy) }
                .onKeyPress(.upArrow) { move(by: -1, proxy) }
            }
        }

        private func rowView(_ row: Row) -> some View {
            let isSelected = row.id == selection
            return label(row)
                .macListRow(isSelected: isSelected)
                .id(row.id)
                .onTapGesture(count: 2) { onOpen(row) }
                .simultaneousGesture(TapGesture().onEnded {
                    selection = row.id
                    isFocused = true
                })
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
                .accessibilityAction { selection = row.id }
                .accessibilityAction(named: L10n.Browse.open) { onOpen(row) }
        }

        private func move(by offset: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
            let ids = rows.map(\.id)
            let current = selection.flatMap { ids.firstIndex(of: $0) }
            let index = current.map { $0 + offset } ?? (offset > 0 ? 0 : ids.count - 1)
            guard ids.indices.contains(index) else { return .handled }
            selection = ids[index]
            proxy.scrollTo(ids[index])
            return .handled
        }
    }

    private struct PreviewRow: Identifiable {
        let id: String
    }

    #Preview("Picker list") {
        @Previewable @State var selection: String? = "Photos"
        MacPickerList(
            rows: ["Documents", "Photos", "Projects"].map(PreviewRow.init),
            selection: $selection,
            onOpen: { _ in }
        ) { row in
            Text(row.id).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 320, height: 160)
        .macListBox()
        .padding()
    }
#endif
