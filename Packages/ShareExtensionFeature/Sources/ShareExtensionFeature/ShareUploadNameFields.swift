import ComposableArchitecture
import DesignSystem
import FolderPickerFeature
import Localization
import SwiftUI

private enum Metrics {
    static let rowSpacing: CGFloat = .space8
    static let fieldSpacing: CGFloat = .space4
    static let singleLine = 1
}

/// One field per shared file for the name it uploads under. Only the part before the extension is
/// edited; a known extension trails the field so it is clear it stays.
struct ShareUploadNameFields: View {
    let store: StoreOf<ShareUploadFeature>

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
            ForEach(Array(store.names.enumerated()), id: \.offset) { index, name in
                ShareUploadNameField(
                    name: name,
                    isEnabled: store.canEditNames,
                    onChange: { store.send(.nameChanged(index: index, $0)) }
                )
            }
        }
    }
}

private struct ShareUploadNameField: View {
    let name: EditableItemName
    let isEnabled: Bool
    let onChange: @MainActor @Sendable (String) -> Void

    private var text: Binding<String> {
        Binding(get: { name.text }, set: onChange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.fieldSpacing) {
            HStack(spacing: Metrics.fieldSpacing) {
                field
                if !name.original.fileExtension.isEmpty {
                    Text(".\(name.original.fileExtension)")
                        .type(.body2(.regular), style: .secondary)
                        .lineLimit(Metrics.singleLine)
                        .accessibilityHidden(true)
                }
            }
            if let problem = name.problem {
                Text(problem.message)
                    .type(.body3(.semibold), style: .error)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .disabled(!isEnabled)
    }

    private var field: some View {
        #if os(macOS)
            TextField(L10n.ShareUpload.nameLabel, text: text, prompt: Text(name.original.base))
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .accessibilityHint(L10n.ShareUpload.nameHint)
        #else
            DSTextField(L10n.ShareUpload.nameLabel, text: text, prompt: Text(name.original.base))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .accessibilityHint(L10n.ShareUpload.nameHint)
        #endif
    }
}

@MainActor
private func previewStore(_ names: [EditableItemName], phase: ShareUploadFeature.Phase = .ready)
    -> StoreOf<ShareUploadFeature>
{
    var state = ShareUploadFeature.State()
    state.phase = phase
    state.names = names
    return Store(initialState: state) { EmptyReducer() }
}

private enum PreviewNames {
    static let photo = EditableItemName(SharedItemName(base: "IMG_0042"))
    static let report = EditableItemName(SharedItemName(base: "Quarterly report", fileExtension: "pdf"))
    static var invalid: EditableItemName {
        var name = report
        name.text = "2026/report"
        return name
    }
}

#Preview("One file") {
    ShareUploadNameFields(store: previewStore([PreviewNames.report]))
        .padding(.space24)
}

#Preview("Several files") {
    ShareUploadNameFields(store: previewStore([PreviewNames.report, PreviewNames.photo]))
        .padding(.space24)
}

#Preview("Invalid name") {
    ShareUploadNameFields(store: previewStore([PreviewNames.invalid]))
        .padding(.space24)
}

#Preview("Checking, still editable") {
    ShareUploadNameFields(store: previewStore([PreviewNames.photo], phase: .checking))
        .padding(.space24)
}
