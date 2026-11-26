#if os(macOS)
    import SwiftUI

    public enum MacTextScale {
        public static let range: ClosedRange<CGFloat> = 1 ... 1.4
        static let largestScaledPointSize: CGFloat = 32

        public static func clamped(_ scale: CGFloat) -> CGFloat {
            min(max(scale, range.lowerBound), range.upperBound)
        }

        static func pointSize(_ size: CGFloat, scale: CGFloat) -> CGFloat {
            guard size < largestScaledPointSize else { return size }
            return min(size * clamped(scale), largestScaledPointSize)
        }
    }

    public enum MacControlHeight: CaseIterable, Sendable {
        case mini
        case small
        case regular
        case medium
        case large
        case xLarge
        case xxLarge
        case formRow

        public var points: CGFloat {
            switch self {
            case .mini: 22
            case .small: 28
            case .regular: .size32
            case .medium: .size36
            case .large: .size40
            case .xLarge: .size44
            case .xxLarge: .size48
            case .formRow: 52
            }
        }

        public func points(scale: CGFloat) -> CGFloat {
            points * MacTextScale.clamped(scale)
        }

        public func points(ofRows count: Int) -> CGFloat {
            CGFloat(count) * points + CGFloat(max(count - 1, 0)) * .borderWidthHairline
        }
    }

    public extension EnvironmentValues {
        @Entry var macTextScale: CGFloat = 1
    }

    public extension View {
        func macTextScale(_ scale: CGFloat) -> some View {
            environment(\.macTextScale, MacTextScale.clamped(scale))
        }

        func macMinHeight(_ height: MacControlHeight) -> some View {
            modifier(MacScaledFrame(base: height.points, shape: .minHeight))
        }

        func macMinHeight(points: CGFloat) -> some View {
            modifier(MacScaledFrame(base: points, shape: .minHeight))
        }

        func macHeight(points: CGFloat) -> some View {
            modifier(MacScaledFrame(base: points, shape: .height))
        }

        func macSquare(_ side: CGFloat) -> some View {
            modifier(MacScaledFrame(base: side, shape: .square))
        }
    }

    private struct MacScaledFrame: ViewModifier {
        enum Shape {
            case minHeight
            case height
            case square
        }

        let base: CGFloat
        let shape: Shape
        @Environment(\.macTextScale) private var scale

        func body(content: Content) -> some View {
            let side = base * MacTextScale.clamped(scale)
            switch shape {
            case .minHeight: content.frame(minHeight: side)
            case .height: content.frame(height: side)
            case .square: content.frame(width: side, height: side)
            }
        }
    }
#endif
