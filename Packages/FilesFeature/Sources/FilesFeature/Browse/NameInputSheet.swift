import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let contentSpacing: CGFloat = .space24
    static let horizontalPadding: CGFloat = .space24
    static let verticalPadding: CGFloat = .space24
}

/// A one field name entry sheet shared by "Create Folder" and "Rename": a `DSDynamicHeightSheet`
/// with a single text field and a confirm button, sizing to its own content. The draft lives
/// in this view's own `@State` rather than the store — a `TextField` bound through a TCA
/// `.sending` binding dropped keystrokes. `onConfirm` gets the raw text; the reducer trims and
/// decides whether the name actually changed.
struct NameInputSheet: View {
    let icon: Image
    let title: String
    let placeholder: String
    let confirmTitle: String
    let isBusy: Bool
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    @State private var name: String
    @FocusState private var isFieldFocused: Bool

    init(
        icon: Image,
        title: String,
        placeholder: String,
        confirmTitle: String,
        initialName: String = "",
        isBusy: Bool,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.placeholder = placeholder
        self.confirmTitle = confirmTitle
        self.isBusy = isBusy
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._name = State(initialValue: initialName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Inline reason the current name can't be used (a path separator, a reserved name), or `nil`.
    private var validationError: String? {
        FileNameValidation.errorMessage(forTrimmed: trimmedName)
    }

    var body: some View {
        DSDynamicHeightSheet {
            VStack(alignment: .leading, spacing: Constants.contentSpacing) {
                DSSheetHeader(icon: icon, title: title, closeAccessibilityLabel: L10n.Common.close, onClose: onCancel)
                VStack(alignment: .leading, spacing: .space8) {
                    DSTextField(placeholder, text: $name, focused: $isFieldFocused)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(submit)
                    if let validationError {
                        Text(validationError)
                            .type(.body2(.semibold), style: .error)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: validationError)
                DSButton(confirmTitle, style: .primary, isLoading: isBusy, action: submit)
                    .disabled(!FileNameValidation.isAcceptable(trimmed: trimmedName))
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
        }
        .task { isFieldFocused = true }
    }

    private func submit() {
        guard FileNameValidation.isAcceptable(trimmed: trimmedName), !isBusy else { return }
        onConfirm(name)
    }
}

#Preview("Create folder") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NameInputSheet(
            icon: IconKit.folder,
            title: "New folder",
            placeholder: "Folder name",
            confirmTitle: "Create",
            isBusy: false,
            onConfirm: { _ in },
            onCancel: {}
        )
    }
}

#Preview("Rename") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NameInputSheet(
            icon: IconKit.rename,
            title: "Rename",
            placeholder: "Name",
            confirmTitle: "Save",
            initialName: "vacation.jpg",
            isBusy: false,
            onConfirm: { _ in },
            onCancel: {}
        )
    }
}

#Preview("Invalid name") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NameInputSheet(
            icon: IconKit.folder,
            title: "New folder",
            placeholder: "Folder name",
            confirmTitle: "Create",
            initialName: "Reports/2026",
            isBusy: false,
            onConfirm: { _ in },
            onCancel: {}
        )
    }
}
