import DesignSystem
import FilesClient
import SwiftUI

/// The Save button of an admin form, with a Discard button beside it while there are unsaved
/// changes.
struct SettingsSaveRow: View {
    let saveTitle: String
    let discardTitle: String
    let isSaving: Bool
    let isSaveEnabled: Bool
    let isDirty: Bool
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        HStack(spacing: .space8) {
            DSButton(saveTitle, style: .primary, isLoading: isSaving, action: onSave)
                .disabled(!isSaveEnabled)
            if isDirty {
                DSButton(discardTitle, style: .secondary, action: onDiscard)
            }
        }
        .padding(.top, .space4)
        .formActionAlignment()
    }
}

#Preview("Unsaved changes") {
    SettingsSaveRow(saveTitle: "Save Changes", discardTitle: "Discard", isSaving: false, isSaveEnabled: true, isDirty: true, onSave: {}, onDiscard: {})
        .padding()
}

#Preview("Nothing to save") {
    SettingsSaveRow(saveTitle: "Save Changes", discardTitle: "Discard", isSaving: false, isSaveEnabled: false, isDirty: false, onSave: {}, onDiscard: {})
        .padding()
}

#Preview("Saving") {
    SettingsSaveRow(saveTitle: "Save Changes", discardTitle: "Discard", isSaving: true, isSaveEnabled: false, isDirty: true, onSave: {}, onDiscard: {})
        .padding()
}
