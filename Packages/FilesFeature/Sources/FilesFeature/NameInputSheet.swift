import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let headerIconSize: CGFloat = .iconMedium
    static let closeIconSize: CGFloat = .iconXSmall
    static let closeButtonPadding: CGFloat = .space8
    static let contentSpacing: CGFloat = .space24
    static let horizontalPadding: CGFloat = .space24
    static let verticalPadding: CGFloat = .space24
}

/// A one field name entry sheet shared by "Create Folder" and "Rename": a `DynamicHeightSheet`
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

    var body: some View {
        DynamicHeightSheet {
            VStack(alignment: .leading, spacing: Constants.contentSpacing) {
                header
                Text(title).type(.headline3, style: .link)
                DSTextField(placeholder, text: $name, focused: $isFieldFocused)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(submit)
                DSButton(confirmTitle, style: .primary, isLoading: isBusy, action: submit)
                    .disabled(trimmedName.isEmpty)
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
        }
        .task { isFieldFocused = true }
    }

    private var header: some View {
        HStack {
            icon
                .resizable()
                .scaledToFit()
                .foregroundStyle(Color.accent)
                .frame(width: Constants.headerIconSize, height: Constants.headerIconSize)
            Spacer()
            Button(action: onCancel) {
                IconKit.close
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.primaryDS)
                    .frame(width: Constants.closeIconSize, height: Constants.closeIconSize)
                    .padding(Constants.closeButtonPadding)
                    .background(Circle().fill(Color.backgroundSecondary))
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(L10n.Common.close)
        }
    }

    private func submit() {
        guard !trimmedName.isEmpty, !isBusy else { return }
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
