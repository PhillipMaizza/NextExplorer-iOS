import SwiftUI

public extension View {
    /// Liquid Glass on iOS 26, frosted `.ultraThinMaterial` fallback below it. For floating
    /// controls that sit over arbitrary content: full screen preview toolbars, close button
    /// chips: where the system toolbar can't reach (custom `fullScreenCover` with its own
    /// swipe to dismiss). Pass `interactive: true` on a tappable control so the glass reacts
    /// to touch the way system glass buttons do.
    ///
    /// Honors Reduce Transparency: when that setting is on, both the glass and the material are
    /// swapped for an opaque `backgroundSecondary` fill so nothing behind the control bleeds
    /// through.
    func dsGlass(interactive: Bool = false, in shape: some Shape = Capsule()) -> some View {
        modifier(DSGlassModifier(interactive: interactive, shape: shape))
    }
}

private struct DSGlassModifier<S: Shape>: ViewModifier {
    let interactive: Bool
    let shape: S
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(shape.fill(Color.backgroundSecondary))
        } else if #available(iOS 26.0, macOS 26.0, *) {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            content.background(shape.fill(.ultraThinMaterial))
        }
    }
}

/// A shape of frosted material washed with a tint: the tint keeps its meaning (a toast's color, a
/// sheet's dim) while what lies behind shows through blurred. With Reduce Transparency on, the tint
/// alone at `fallbackOpacity`, so nothing behind bleeds through.
public struct DSFrostedTint<S: Shape>: View {
    private let shape: S
    private let tint: Color
    private let tintOpacity: Double
    private let fallbackOpacity: Double
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    public init(_ shape: S, tint: Color, tintOpacity: Double, fallbackOpacity: Double = 1) {
        self.shape = shape
        self.tint = tint
        self.tintOpacity = tintOpacity
        self.fallbackOpacity = fallbackOpacity
    }

    public var body: some View {
        if reduceTransparency {
            shape.fill(tint.opacity(fallbackOpacity))
        } else {
            ZStack {
                shape.fill(.ultraThinMaterial)
                shape.fill(tint.opacity(tintOpacity))
            }
        }
    }
}

/// A sheet's surface: frosted, with enough of the page color over it that text stays easy to read.
/// Solid page color with Reduce Transparency on.
public struct DSSheetSurface: View {
    private static let tintOpacity: Double = 0.65

    public init() {}

    public var body: some View {
        DSFrostedTint(Rectangle(), tint: .backgroundPrimary, tintOpacity: Self.tintOpacity)
    }
}

#Preview("Frosted tint") {
    ZStack {
        LinearGradient(colors: [.orange, .purple], startPoint: .top, endPoint: .bottom)
        DSFrostedTint(Capsule(), tint: .positive, tintOpacity: 0.78)
            .frame(width: 240, height: 48)
    }
}

#Preview("Sheet surface") {
    ZStack {
        LinearGradient(colors: [.orange, .purple], startPoint: .top, endPoint: .bottom)
        Text("Sheet")
            .frame(width: 280, height: 160)
            .background(DSSheetSurface())
    }
}

#Preview("Sheet dim") {
    ZStack {
        LinearGradient(colors: [.orange, .purple], startPoint: .top, endPoint: .bottom)
        DSFrostedTint(Rectangle(), tint: .black, tintOpacity: 0.3, fallbackOpacity: 0.3)
    }
}
