#if os(macOS)
    import Localization
    import SwiftUI

    public struct MacSplitButton<Label: View, Items: View>: View {
        private let menuLabel: String
        private let action: () -> Void
        private let label: Label
        private let items: () -> Items

        public init(
            menuLabel: String,
            action: @escaping () -> Void,
            @ViewBuilder label: () -> Label,
            @ViewBuilder items: @escaping () -> Items
        ) {
            self.menuLabel = menuLabel
            self.action = action
            self.label = label()
            self.items = items
        }

        public var body: some View {
            HStack(spacing: .borderWidthHairline) {
                Button(action: action) { label }
                    .buttonStyle(MacSplitHalfStyle(padding: DSButtonSize.medium.macPadding))
                Menu(content: items) {
                    IconKit.chevronDown
                        .imageScale(.small)
                        .fontWeight(.semibold)
                }
                .menuStyle(.button)
                .buttonStyle(MacSplitHalfStyle(padding: .space12))
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabelWithTooltip(menuLabel)
            }
            .clipShape(MacButtonShape.pill)
            .macDisabledDim()
        }
    }

    private struct MacSplitHalfStyle: ButtonStyle {
        let padding: CGFloat

        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .type(DSButtonSize.medium.macTextType)
                .lineLimit(1)
                .foregroundStyle(DSButtonStyle.primary.macForeground(isDestructive: false, tone: .neutral))
                .padding(.horizontal, padding)
                .macMinHeight(DSButtonSize.medium.macHeight)
                .background(DSButtonStyle.primary.macFill)
                .modifier(MacButtonInteraction(shape: Rectangle(), isPressed: configuration.isPressed))
        }
    }

    #Preview("Split button") {
        VStack(spacing: .space16) {
            MacSplitButton(menuLabel: L10n.Common.more, action: {}) {
                Text(verbatim: "Open in Archive Utility")
            } items: {
                Button {} label: { Text(verbatim: "The Unarchiver") }
            }
            MacSplitButton(menuLabel: L10n.Common.more, action: {}) {
                Text(verbatim: "Open in Preview")
            } items: {
                Button {} label: { Text(verbatim: "Pixelmator Pro") }
            }
            .disabled(true)
        }
        .padding(.space24)
        .background(Color.macCard)
    }
#endif
