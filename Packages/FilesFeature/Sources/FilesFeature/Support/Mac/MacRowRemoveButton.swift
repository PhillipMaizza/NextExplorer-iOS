#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacRowRemoveButton: View {
        let label: String
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                IconKit.close
                    .imageScale(.small)
                    .foregroundStyle(Color.macChromeSecondary)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabelWithTooltip(label)
        }
    }

    #Preview {
        MacRowRemoveButton(label: L10n.Common.remove) {}
            .padding(.space16)
    }
#endif
