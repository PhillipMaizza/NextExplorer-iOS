#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let rowSpacing: CGFloat = .space8
    }

    struct MacPaneSaveButton: View {
        let title: String
        let isSaving: Bool
        let isEnabled: Bool
        let action: () -> Void

        var body: some View {
            HStack(spacing: Metrics.rowSpacing) {
                if isSaving {
                    MacSpinner()
                }
                Button(title, action: action)
                    .buttonStyle(.macDS(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isEnabled)
            }
        }
    }

    #Preview("Save button") {
        VStack(alignment: .trailing, spacing: .space16) {
            MacPaneSaveButton(title: L10n.Common.save, isSaving: false, isEnabled: true) {}
            MacPaneSaveButton(title: L10n.Common.save, isSaving: false, isEnabled: false) {}
            MacPaneSaveButton(title: L10n.Common.save, isSaving: true, isEnabled: false) {}
        }
        .padding(.space24)
        .background(Color.macCard)
    }
#endif
