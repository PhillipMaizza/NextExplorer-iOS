#if os(macOS)
    import SwiftUI

    private enum Constants {
        static let trackOpacity: Double = 0.18
        static let quarterTurn: Double = -90
    }

    public struct MacProgressRing: View {
        private let progress: Double
        private let lineWidth: CGFloat

        public init(progress: Double, lineWidth: CGFloat = .borderWidthFocused) {
            self.progress = progress
            self.lineWidth = lineWidth
        }

        public var body: some View {
            ZStack {
                Circle()
                    .stroke(Color.macChromeText.opacity(Constants.trackOpacity), lineWidth: lineWidth)
                Circle()
                    .trim(from: 0, to: min(max(progress, 0), 1))
                    .stroke(Color.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(Constants.quarterTurn))
            }
            .accessibilityHidden(true)
        }
    }

    #Preview("Progress ring") {
        HStack(spacing: .space16) {
            ForEach([0, 0.25, 0.62, 1], id: \.self) { value in
                MacProgressRing(progress: value)
                    .frame(width: .size24, height: .size24)
            }
        }
        .padding(.space24)
        .background(Color.macChrome)
    }
#endif
