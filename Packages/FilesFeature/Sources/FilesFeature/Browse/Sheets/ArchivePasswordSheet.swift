#if os(iOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let contentSpacing: CGFloat = .space24
        static let fieldSpacing: CGFloat = .space8
        static let padding: CGFloat = .space24
    }

    struct ArchivePasswordSheet: View {
        let store: StoreOf<BrowseFeature>
        let prompt: BrowseFeature.ArchivePasswordPrompt
        @State private var password = ""
        @FocusState private var isFocused: Bool

        private var isBusy: Bool {
            store.isPerformingFileAction
        }

        var body: some View {
            DSDynamicHeightSheet {
                VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                    DSSheetHeader(
                        icon: IconKit.lock,
                        title: L10n.Browse.archivePasswordTitle,
                        closeAccessibilityLabel: L10n.Common.cancel,
                        onClose: { store.send(.archivePasswordCancelled) }
                    )
                    Text(L10n.Browse.archivePasswordMessage)
                        .type(.body2(.regular), style: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: Metrics.fieldSpacing) {
                        DSSecureField(
                            L10n.Browse.archivePasswordPlaceholder,
                            text: $password,
                            prompt: Text(L10n.Browse.archivePasswordPlaceholder)
                        )
                        .focused($isFocused)
                        .submitLabel(.go)
                        .onSubmit(submit)
                        if prompt.isInvalid {
                            Text(L10n.Browse.archivePasswordInvalid)
                                .type(.body2(.semibold), style: .error)
                                .transition(.opacity)
                        }
                    }
                    .animation(DSMotion.quickFade, value: prompt.invalidAttempts)
                    DSButton(L10n.Browse.actionExtract, style: .primary, isLoading: isBusy, action: submit)
                        .disabled(password.isEmpty)
                }
                .padding(Metrics.padding)
            }
            .task { isFocused = true }
            .onChange(of: prompt.invalidAttempts) { password = "" }
        }

        private func submit() {
            guard !password.isEmpty, !isBusy else { return }
            store.send(.archivePasswordSubmitted(password))
        }
    }

    #Preview("Archive password, wrong") {
        Color.clear.sheet(isPresented: .constant(true)) {
            ArchivePasswordSheet(
                store: Store(initialState: .preview(items: browsePreviewItems)) { BrowseFeature() },
                prompt: BrowseFeature.ArchivePasswordPrompt(
                    item: browsePreviewItems[0],
                    destination: .newFolder,
                    invalidAttempts: 1
                )
            )
        }
    }
#endif
