#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacArchivePasswordAlert: View {
        let store: StoreOf<BrowseFeature>
        let prompt: BrowseFeature.ArchivePasswordPrompt
        @State private var password = ""

        private var isBusy: Bool {
            store.isPerformingFileAction
        }

        var body: some View {
            MacAlertSheet(
                glyph: IconKit.lock,
                title: L10n.Browse.archivePasswordTitle,
                message: L10n.Browse.archivePasswordMessage,
                confirmTitle: L10n.Browse.actionExtract,
                isDestructive: false,
                isConfirmLoading: isBusy,
                isConfirmDisabled: password.isEmpty,
                onConfirm: submit,
                onCancel: { store.send(.archivePasswordCancelled) },
                accessory: {
                    VStack(alignment: .leading, spacing: .space4) {
                        MacSecureField(
                            L10n.Browse.archivePasswordPlaceholder,
                            text: $password,
                            prompt: Text(L10n.Browse.archivePasswordPlaceholder),
                            isInvalid: prompt.isInvalid
                        )
                        .disabled(isBusy)
                        .onSubmit(submit)
                        if prompt.isInvalid {
                            Text(L10n.Browse.archivePasswordInvalid)
                                .type(.caption(.regular))
                                .foregroundStyle(Color.negative)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            )
            .onChange(of: prompt.invalidAttempts) { password = "" }
        }

        private func submit() {
            guard !password.isEmpty, !isBusy else { return }
            store.send(.archivePasswordSubmitted(password))
        }
    }

    #Preview("Archive password, wrong") {
        MacArchivePasswordAlert(
            store: Store(initialState: .preview(items: browsePreviewItems)) { BrowseFeature() },
            prompt: BrowseFeature.ArchivePasswordPrompt(
                item: browsePreviewItems[0],
                destination: .newFolder,
                invalidAttempts: 1
            )
        )
        .background(Color.macCard)
    }
#endif
