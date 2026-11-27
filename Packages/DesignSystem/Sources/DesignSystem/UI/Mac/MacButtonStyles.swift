#if os(macOS)
    import Localization
    import SwiftUI

    private enum Constants {
        static let hoverOpacity: Double = 0.06
        static let pressedOpacity: Double = .opacityFaint
    }

    extension DSButtonSize {
        var macHeight: MacControlHeight {
            switch self {
            case .large: .xLarge
            case .medium: .medium
            case .small: .small
            }
        }

        var macPadding: CGFloat {
            self == .small ? .space12 : .space16
        }

        var macTextType: Typography.TextType {
            self == .small ? .label4 : .label3
        }
    }

    public enum MacButtonTone: CaseIterable, Sendable {
        case neutral
        case success
        case accent

        var outlineColor: Color? {
            switch self {
            case .neutral: nil
            case .success: .positiveText
            case .accent: .accentText
            }
        }
    }

    extension DSButtonStyle {
        var macFill: Color {
            self == .secondary ? .macButtonRaised : backgroundColor
        }

        func macForeground(isDestructive: Bool, tone: MacButtonTone) -> Color {
            switch self {
            case .primary: .onAccent
            case .success, .failure, .inverted: .white
            case .outline: isDestructive ? .negativeText : tone.outlineColor ?? .macChromeText
            case .secondary, .ghost: isDestructive ? .negativeText : .macChromeText
            case .tertiary: isDestructive ? .negativeText : .accentText
            }
        }

        func macBorder(isDestructive: Bool, tone: MacButtonTone) -> Color {
            guard self == .outline else { return .clear }
            return isDestructive ? .negativeText : tone.outlineColor ?? .macChromeDisabled
        }
    }

    public struct MacDSButtonStyle: ButtonStyle {
        let style: DSButtonStyle
        let size: DSButtonSize
        let tone: MacButtonTone

        public init(style: DSButtonStyle, size: DSButtonSize, tone: MacButtonTone = .neutral) {
            self.style = style
            self.size = size
            self.tone = tone
        }

        public func makeBody(configuration: Configuration) -> some View {
            MacDSButtonBody(
                label: configuration.label,
                isPressed: configuration.isPressed,
                isDestructive: configuration.role == .destructive,
                style: style,
                size: size,
                tone: tone
            )
        }
    }

    public extension ButtonStyle where Self == MacDSButtonStyle {
        static func macDS(
            _ style: DSButtonStyle = .secondary,
            size: DSButtonSize = .medium,
            tone: MacButtonTone = .neutral
        ) -> MacDSButtonStyle {
            MacDSButtonStyle(style: style, size: size, tone: tone)
        }
    }

    private struct MacDSButtonBody<Label: View>: View {
        let label: Label
        let isPressed: Bool
        let isDestructive: Bool
        let style: DSButtonStyle
        let size: DSButtonSize
        let tone: MacButtonTone

        var body: some View {
            label
                .type(size.macTextType)
                .lineLimit(1)
                .foregroundStyle(style.macForeground(isDestructive: isDestructive, tone: tone))
                .padding(.horizontal, size.macPadding)
                .macMinHeight(size.macHeight)
                .background {
                    if style == .secondary {
                        MacButtonShape.pill.fill(style.macFill)
                            .elevation(.level1)
                    } else {
                        MacButtonShape.pill.fill(style.macFill)
                    }
                }
                .overlay(
                    MacButtonShape.pill.strokeBorder(
                        style.macBorder(isDestructive: isDestructive, tone: tone),
                        lineWidth: .borderWidthHairline
                    )
                )
                .modifier(MacButtonInteraction(shape: MacButtonShape.pill, isPressed: isPressed))
        }
    }

    public struct MacToolbarButtonStyle: ButtonStyle {
        let isAccent: Bool

        public init(isAccent: Bool = false) {
            self.isAccent = isAccent
        }

        public func makeBody(configuration: Configuration) -> some View {
            MacToolbarButtonBody(label: configuration.label, isPressed: configuration.isPressed, isAccent: isAccent)
        }
    }

    public extension ButtonStyle where Self == MacToolbarButtonStyle {
        static var macToolbar: MacToolbarButtonStyle {
            MacToolbarButtonStyle()
        }

        static var macToolbarAccent: MacToolbarButtonStyle {
            MacToolbarButtonStyle(isAccent: true)
        }
    }

    private struct MacToolbarButtonBody<Label: View>: View {
        let label: Label
        let isPressed: Bool
        let isAccent: Bool

        var body: some View {
            label
                .labelStyle(.iconOnly)
                .type(.body2(.regular))
                .macSquare(.iconSmall)
                .foregroundStyle(isAccent ? Color.onAccent : Color.macChromeText)
                .macSquare(MacControlHeight.large.points)
                .background(Circle().fill(isAccent ? Color.accent : Color.macChromeButton))
                .modifier(MacButtonInteraction(shape: Circle(), isPressed: isPressed))
        }
    }

    enum MacButtonShape {
        static let pill = Capsule(style: .continuous)
    }

    struct MacButtonInteraction<S: InsettableShape>: ViewModifier {
        let shape: S
        let isPressed: Bool
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.isFocused) private var isFocused
        @State private var isHovered = false

        func body(content: Content) -> some View {
            content
                .overlay(shape.fill(Color.macChromeText.opacity(tintOpacity)))
                .macFocusRing(isFocused, in: shape)
                .contentShape(shape)
                .macDisabledDim()
                .onHover { isHovered = $0 }
                .animation(DSMotion.quickFade, value: isHovered)
                .animation(DSMotion.quickFade, value: isPressed)
        }

        private var tintOpacity: Double {
            guard isEnabled else { return 0 }
            if isPressed {
                return Constants.pressedOpacity
            }
            return isHovered ? Constants.hoverOpacity : 0
        }
    }

    extension View {
        func macFocusRing(_ isFocused: Bool, in shape: some InsettableShape) -> some View {
            focusEffectDisabled()
                .overlay(
                    shape
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: .borderWidthFocused)
                        .opacity(isFocused ? 1 : 0)
                )
        }
    }

    public extension View {
        func macKeyFocus(_ isFocused: FocusState<Bool>.Binding) -> some View {
            background {
                Color.clear
                    .focusable()
                    .focused(isFocused)
                    .focusEffectDisabled()
            }
        }
    }

    #Preview("Buttons") {
        VStack(alignment: .leading, spacing: .space16) {
            ForEach(DSButtonSize.allCases, id: \.self) { size in
                HStack(spacing: .space8) {
                    Button(L10n.Common.save) {}.buttonStyle(.macDS(.primary, size: size))
                    Button(L10n.Common.cancel) {}.buttonStyle(.macDS(.secondary, size: size))
                    Button(L10n.Common.delete, role: .destructive) {}.buttonStyle(.macDS(.secondary, size: size))
                    Button(L10n.Common.remove) {}.buttonStyle(.macDS(.failure, size: size))
                    Button(L10n.Common.edit) {}.buttonStyle(.macDS(.outline, size: size))
                    Button(L10n.Common.share) {}.buttonStyle(.macDS(.tertiary, size: size))
                }
            }
            HStack(spacing: .space8) {
                ForEach(MacButtonTone.allCases, id: \.self) { tone in
                    Button(L10n.Common.edit) {}.buttonStyle(.macDS(.outline, size: .small, tone: tone))
                }
                Button(L10n.Common.delete, role: .destructive) {}.buttonStyle(.macDS(.outline, size: .small))
            }
            HStack(spacing: .space8) {
                Button(L10n.Common.save) {}.buttonStyle(.macDS(.primary)).disabled(true)
                Button(L10n.Common.cancel) {}.buttonStyle(.macDS(.secondary)).disabled(true)
            }
        }
        .padding(.space24)
        .background(Color.macRow)
    }

    #Preview("Toolbar buttons") {
        HStack(spacing: .space12) {
            Button {} label: { Label { Text(L10n.Common.more) } icon: { IconKit.moreOptions } }.buttonStyle(.macToolbar)
            Button {} label: { Label { Text(L10n.Common.share) } icon: { IconKit.link } }.buttonStyle(.macToolbar)
            Button {} label: { Label { Text(L10n.Common.download) } icon: { IconKit.upload } }
                .buttonStyle(.macToolbarAccent)
            Button {} label: { Label { Text(L10n.Common.more) } icon: { IconKit.moreOptions } }.buttonStyle(.macToolbar)
                .disabled(true)
        }
        .padding(.space24)
        .background(Color.macChrome)
    }
#endif
