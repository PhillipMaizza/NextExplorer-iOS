#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    /// The small borderless add or remove button under a Mac table, like Finder's and System
    /// Settings' list editors.
    struct MacTableBarButton: View {
        let icon: Image
        let label: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                icon.frame(width: .size24, height: .size20)
            }
            .buttonStyle(.borderless)
            .accessibilityLabelWithTooltip(label)
        }
    }

    /// The hairline between neighbouring table bar buttons.
    struct MacTableBarDivider: View {
        var body: some View {
            Divider().frame(height: .size16)
        }
    }

    #Preview {
        HStack(spacing: 0) {
            MacTableBarButton(icon: IconKit.plus, label: L10n.Uploads.reviewAddMore) {}
            MacTableBarDivider()
            MacTableBarButton(icon: IconKit.minus, label: L10n.Common.remove) {}
            Spacer()
        }
        .padding(.space8)
        .previewCanvasWidth(.control)
    }
#endif
