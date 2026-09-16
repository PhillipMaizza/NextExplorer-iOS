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

        /// Lazily registers the font on first access. Previews never run `NextExplorerApp.init()`,
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
            case let .body1(trait), let .body2(trait),
                 let .body3(trait), let .caption(trait):
                trait.weight
            case .label1: .semibold
            case .label2: .semibold
            case .label3: .semibold
            case .label4: .semibold
            }
        }

        /// The tier's weight, bumped one step heavier when the system Bold Text accessibility
        /// setting is on. A system font inherits Bold Text for free; the custom Figtree font
        /// does not, so the DS text modifier feeds `legibilityWeight` through here instead.
        public func weight(boldText: Bool) -> Font.Weight {
            boldText ? Self.bolder(weight) : weight
        }

        private static func bolder(_ weight: Font.Weight) -> Font.Weight {
            switch weight {
            case .ultraLight: .thin
            case .thin: .light
            case .light: .regular
            case .regular: .semibold
            case .medium: .semibold
            case .semibold: .bold
            case .bold: .heavy
            case .heavy: .black
            default: .bold
            }
        }

        /// The system text style each tier scales against so the custom Figtree font tracks
        /// Dynamic Type. `Font.custom(_:size:relativeTo:)` runs the base `size` through
        /// `UIFontMetrics` for this style, which a bare `Font.custom(_:size:)` never does.
        private var relativeTextStyle: Font.TextStyle {
            switch self {
            case .display, .headline1: .largeTitle
            case .headline2, .headline3: .title
            case .headline4, .subtitle1, .label1: .title2
            case .label2: .title3
            case .subtitle2, .body1, .body2, .label3: .body
            case .body3, .label4: .subheadline
            case .caption: .caption
            }
        }

        public func font() -> Font {
            _ = Self.fontsRegistered
            return .custom(Self.familyName, size: size, relativeTo: relativeTextStyle)
        }
    }

    /// Text color roles.
    public enum TextStyle {
        /// Primary text on a plain surface (the app background or a card).
        case primaryOnSurface
        /// Primary text on a filled accent surface (a filled button), inverted for contrast.
        case primaryOnAccent
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
            case .primaryOnSurface: .primaryDS
            case .primaryOnAccent: .primaryInverted
            case .secondary: .secondaryDS
            case .tertiary: .tertiaryDS
            case .disabled: .tertiaryDS
            case .inverted: .primaryInverted
            case .invertedSecondary: .secondaryInverted
            case .success: .positiveText
            case .link: .accentText
            case .error: .negativeText
            case .warning: .attention
            case let .custom(color): color
            }
        }
    }
}

public extension View {
    /// Applies a Design System text type (font + weight) to any view. Runs through
    /// `DSTextTypeModifier` so the weight honors the system Bold Text accessibility setting,
    /// which the custom Figtree font would otherwise ignore.
    func type(_ type: Typography.TextType) -> some View {
        modifier(DSTextTypeModifier(type: type))
    }

    /// Applies both a text type (font + weight) and style (color) in one call.
    func type(_ type: Typography.TextType, style: Typography.TextStyle) -> some View {
        modifier(DSTextTypeModifier(type: type)).foregroundColor(style.color)
    }

    /// Applies a Design System text style (color) to any view.
    func style(_ style: Typography.TextStyle) -> some View {
        foregroundColor(style.color)
    }
}

/// Applies a text tier's font and Bold-Text-aware weight. A `ViewModifier` (not a `Text`
/// extension) so it can read `legibilityWeight` from the environment.
private struct DSTextTypeModifier: ViewModifier {
    let type: Typography.TextType
    @Environment(\.legibilityWeight) private var legibilityWeight

    func body(content: Content) -> some View {
        content
            .font(type.font())
            .fontWeight(type.weight(boldText: legibilityWeight == .bold))
    }
}
