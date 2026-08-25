import SwiftUI

struct TokenPreviewView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: .space12) {
            Text("Headline").type(.headline1, style: .primary(for: .label))
            Text("Body").type(.body1(.semibold), style: .primary(for: .label))
            Text("Label").type(.label1, style: .secondary)

            let swatches: [Color] = [.accent, .positive, .attention, .negative]
            HStack(spacing: .space8) {
                ForEach(swatches.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: .radiusSmall).fill(swatches[index]).frame(width: 32, height: 32)
                }
            }
        }
        .padding(.space16)
        .background(Color.backgroundPrimary)
    }
}

#Preview {
    TokenPreviewView()
}

/// Every `Typography.TextType` case rendered against its own name/size/weight so a Figtree
/// change (or a registration regression) is visible at a glance in the canvas.
private struct TypographyPreviewView: View {
    private let rows: [(name: String, type: Typography.TextType)] = [
        ("headline1", .headline1),
        ("body1", .body1(.bold)),
        ("body2", .body2(.bold)),
        ("button", .label1),
        ("label1", .label1)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: .space16) {
            ForEach(rows, id: \.name) { row in
                VStack(alignment: .leading, spacing: .space4) {
                    Text("The quick brown fox — 0123456789")
                        .type(row.type, style: .primary(for: .label))
                    Text("\(row.name)  \(Int(row.type.size))pt  \(String(describing: row.type.weight))")
                        .type(.label1, style: .secondary)
                }
            }
        }
        .padding(.space16)
        .background(Color.backgroundPrimary)
    }
}

#Preview("Typography") {
    TypographyPreviewView()
}

/// Every `DSButtonStyle`, in every `DSButtonSize`, both loading/disabled, so a radius or
/// color change is visible at a glance in the canvas.
private struct ButtonPreviewView: View {
    var body: some View {
        VStack(spacing: .space24) {
            ForEach(DSButtonStyle.allCases, id: \.self) { style in
                VStack(spacing: .space8) {
                    ForEach(DSButtonSize.allCases, id: \.self) { size in
                        DSButton("Continue", style: style, size: size) {}
                    }
                    DSButton("Continue", style: style, isLoading: true) {}
                    DSButton("Continue", style: style) {}
                        .disabled(true)
                }
            }

            DSAnimatedButton(phase: 0, isCollapsed: false, style: .inverted) {} content: {
                Text("Test Connection").type(.label2).foregroundStyle(Color.backgroundPrimary)
            }
            DSAnimatedButton(phase: 1, isCollapsed: true, style: .inverted) {} content: {
                ProgressView().tint(Color.backgroundPrimary)
            }
            DSAnimatedButton(phase: 2, isCollapsed: true, style: .success) {} content: {
                IconKit.checkmark.foregroundStyle(.white)
            }
            DSAnimatedButton(phase: 3, isCollapsed: true, style: .failure) {} content: {
                IconKit.xmark.foregroundStyle(.white)
            }
        }
        .padding(.space16)
        .background(Color.backgroundPrimary)
    }
}

#Preview("Buttons") {
    ButtonPreviewView()
}

/// `DSFieldContainer` empty, filled, and `isInvalid`, plus a standalone `DSPlaceholderText`.
private struct FieldsPreviewView: View {
    @State private var text = ""

    var body: some View {
        VStack(spacing: .space16) {
            DSFieldContainer(label: "Empty", icon: IconKit.envelope) {
                DSPlaceholderText("name@company.com")
            }
            DSFieldContainer(label: "Filled", icon: IconKit.envelope) {
                Text("jane.doe@example.com").type(.body1(.regular))
            }
            DSFieldContainer(label: "Invalid", icon: IconKit.lock, isInvalid: true) {
                Text("wrong-password").type(.body1(.regular))
            }
        }
        .padding(.space16)
        .background(Color.backgroundPrimary)
    }
}

#Preview("Fields") {
    FieldsPreviewView()
}

/// `DSSegmentedControl` with each option selected in turn.
private struct SegmentedControlPreviewView: View {
    private enum Option: Hashable, CaseIterable { case first, second, third }
    @State private var selection: Option = .first

    var body: some View {
        VStack(spacing: .space16) {
            ForEach(Array(Option.allCases), id: \.self) { option in
                DSSegmentedControl(
                    options: Array(Option.allCases),
                    selection: .constant(option),
                    label: { "\($0)".capitalized }
                )
            }
        }
        .padding(.space16)
        .background(Color.backgroundPrimary)
    }
}

#Preview("SegmentedControl") {
    SegmentedControlPreviewView()
}
