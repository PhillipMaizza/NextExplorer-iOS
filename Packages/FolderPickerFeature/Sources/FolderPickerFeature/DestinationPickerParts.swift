import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

extension DestinationPickerFeature.State {
    var refusalMessage: String? {
        switch refusal {
        case .noFolder: L10n.Browse.destinationPickerChooseFolder
        case .noRights: L10n.Browse.destinationPickerNoRights
        case .intoItself: L10n.Browse.destinationPickerIntoItself
        case .alreadyThere: L10n.Browse.destinationPickerAlreadyThere(destinationName)
        case nil: nil
        }
    }
}

#if os(iOS)
    private enum Metrics {
        static let padding: CGFloat = .space24
        static let contentSpacing: CGFloat = .space24
        static let fieldSpacing: CGFloat = .space8
    }

    struct PickerNewFolderSheet: View {
        let store: StoreOf<DestinationPickerFeature>
        @FocusState private var isFocused: Bool

        private var draft: DestinationPickerFeature.NewFolderDraft {
            store.newFolder ?? .init()
        }

        var body: some View {
            DSDynamicHeightSheet {
                VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                    DSSheetHeader(
                        icon: IconKit.newFolder,
                        title: L10n.Browse.newFolderTitle,
                        closeAccessibilityLabel: L10n.Common.close,
                        onClose: { store.send(.newFolderCancelled) }
                    )
                    VStack(alignment: .leading, spacing: Metrics.fieldSpacing) {
                        DSTextField(
                            L10n.Browse.newFolderPlaceholder,
                            text: Binding(get: { draft.name }, set: { store.send(.newFolderNameChanged($0)) }),
                            focused: $isFocused
                        )
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { store.send(.newFolderConfirmed) }
                        if let problem = draft.problem ?? draft.phase.errorMessage {
                            Text(problem)
                                .type(.body2(.semibold), style: .error)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .transition(.opacity)
                        }
                    }
                    .animation(DSMotion.quickFade, value: draft.problem ?? draft.phase.errorMessage)
                    DSButton(
                        L10n.Browse.newFolderConfirm,
                        style: .primary,
                        isLoading: draft.phase == .loading,
                        action: { store.send(.newFolderConfirmed) }
                    )
                    .disabled(!draft.canCreate)
                }
                .padding(Metrics.padding)
            }
            .task { isFocused = true }
        }
    }

    struct PickerRefusalLine: View {
        let message: String

        var body: some View {
            Label {
                Text(message).type(.body3(.regular), style: .secondary)
            } icon: {
                IconKit.info.foregroundStyle(Color.secondaryDS)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, .space16)
            .padding(.vertical, .space12)
            .background(Color.backgroundPrimary)
            .accessibilityElement(children: .combine)
        }
    }

    #Preview("New folder") {
        var state = DestinationPickerFeature.State(
            serverURL: URL(string: "https://example.com")!,
            items: [FileItem(name: "report.pdf", path: "Documents", dateModified: .now, size: 0, kind: "pdf")]
        )
        state.newFolder = .init(name: "Invoices/2026")
        return Color.clear.sheet(isPresented: .constant(true)) {
            PickerNewFolderSheet(store: Store(initialState: state) { EmptyReducer() })
        }
    }

    #Preview("Refusal") {
        PickerRefusalLine(message: L10n.Browse.destinationPickerIntoItself)
    }
#endif
