import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let contentSpacing: CGFloat = .space24
    static let horizontalPadding: CGFloat = .space24
    static let verticalPadding: CGFloat = .space24
}

enum NameInputRule {
    case fileName
    case versionLabel
}

/// A one field name entry sheet shared by "Create Folder", "Create File" and "Rename": a `DSDynamicHeightSheet`
/// with a single text field and a confirm button, sizing to its own content. The draft lives
/// in this view's own `@State` rather than the store: a `TextField` bound through a TCA
/// `.sending` binding dropped keystrokes. `onConfirm` gets the raw text; the reducer trims and
/// decides whether the name actually changed.
struct NameInputSheet: View {
    let icon: Image
    let title: String
    let placeholder: String
    let confirmTitle: String
    let isBusy: Bool
    /// A rule on top of the file name rules, such as "an extension the editor opens" for a new
    /// file: returns why the trimmed name can't be used, or `nil`.
    let additionalRule: ((String) -> String?)?
    let hint: String?
    let shouldCapitalizeWords: Bool
    let rule: NameInputRule
    let onConfirm: (String) -> Void
    let onCancel: () -> Void

    private let isRenaming: Bool
    @State private var name: String
    @FocusState private var isFieldFocused: Bool

    init(
        icon: Image,
        title: String,
        placeholder: String,
        confirmTitle: String,
        initialName: String = "",
        isBusy: Bool,
        additionalRule: ((String) -> String?)? = nil,
        hint: String? = nil,
        shouldCapitalizeWords: Bool = true,
        rule: NameInputRule = .fileName,
        onConfirm: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.placeholder = placeholder
        self.confirmTitle = confirmTitle
        self.isBusy = isBusy
        self.additionalRule = additionalRule
        self.hint = hint
        self.shouldCapitalizeWords = shouldCapitalizeWords
        self.rule = rule
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        isRenaming = !initialName.isEmpty
        _name = State(initialValue: initialName)
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Inline reason the current name can't be used (a path separator, a reserved name), or `nil`.
    private var validationError: String? {
        guard rule == .fileName else { return nil }
        if let error = FileNameValidation.errorMessage(forTrimmed: trimmedName) {
            return error
        }
        if trimmedName.isEmpty {
            return isRenaming ? L10n.Favorites.editNameErrorEmpty : nil
        }
        return additionalRule?(trimmedName)
    }

    private var canSubmit: Bool {
        guard rule == .fileName else { return true }
        return FileNameValidation.isAcceptable(trimmed: trimmedName) && additionalRule?(trimmedName) == nil
    }

    private var nameBinding: Binding<String> {
        Binding(
            get: { name },
            set: { name = rule == .versionLabel ? FileVersion.cappedLabel($0) : $0 }
        )
    }

    var body: some View {
        #if os(macOS)
            macBody
        #else
            phoneBody
        #endif
    }

    #if os(macOS)
        /// A native Mac dialog: the field, its error, then Cancel and the confirm button.
        private var macBody: some View {
            MacFormSheet(
                title: title,
                confirmTitle: confirmTitle,
                isConfirmEnabled: canSubmit,
                isWorking: isBusy,
                onCancel: onCancel,
                onConfirm: submit
            ) {
                MacFormSheetRow(L10n.Browse.renameNamePlaceholder) {
                    MacTextField(placeholder, text: nameBinding, prompt: placeholder, isInvalid: validationError != nil)
                        .focused($isFieldFocused)
                        .autocorrectionDisabled()
                        .onSubmit(submit)
                    if let line = validationError ?? hint {
                        Text(line)
                            .type(.body3(.regular), style: validationError == nil ? .secondary : .error)
                            .contentTransition(.opacity)
                            .animation(DSMotion.stateFade, value: line)
                            .macDialogReveal()
                    }
                }
            }
            .task { isFieldFocused = true }
        }
    #endif

    private var phoneBody: some View {
        DSDynamicHeightSheet {
            VStack(alignment: .leading, spacing: Constants.contentSpacing) {
                DSSheetHeader(icon: icon, title: title, closeAccessibilityLabel: L10n.Common.close, onClose: onCancel)
                VStack(alignment: .leading, spacing: .space8) {
                    DSTextField(placeholder, text: nameBinding, focused: $isFieldFocused)
                        .textInputAutocapitalization(shouldCapitalizeWords ? .words : .never)
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
                .animation(DSMotion.quickFade, value: validationError)
                DSButton(confirmTitle, style: .primary, isLoading: isBusy, action: submit)
                    .disabled(!canSubmit)
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
        }
        .task { isFieldFocused = true }
    }

    private func submit() {
        guard canSubmit, !isBusy else { return }
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

#Preview("Create file") {
    Color.clear.sheet(isPresented: .constant(true)) {
        NameInputSheet(
            icon: IconKit.newFile,
            title: "New File",
            placeholder: "notes.txt",
            confirmTitle: "Create",
            initialName: "photo.jpg",
            isBusy: false,
            additionalRule: {
                EditableTextFiles
                    .isEditable(name: $0) ? nil : "Use a file type the editor can open, such as .txt, .md or .js."
            },
            shouldCapitalizeWords: false,
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
