#if os(macOS)
    import SwiftUI

    private enum Metrics {
        static let minHeight: CGFloat = 46
        static let iconColumn: CGFloat = .size20
        static let spacing: CGFloat = .space12
    }

    public struct MacChoiceRow: View {
        private let title: String
        private let subtitle: String?
        private let icon: Image
        private let isSelected: Bool
        private let action: () -> Void

        public static let textIndent: CGFloat = .space16 + Metrics.iconColumn + Metrics.spacing

        public init(
            _ title: String,
            subtitle: String? = nil,
            icon: Image,
            isSelected: Bool,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.subtitle = subtitle
            self.icon = icon
            self.isSelected = isSelected
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                HStack(spacing: Metrics.spacing) {
                    icon
                        .foregroundStyle(isSelected ? Color.accent : Color.secondaryDS)
                        .frame(width: Metrics.iconColumn)
                    VStack(alignment: .leading, spacing: .zero) {
                        Text(title).type(.body2(.semibold))
                        if let subtitle {
                            Text(subtitle).type(.caption(.regular), style: .secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    IconKit.checkmark
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.accent)
                        .opacity(isSelected ? 1 : 0)
                        .accessibilityHidden(true)
                }
                .macMinHeight(points: Metrics.minHeight)
                .padding(.horizontal, .space16)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            .animation(DSMotion.stateFade, value: isSelected)
        }
    }

    #Preview("Choice rows") {
        MacFormGroup {
            MacChoiceRow("View only", subtitle: "Open and read. No copies.", icon: IconKit.eye, isSelected: false) {}
            MacChoiceRow(
                "Can download",
                subtitle: "Open and download.",
                icon: IconKit.menuDownload,
                isSelected: true
            ) {}
            MacChoiceRow("Custom", subtitle: "Choose each permission.", icon: IconKit.sliders, isSelected: false) {}
        }
        .padding(.space24)
        .previewCanvasWidth(.sheet)
    }
#endif
