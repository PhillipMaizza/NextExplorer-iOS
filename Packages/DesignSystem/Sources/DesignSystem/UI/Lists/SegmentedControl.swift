import SwiftUI

private enum SegmentedControlConstants {
    static let segmentHeight: CGFloat = 30
    static let trackInset: CGFloat = 2
    /// Track tint over whatever surface the control sits on, so it reads on the background and in sheets.
    static let trackOpacity: Double = 0.07
    /// The dark mode pill: a lighter step above the track instead of the surface color.
    static let darkPillOpacity: Double = 0.22
    static let pillShadowAlpha: Double = 0.18
}

/// A compact pill shaped segmented control: a raised neutral pill on a softly tinted track.
/// Generic over any `Hashable` option set (e.g. an enum of modes). The selected pill is a single
/// view that slides between segments via `matchedGeometryEffect` rather than each segment
/// independently fading its own background in and out.
public struct DSSegmentedControl<Option: Hashable>: View {
    private let options: [Option]
    private let label: (Option) -> String
    @Binding private var selection: Option
    @Namespace private var pillNamespace
    @Environment(\.colorScheme) private var colorScheme
    private static var pillID: String {
        "pill"
    }

    private let shouldAlwaysUsePill: Bool

    /// The Mac shows a native segmented control unless `shouldAlwaysUsePill` is set, for a branded
    /// screen (the login card) that keeps the accent pill everywhere.
    public init(
        options: [Option],
        selection: Binding<Option>,
        shouldAlwaysUsePill: Bool = false,
        label: @escaping (Option) -> String
    ) {
        self.options = options
        _selection = selection
        self.shouldAlwaysUsePill = shouldAlwaysUsePill
        self.label = label
    }

    public var body: some View {
        #if os(macOS)
            if shouldAlwaysUsePill {
                pillControl
            } else {
                nativeControl
            }
        #else
            pillControl
        #endif
    }

    #if os(macOS)
        /// The native control at its natural size, not the full width pill.
        private var nativeControl: some View {
            Picker(selection: $selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    #endif

    private var pillFill: Color {
        colorScheme == .dark
            ? Color.primaryDS.opacity(SegmentedControlConstants.darkPillOpacity)
            : Color.backgroundSecondary
    }

    private var pillControl: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isSelected = option == selection
                Button {
                    selection = option
                } label: {
                    Text(label(option))
                        .type(.body3(.semibold), style: isSelected ? .primaryOnSurface : .secondary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .frame(height: SegmentedControlConstants.segmentHeight)
                        .background {
                            if isSelected {
                                RoundedRectangle(cornerRadius: .radiusFull)
                                    .fill(pillFill)
                                    .elevation(
                                        colorScheme == .dark ? .level0 : .level1,
                                        alpha: SegmentedControlConstants.pillShadowAlpha
                                    )
                                    .matchedGeometryEffect(id: Self.pillID, in: pillNamespace)
                            }
                        }
                        // Whole segment is the hit target, not just the glyph.
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            }
        }
        .padding(SegmentedControlConstants.trackInset)
        .background(
            RoundedRectangle(cornerRadius: .radiusFull)
                .fill(Color.primaryDS.opacity(SegmentedControlConstants.trackOpacity))
        )
        .animation(
            DSMotion.controlMorph,
            value: selection
        )
        .hapticFeedback(.selection, trigger: selection)
    }
}
