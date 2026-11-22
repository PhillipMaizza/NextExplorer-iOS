import SwiftUI

/// Shared style/size vocabulary for every button in the design system:
/// `DSButton` and `DSAnimatedButton` both key off these.
public enum DSButtonStyle: CaseIterable, Hashable {
    /// Filled accent background: primary call to action.
    case primary
    /// Filled surface background: secondary action.
    case secondary
    /// Transparent background, accent text: low emphasis inline action.
    case tertiary
    /// Transparent, no border, no lift, neutral text: a dismiss ("Cancel") that shouldn't
    /// compete with the primary CTA beside it. Unlike `.tertiary` the label isn't accent.
    case ghost
    /// Clear background, hairline border, neutral text: a lighter dismiss than `.secondary`
    /// (which fills a surface) for pairing beside a filled primary without competing with it.
    case outline
    /// Filled positive background: confirms a completed action.
    case success
    /// Filled negative background: flags a failed action.
    case failure
    /// Fixed dark charcoal fill, white text: SSO/secondary CTAs that should read as a
    /// distinct, high contrast brand element in both light and dark mode, rather than
    /// flipping to whichever color currently contrasts with the background.
    case inverted

    var backgroundColor: Color {
        switch self {
        case .primary: .accent
        case .secondary: .backgroundSecondary
        case .tertiary, .ghost, .outline: .clear
        case .success: .positive
        case .failure: .negative
        case .inverted: Color(white: Constants.invertedFillWhite)
        }
    }

    var foregroundColor: Color {
        switch self {
        // `.accent` is a pale gold: white text on it fails contrast in both appearances,
        // so its label stays fixed dark rather than following the semantic on fill color.
        case .primary: .black
        case .success, .failure, .inverted: .white
        case .secondary, .outline: .primaryDS
        case .ghost: .secondaryDS
        case .tertiary: .accentText
        }
    }

    var borderColor: Color {
        self == .secondary || self == .outline ? Self.hairline : .clear
    }

    private static var hairline: Color {
        #if os(macOS)
            .macLine
        #else
            .borderPrimary
        #endif
    }
}

public enum DSButtonSize: CaseIterable, Hashable {
    case large
    case medium
    case small

    var height: CGFloat {
        switch self {
        case .large: .size56
        case .medium: .size48
        case .small: .size40
        }
    }
}

private enum Constants {
    static let loadingOpacity: Double = 0.7
    static let disabledOpacity: Double = 0.4
    /// Fixed dark charcoal fill for `.inverted`, deliberately not theme adaptive.
    static let invertedFillWhite: Double = 0.15
    /// Press down feedback: a subtle scale down over this duration.
    static let pressedScale: CGFloat = 0.97
}

/// A plain tappable row, icon or button that shrinks a little while pressed, without any of
/// `.plain`'s visual side effects.
public struct DSPressableButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        PressFeedback(isPressed: configuration.isPressed) {
            configuration.label
        }
    }

    /// A subtle scale down on press, with no haptic: a tap on a plain button is not an event worth a
    /// buzz, and haptics stay for outcomes and changing values. A nested view so it can read Reduce
    /// Motion (a `ButtonStyle` can't observe `@Environment` directly).
    private struct PressFeedback<Label: View>: View {
        let isPressed: Bool
        @ViewBuilder let label: Label
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .scaleEffect(reduceMotion || !isPressed ? 1 : Constants.pressedScale)
                .animation(reduceMotion ? nil : DSMotion.quickFade, value: isPressed)
        }
    }
}

/// The app's standard rectangular button: corners match the web client's `rounded-xl`
/// inputs/buttons (`.radiusControl`, 12pt). Use this for any plain tap action; reach for
/// `DSAnimatedButton` instead when the action is async and should show a spinner/success
/// state in place.
public struct DSButton: View {
    @Environment(\.isEnabled) private var isEnabled

    private let title: String
    private let icon: Image?
    private let style: DSButtonStyle
    private let size: DSButtonSize
    private let isLoading: Bool
    private let action: () -> Void

    public init(
        _ title: String,
        icon: Image? = nil,
        style: DSButtonStyle = .primary,
        size: DSButtonSize = .medium,
        isLoading: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.style = style
        self.size = size
        self.isLoading = isLoading
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: .space8) {
                if isLoading {
                    DSSpinner(size: .small, color: style.foregroundColor)
                } else {
                    if let icon {
                        icon
                    }
                    Text(title)
                        .multilineTextAlignment(.center)
                }
            }
            .type(.label3)
            .foregroundStyle(style.foregroundColor)
            .frame(maxWidth: .infinity)
            // `minHeight`, not a fixed height: at large Dynamic Type / Bold Text the label grows
            // taller and the pill grows with it instead of clipping the text.
            .fixedSize(horizontal: false, vertical: true)
            .frame(minHeight: size.height)
            .background(chromeShape.fill(style.backgroundColor))
            .overlay(
                chromeShape.stroke(
                    style.borderColor,
                    lineWidth: style == .secondary || style == .outline ? .borderWidthHairline : 0
                )
            )
            .contentShape(chromeShape)
        }
        .buttonStyle(DSPressableButtonStyle())
        .allowsHitTesting(isEnabled && !isLoading)
        .opacity(!isEnabled ? Constants.disabledOpacity : isLoading ? Constants.loadingOpacity : 1)
        .animation(DSMotion.quickFade, value: isLoading)
    }

    private var chromeShape: AnyShape {
        #if os(macOS)
            AnyShape(Capsule())
        #else
            AnyShape(RoundedRectangle(cornerRadius: .radiusControl))
        #endif
    }
}

/// A CTA button that morphs between a full width rectangle with `.radiusControl` corners (matching
/// `DSButton`) and a circle `size` wide: for async actions that show a spinner while in
/// flight and a distinct end state (e.g. a checkmark or an X) in place, like "Test Connection".
public struct DSAnimatedButton<Content: View, Phase: Equatable>: View {
    @Environment(\.isEnabled) private var isEnabled

    private let phase: Phase
    private let isCollapsed: Bool
    private let style: DSButtonStyle
    private let size: DSButtonSize
    private let isHitEnabled: Bool
    private let action: () -> Void
    private let content: Content

    public init(
        phase: Phase,
        isCollapsed: Bool,
        style: DSButtonStyle = .primary,
        size: DSButtonSize = .medium,
        isHitEnabled: Bool = true,
        action: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) {
        self.phase = phase
        self.isCollapsed = isCollapsed
        self.style = style
        self.size = size
        self.isHitEnabled = isHitEnabled
        self.action = action
        self.content = content()
    }

    public var body: some View {
        GeometryReader { proxy in
            Button(action: action) {
                content
                    .animation(DSMotion.quickFade, value: phase)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    // Without this, only the pixels the label actually draws (the text glyphs)
                    // register taps: the rest of the expanded frame is transparent, so most of
                    // the pill was visually a button but not actually tappable.
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableButtonStyle())
            .allowsHitTesting(isHitEnabled && isEnabled)
            .opacity(isEnabled ? 1 : Constants.disabledOpacity)
            .animation(DSMotion.quickFade, value: isEnabled)
            .modifier(
                MorphingButtonChrome(
                    progress: isCollapsed ? 1 : 0,
                    expandedWidth: proxy.size.width,
                    height: size.height,
                    fillColor: style.backgroundColor,
                    borderColor: style.borderColor
                )
            )
            .frame(maxWidth: .infinity)
            .animation(
                DSMotion.controlMorph,
                value: isCollapsed
            )
        }
        .frame(height: size.height)
    }
}

/// Derives frame width and corner radius from one interpolated `progress` (0 = expanded
/// `.radiusControl` rectangle, 1 = collapsed circle `height` wide) so they animate in lockstep.
struct MorphingButtonChrome: Animatable, ViewModifier {
    var progress: CGFloat
    let expandedWidth: CGFloat
    let height: CGFloat
    let fillColor: Color
    let borderColor: Color

    nonisolated var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    /// Pure width/radius interpolation, split out from `body(content:)` so it's testable
    /// without rendering a `View`. `nonisolated` because `ViewModifier` conformance would
    /// otherwise infer these onto `MainActor`, even though the math touches no UI state.
    nonisolated static func width(progress: CGFloat, expandedWidth: CGFloat, height: CGFloat) -> CGFloat {
        expandedWidth + (height - expandedWidth) * progress
    }

    nonisolated static func radius(progress: CGFloat, height: CGFloat) -> CGFloat {
        .radiusControl + (height / 2 - .radiusControl) * progress
    }

    func body(content: Content) -> some View {
        let width = Self.width(progress: progress, expandedWidth: expandedWidth, height: height)
        content
            .frame(width: width, height: height)
        #if os(macOS)
            .background(Capsule().fill(fillColor))
            .overlay(Capsule().strokeBorder(borderColor, lineWidth: .borderWidthHairline))
        #else
            .background(RoundedRectangle(cornerRadius: Self.radius(progress: progress, height: height)).fill(fillColor))
            .overlay(
                RoundedRectangle(cornerRadius: Self.radius(progress: progress, height: height))
                    .stroke(borderColor, lineWidth: .borderWidthHairline)
            )
        #endif
    }
}
