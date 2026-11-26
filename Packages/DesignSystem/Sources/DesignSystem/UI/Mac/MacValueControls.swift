#if os(macOS)
    import Localization
    import SwiftUI

    private enum Constants {
        static let sliderWidth: CGFloat = 220
        static let trackHeight: CGFloat = .size6
        static let knobSize: CGFloat = .size18
        static let knobShadowRadius: CGFloat = .size2
        static let knobShadowOpacity: Double = 0.3
        static let stepperHeight: CGFloat = .size32
        static let stepperButtonWidth: CGFloat = 30
        static let stepperGlyph: CGFloat = 13
        static let stepperValueWidth: CGFloat = .size44
        static let stepperShape = RoundedRectangle(cornerRadius: 9, style: .continuous)
    }

    public struct MacSlider: View {
        private let label: String
        private let value: Int
        private let range: ClosedRange<Int>
        private let step: Int
        private let onChange: (Int) -> Void

        public init(
            label: String,
            value: Int,
            range: ClosedRange<Int>,
            step: Int,
            onChange: @escaping (Int) -> Void
        ) {
            self.label = label
            self.value = value
            self.range = range
            self.step = step
            self.onChange = onChange
        }

        public var body: some View {
            GeometryReader { proxy in
                let travel = proxy.size.width
                let knobX = travel * fraction
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.macSegment).frame(height: Constants.trackHeight)
                    Capsule().fill(Color.accent).frame(width: knobX, height: Constants.trackHeight)
                    Circle()
                        .fill(Color.white)
                        .shadow(
                            color: .black.opacity(Constants.knobShadowOpacity),
                            radius: Constants.knobShadowRadius,
                            y: 1
                        )
                        .frame(width: Constants.knobSize, height: Constants.knobSize)
                        .offset(x: knobX - Constants.knobSize / 2)
                }
                .frame(maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                    commit(fraction: drag.location.x / max(travel, 1))
                })
            }
            .frame(width: Constants.sliderWidth, height: Constants.knobSize)
            .macDisabledDim()
            .accessibilityRepresentation {
                Slider(
                    value: Binding(get: { Double(value) }, set: { onChange(Int($0.rounded())) }),
                    in: Double(range.lowerBound) ... Double(range.upperBound),
                    step: Double(step)
                ) {
                    Text(label)
                }
            }
        }

        private var fraction: CGFloat {
            let span = range.upperBound - range.lowerBound
            guard span > 0 else { return 0 }
            return CGFloat(min(max(value, range.lowerBound), range.upperBound) - range.lowerBound) / CGFloat(span)
        }

        private func commit(fraction: CGFloat) {
            let clamped = min(max(fraction, 0), 1)
            let raw = Double(range.lowerBound) + Double(range.upperBound - range.lowerBound) * Double(clamped)
            let snapped = Int((raw / Double(step)).rounded()) * step
            let next = min(max(snapped, range.lowerBound), range.upperBound)
            if next != value {
                onChange(next)
            }
        }
    }

    public struct MacStepper: View {
        private let label: String
        private let value: Int
        private let range: ClosedRange<Int>
        private let step: Int
        private let onChange: (Int) -> Void
        @FocusState private var isValueFocused: Bool

        public init(
            label: String,
            value: Int,
            range: ClosedRange<Int>,
            step: Int,
            onChange: @escaping (Int) -> Void
        ) {
            self.label = label
            self.value = value
            self.range = range
            self.step = step
            self.onChange = onChange
        }

        public var body: some View {
            HStack(spacing: .zero) {
                stepButton(IconKit.minus, label: L10n.Common.decrease, isEnabled: value > range.lowerBound) {
                    onChange(max(value - step, range.lowerBound))
                }
                TextField(
                    label,
                    value: Binding(get: { value }, set: { onChange(min(max($0, range.lowerBound), range.upperBound)) }),
                    format: .number
                )
                .textFieldStyle(.plain)
                .labelsHidden()
                .type(.body2(.semibold))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .tint(Color.accent)
                .focused($isValueFocused)
                .focusEffectDisabled()
                .accessibilityLabel(label)
                .fixedSize()
                .frame(minWidth: Constants.stepperValueWidth)
                .padding(.horizontal, .space4)
                stepButton(IconKit.plus, label: L10n.Common.increase, isEnabled: value < range.upperBound) {
                    onChange(min(value + step, range.upperBound))
                }
            }
            .frame(height: Constants.stepperHeight)
            .background(Constants.stepperShape.fill(Color.macField))
            .overlay(
                Constants.stepperShape.strokeBorder(
                    isValueFocused ? Color.accent : Color.macLine,
                    lineWidth: .borderWidthHairline
                )
            )
            .clipShape(Constants.stepperShape)
            .macDisabledDim()
            .accessibilityElement(children: .contain)
            .accessibilityLabel(label)
        }

        private func stepButton(
            _ icon: Image,
            label: String,
            isEnabled: Bool,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.stepperGlyph, height: Constants.stepperGlyph)
                    .foregroundStyle(Color.macChromeText)
                    .frame(width: Constants.stepperButtonWidth, height: Constants.stepperHeight)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!isEnabled)
            .accessibilityLabel(label)
        }
    }

    #Preview("Slider and stepper") {
        @Previewable @State var quality = 70
        @Previewable @State var size = 400
        VStack(alignment: .leading, spacing: .space24) {
            HStack(spacing: .space12) {
                MacSlider(label: "Quality", value: quality, range: 1 ... 100, step: 5) { quality = $0 }
                Text(verbatim: "\(quality)")
            }
            MacStepper(label: "Max Dimension", value: size, range: 64 ... 2048, step: 8) { size = $0 }
            MacStepper(label: "Max Dimension", value: size, range: 64 ... 2048, step: 8) { size = $0 }
                .disabled(true)
        }
        .padding(.space24)
        .background(Color.macCard)
    }
#endif
