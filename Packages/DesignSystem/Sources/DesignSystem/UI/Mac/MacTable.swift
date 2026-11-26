#if os(macOS)
    import SwiftUI

    public enum MacTableMetrics {
        public static let rowHeight: CGFloat = .size40
        public static let columnSpacing: CGFloat = .space12
        static let rowInset: CGFloat = .space12
        static let headerHeight: CGFloat = 30
        static let sortGlyphSize: CGFloat = 9
        static let selectionOpacity: Double = .opacitySelection
        static let listRowHeight: CGFloat = .size32
        static let rowShape = RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
    }

    public struct MacTableEmptyLine: View {
        private let text: String

        public init(_ text: String) {
            self.text = text
        }

        public var body: some View {
            Text(text)
                .type(.body2(.regular), style: .secondary)
                .padding(.horizontal, MacTableMetrics.rowInset)
                .frame(height: MacTableMetrics.rowHeight)
        }
    }

    public struct MacTableHeader<Content: View>: View {
        private let content: () -> Content

        public init(@ViewBuilder content: @escaping () -> Content) {
            self.content = content
        }

        public var body: some View {
            HStack(spacing: MacTableMetrics.columnSpacing) {
                content()
            }
            .padding(.horizontal, MacTableMetrics.rowInset)
            .frame(height: MacTableMetrics.headerHeight)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Color.macLine)
                    .frame(height: .borderWidthHairline)
            }
            .padding(.bottom, .space4)
        }
    }

    public struct MacTableColumnTitle: View {
        private let title: String

        public init(_ title: String) {
            self.title = title
        }

        public var body: some View {
            Text(title)
                .type(.body3(.semibold))
                .foregroundStyle(Color.macChromeSecondary)
        }
    }

    public struct MacTableSortHeader: View {
        private let title: String
        private let isSorted: Bool
        private let isAscending: Bool
        private let action: () -> Void

        public init(_ title: String, isSorted: Bool, isAscending: Bool, action: @escaping () -> Void) {
            self.title = title
            self.isSorted = isSorted
            self.isAscending = isAscending
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                HStack(spacing: .space4) {
                    Text(title)
                    if isSorted {
                        (isAscending ? IconKit.chevronUp : IconKit.chevronDown)
                            .resizable()
                            .scaledToFit()
                            .frame(width: MacTableMetrics.sortGlyphSize, height: MacTableMetrics.sortGlyphSize)
                    }
                }
                .type(.body3(.semibold))
                .foregroundStyle(isSorted ? Color.macChromeText : .macChromeSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSorted ? .isSelected : [])
        }
    }

    public extension View {
        func macTableRow(isShaded: Bool, isSelected: Bool = false) -> some View {
            padding(.horizontal, MacTableMetrics.rowInset)
                .frame(height: MacTableMetrics.rowHeight)
                .background(
                    MacTableMetrics.rowShape
                        .fill(isSelected
                            ? Color.accent.opacity(MacTableMetrics.selectionOpacity)
                            : isShaded ? Color.macRow : .clear)
                )
                .contentShape(MacTableMetrics.rowShape)
        }

        func macTableBleed() -> some View {
            padding(.horizontal, -MacTableMetrics.rowInset)
        }

        func macListBox() -> some View {
            let shape = RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
            return background(shape.fill(Color.macField))
                .clipShape(shape)
                .overlay(shape.strokeBorder(Color.macLine, lineWidth: .borderWidthHairline))
        }

        func macListRow(isSelected: Bool) -> some View {
            padding(.horizontal, MacTableMetrics.rowInset)
                .frame(minHeight: MacTableMetrics.listRowHeight)
                .background(isSelected ? Color.accent.opacity(MacTableMetrics.selectionOpacity) : .clear)
                .contentShape(Rectangle())
        }
    }

    public struct MacTableRowButton<Label: View>: View {
        let isShaded: Bool
        let isSelected: Bool
        let action: () -> Void
        @ViewBuilder let label: () -> Label

        public init(
            isShaded: Bool,
            isSelected: Bool,
            action: @escaping () -> Void,
            @ViewBuilder label: @escaping () -> Label
        ) {
            self.isShaded = isShaded
            self.isSelected = isSelected
            self.action = action
            self.label = label
        }

        public var body: some View {
            Button(action: action) {
                label()
                    .lineLimit(1)
                    .foregroundStyle(Color.macChromeText)
                    .macTableRow(isShaded: isShaded, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    #Preview("Row buttons") {
        VStack(spacing: .zero) {
            MacTableRowButton(isShaded: false, isSelected: false, action: {}) { Text(verbatim: "Plain") }
            MacTableRowButton(isShaded: true, isSelected: false, action: {}) { Text(verbatim: "Shaded") }
            MacTableRowButton(isShaded: false, isSelected: true, action: {}) { Text(verbatim: "Selected") }
        }
        .padding(.space16)
        .frame(width: 420)
    }

    #Preview("Table") {
        VStack(spacing: .zero) {
            MacTableHeader {
                MacTableSortHeader("Name", isSorted: true, isAscending: true) {}
                    .frame(maxWidth: .infinity, alignment: .leading)
                MacTableColumnTitle("Email")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ForEach(0 ..< 4) { index in
                HStack {
                    Text(verbatim: "Row \(index + 1)")
                    Spacer()
                }
                .foregroundStyle(Color.macChromeText)
                .macTableRow(isShaded: index.isMultiple(of: 2), isSelected: index == 1)
            }
        }
        .padding()
        .previewCanvasWidth(.dialog)
        .background(Color.macCard)
    }

    #Preview("List box") {
        VStack(spacing: .zero) {
            ForEach(["archive", "projects", "media"], id: \.self) { name in
                HStack {
                    Text(verbatim: name)
                    Spacer()
                }
                .foregroundStyle(Color.macChromeText)
                .macListRow(isSelected: name == "projects")
            }
        }
        .background(Color.macField)
        .padding()
        .previewCanvasWidth(.control)
        .background(Color.macCard)
    }
#endif
