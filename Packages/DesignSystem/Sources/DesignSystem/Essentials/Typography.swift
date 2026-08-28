import SwiftUI

public enum Typography {
    public enum Trait {
        case bold
        case semibold
        case regular

        var weight: Font.Weight {
            switch self {
            case .bold: .bold
            case .semibold: .semibold
            case .regular: .regular
            }
        }
    }
    /// Font size/weight tiers. Separate from `TextStyle` (color) so either can vary independently.
    ///
    /// Backed by the Figtree variable font (registered lazily on first use, see
    /// `TextType.fontsRegistered` below). Its default instance is Light, so every tier
    /// applies an explicit weight; never rely on the font's own default.
    public enum TextType {
        case display
        case headline1
        case headline2
        case headline3
        case headline4
        case subtitle1
        case subtitle2
        case body1(Trait)
        case body2(Trait)
        case body3(Trait)
        case caption(Trait)
        case label1
        case label2
        case label3
        case label4

        private static let familyName = "Figtree"

        /// Lazily registers the font on first access. Previews never run `NEXTExplorerApp.init()`,
        /// and `Font.custom` silently falls back to the system font if "Figtree" isn't registered.
        private static let fontsRegistered: Void = DesignSystemFonts.registerAll()

        public var size: CGFloat {
            switch self {
            case .display: 64
            case .headline1: 48
            case .headline2: 32
            case .headline3: 24
            case .headline4: 20
            case .subtitle1: 20
            case .subtitle2: 16
            case .body1: 18
            case .body2: 16
            case .body3: 14
            case .caption: 12
            case .label1: 24
            case .label2: 20
            case .label3: 16
            case .label4: 14
            }
        }

        public var weight: Font.Weight {
            switch self {
            case .display: .bold
            case .headline1: .bold
            case .headline2: .semibold
            case .headline3: .semibold
            case .headline4: .semibold
            case .subtitle1: .regular
            case .subtitle2: .regular
            case .body1(let trait), .body2(let trait),
                    .body3(let trait), .caption(let trait):
                trait.weight
            case .label1: .semibold
            case .label2: .semibold
            case .label3: .semibold
            case .label4: .semibold
            }
        }

        public func font() -> Font {
            _ = Self.fontsRegistered
            return .custom(Self.familyName, size: size)
        }
    }

    /// Text color roles.
    public enum TextStyle {
        public enum Target {
            case label
            case button
        }

        case primary(for: Target)
        case secondary
        case tertiary
        case disabled
        case inverted
        case invertedSecondary
        case success
        case link
        case error
        case warning
        case custom(Color)

        public var color: Color {
            switch self {
            case .primary(let target):
                target == .button ? .primaryInverted : .primaryDS
            case .secondary: .secondaryDS
            case .tertiary: .tertiaryDS
            case .disabled: .tertiaryDS
            case .inverted: .primaryInverted
            case .invertedSecondary: .secondaryInverted
            case .success: .positive
            case .link: .accent
            case .error: .negative
            case .warning: .attention
            case .custom(let color): color
            }
        }
    }
}

public extension Text {
    /// Applies a Design System text type (font + weight) to the text.
    func type(_ type: Typography.TextType) -> Text {
        font(type.font()).fontWeight(type.weight)
    }

    /// Applies a Design System text style (color) to the text.
    func style(_ style: Typography.TextStyle) -> Text {
        foregroundColor(style.color)
    }

    /// Applies both a text type (font + weight) and style (color) in one call.
    func type(_ type: Typography.TextType, style: Typography.TextStyle) -> Text {
        font(type.font()).fontWeight(type.weight).foregroundColor(style.color)
    }
}

public extension View {
    /// Applies a Design System text type (font + weight) to any view, chiefly for
    /// `TextField`/`SecureField`, which aren't `Text` and so can't use `Text.type(_:)`.
    func type(_ type: Typography.TextType) -> some View {
        font(type.font()).fontWeight(type.weight)
    }
}
