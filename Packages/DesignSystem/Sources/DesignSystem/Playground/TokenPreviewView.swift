import SwiftUI

struct TokenPreviewView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: .space12) {
            Text("Headline").type(.headline1, style: .primary)
            Text("Body").type(.body1, style: .primary)
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
        ("body1", .body1),
        ("body2", .body2),
        ("button", .button),
        ("label1", .label1)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: .space16) {
            ForEach(rows, id: \.name) { row in
                VStack(alignment: .leading, spacing: .space4) {
                    Text("The quick brown fox — 0123456789")
                        .type(row.type, style: .primary)
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

/// Every `DSButtonStyle`, in every `DSButtonSize`, both loading/disabled — so a radius or
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
                Text("Test Connection").type(.button).foregroundStyle(Color.backgroundPrimary)
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
