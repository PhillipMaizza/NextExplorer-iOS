#if os(macOS)
    import SwiftUI

    public struct MacProgressBar: View {
        private enum Metrics {
            static let height: CGFloat = .size6
            static let segmentFraction: CGFloat = 0.35
            static let loopDuration: Double = 1.1
        }

        let value: Double?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isSliding = false

        public init(value: Double?) {
            self.value = value
        }

        public var body: some View {
            GeometryReader { proxy in
                Capsule()
                    .fill(Color.macSegment)
                    .overlay(alignment: .leading) { fill(width: proxy.size.width) }
                    .clipShape(Capsule())
            }
            .frame(height: Metrics.height)
            .onChange(of: value == nil, initial: true) { _, isIndeterminate in
                isSliding = isIndeterminate && !reduceMotion
            }
            .accessibilityRepresentation {
                if let value {
                    ProgressView(value: min(max(value, 0), 1))
                } else {
                    ProgressView()
                }
            }
        }

        @ViewBuilder
        private func fill(width: CGFloat) -> some View {
            if let value {
                Capsule()
                    .fill(Color.accent)
                    .frame(width: width * min(max(value, 0), 1))
            } else {
                let segment = width * Metrics.segmentFraction
                Capsule()
                    .fill(Color.accent)
                    .frame(width: segment)
                    .offset(x: isSliding ? width : (reduceMotion ? 0 : -segment))
                    .animation(reduceMotion ? nil : DSMotion.loop(duration: Metrics.loopDuration), value: isSliding)
            }
        }
    }

    #Preview("Progress") {
        VStack(spacing: .space16) {
            MacProgressBar(value: 0)
            MacProgressBar(value: 0.42)
            MacProgressBar(value: 1)
            MacProgressBar(value: nil)
        }
        .padding(.space24)
        .frame(width: 320)
        .background(Color.macCard)
    }
#endif
