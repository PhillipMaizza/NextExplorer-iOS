import SwiftUI

#if os(macOS)
    private enum Metrics {
        static let sectionSpacing: CGFloat = .space24
        static let headerSpacing: CGFloat = .space8
        static let rowHorizontalPadding: CGFloat = .space16
        static let rowVerticalPadding: CGFloat = .space12
        static let contentPadding: CGFloat = .space16
        static let cornerRadius: CGFloat = .radiusLarge
        static let hoverOpacity: Double = 0.06
    }

    /// macOS has no inset grouped list style, and a grouped `Form` caps itself at a narrow
    /// readable width. So the Mac draws the grouped look itself: each `Section` becomes a full
    /// width rounded card with dividers between rows, laid out lazily so large folders stay
    /// cheap. List only modifiers at call sites (row backgrounds, insets, separators) are
    /// ignored here; actions that were swipe only need a context menu on the Mac.
    public struct DSGroupedList<Content: View>: View {
        private let content: Content

        public init(@ViewBuilder content: () -> Content) {
            self.content = content()
        }

        public init<Data: RandomAccessCollection, RowContent: View>(
            _ data: Data,
            @ViewBuilder rowContent: @escaping (Data.Element) -> RowContent
        ) where Data.Element: Identifiable, Content == ForEach<Data, Data.Element.ID, RowContent> {
            content = ForEach(data, content: rowContent)
        }

        @Environment(\.groupedListRowVerticalPadding) private var rowVerticalPadding
        @Environment(\.groupedListRowHover) private var highlightsRowsOnHover

        public var body: some View {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    ForEach(sections: content) { section in
                        sectionCard(section)
                    }
                }
                .padding(Metrics.contentPadding)
            }
            // Row defaults matching an iOS list: navigation rows and buttons read as rows rather
            // than bezeled push buttons, and toggles are switches rather than checkboxes. An
            // explicit style at a call site still wins.
            .buttonStyle(.plain)
            .toggleStyle(.switch)
        }

        private func sectionCard(_ section: SectionConfiguration) -> some View {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                if !section.header.isEmpty {
                    section.header
                        .type(.body2(.semibold), style: .secondary)
                        .padding(.horizontal, Metrics.rowHorizontalPadding)
                }
                if !section.content.isEmpty {
                    LazyVStack(spacing: 0) {
                        ForEach(subviews: section.content) { row in
                            row
                                .padding(.horizontal, Metrics.rowHorizontalPadding)
                                .padding(.vertical, rowVerticalPadding ?? Metrics.rowVerticalPadding)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .modifier(RowHover(isEnabled: highlightsRowsOnHover))
                            if row.id != section.content.last?.id {
                                Divider().padding(.leading, Metrics.rowHorizontalPadding)
                            }
                        }
                    }
                    .background(Color.backgroundSecondary, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
                }
                if !section.footer.isEmpty {
                    section.footer
                        .type(.body3(.regular), style: .secondary)
                        .padding(.horizontal, Metrics.rowHorizontalPadding)
                }
            }
        }
    }

    /// Full row hover fill; the card's clip shape rounds it at the first and last row.
    private struct RowHover: ViewModifier {
        let isEnabled: Bool
        @State private var isHovering = false

        func body(content: Content) -> some View {
            if isEnabled {
                content
                    .background(Color.primaryDS.opacity(isHovering ? Metrics.hoverOpacity : 0))
                    .onHover { isHovering = $0 }
            } else {
                content
            }
        }
    }
#else
    /// On iOS the grouped list is exactly a `List`, so every existing modifier and scroll
    /// behavior applies to the real list view unchanged.
    public typealias DSGroupedList<Content: View> = List<Never, Content>
#endif

public extension EnvironmentValues {
    @Entry var groupedListRowVerticalPadding: CGFloat?
    @Entry var groupedListRowHover = false
}

public extension View {
    /// Overrides the vertical padding of every row in a `DSGroupedList` on macOS. iOS rows keep
    /// the system list metrics.
    func groupedListRowVerticalPadding(_ padding: CGFloat) -> some View {
        environment(\.groupedListRowVerticalPadding, padding)
    }

    /// On macOS, fills a whole row (edge to edge inside its card) while the pointer is over it,
    /// for lists whose rows are clickable items. iOS has no hover.
    func groupedListRowHover() -> some View {
        environment(\.groupedListRowHover, true)
    }
}

#Preview("Grouped list") {
    DSGroupedList {
        Section("Folders") {
            ForEach(["Files", "Photos", "Music"], id: \.self) { name in
                Label(name, systemImage: "folder.fill")
            }
        }
        Section("Documents") {
            ForEach(["Report.pdf", "Notes.txt"], id: \.self) { name in
                Label(name, systemImage: "doc")
            }
        }
    }
    .listStyle(.insetGrouped)
}
