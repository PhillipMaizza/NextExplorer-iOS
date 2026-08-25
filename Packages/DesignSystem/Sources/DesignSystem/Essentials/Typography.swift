import SwiftUI

public enum Typography {
    /// Font size/weight tiers. Separate from `TextStyle` (color) so either can vary independently.
    ///
    /// Backed by the Figtree variable font (registered lazily on first use — see
    /// `TextType.fontsRegistered` below). Its default instance is Light, so every tier
    /// applies an explicit weight — never rely on the font's own default.
    public enum TextType {
        /// Bold, 28pt
        case headline1
        /// Regular, 17pt
        case body1
        /// Semibold, 17pt — button labels
        case body2
        /// Semibold, 19pt — primary CTA button labels
        case button
        /// Regular, 12pt — section labels, captions
        case label1

        private static let familyName = "Figtree"

        /// Lazily registers the font on first access — previews never run `NetxExplorerApp.init()`,
        /// and `Font.custom` silently falls back to the system font if "Figtree" isn't registered.
        private static let fontsRegistered: Void = DesignSystemFonts.registerAll()

        public var size: CGFloat {
            switch self {
            case .headline1: 28
            case .body1: 17
            case .body2: 17
            case .button: 19
            case .label1: 12
            }
        }

        public var weight: Font.Weight {
            switch self {
            case .headline1: .bold
            case .body1: .regular
            case .body2: .semibold
            case .button: .semibold
            case .label1: .regular
            }
        }

        public func font() -> Font {
            _ = Self.fontsRegistered
            return .custom(Self.familyName, size: size)
        }
    }

    /// Text color roles.
    public enum TextStyle {
        case primary
        case secondary
        case positive
        case negative
        case warning
        case accent

        public var color: Color {
            switch self {
            case .primary: .primaryDS
            case .secondary: .secondaryDS
            case .positive: .positive
            case .negative: .negative
            case .warning: .attention
            case .accent: .accent
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
    /// Applies a Design System text type (font + weight) to any view — chiefly for
    /// `TextField`/`SecureField`, which aren't `Text` and so can't use `Text.type(_:)`.
    func type(_ type: Typography.TextType) -> some View {
        font(type.font()).fontWeight(type.weight)
    }
}
