#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let hoverInset: CGFloat = .space4
    }

    struct MacShareTitle: View {
        let store: StoreOf<SharedFeature>
        let name: String
        let share: Share?
        let isEditable: Bool

        @State private var isHovering = false
        @FocusState private var isFieldFocused: Bool
        @State private var appearedAt = Date.distantPast

        private var editStore: StoreOf<EditShareFeature>? {
            guard store.editPopover == .label, store.editSheet?.share.id == share?.id else { return nil }
            return store.scope(state: \.editSheet, action: \.editSheet.presented)
        }

        var body: some View {
            if let editStore {
                TextField(
                    L10n.CreateShare.sectionLabel,
                    text: Binding(get: { editStore.label }, set: { editStore.send(.labelChanged($0)) }),
                    prompt: Text(name)
                )
                .textFieldStyle(.plain)
                .type(.headline4)
                .focused($isFieldFocused)
                .padding(.horizontal, Metrics.hoverInset)
                .macFieldChrome(isFocused: isFieldFocused, size: .flexible)
                .padding(.horizontal, -Metrics.hoverInset)
                .disabled(editStore.isSaving)
                .onAppear {
                    appearedAt = .now
                    isFieldFocused = true
                    DispatchQueue.main.async { isFieldFocused = true }
                }
                .onSubmit { store.send(.labelEditEnded) }
                .onExitCommand { store.send(.editPopoverDismissed) }
                .onChange(of: isFieldFocused) { _, isFocused in
                    guard !isFocused, store.editPopover == .label else { return }
                    if Date.now.timeIntervalSince(appearedAt) < MacInlineRenameField.focusSettleInterval {
                        isFieldFocused = true
                    } else {
                        store.send(.labelEditEnded)
                    }
                }
            } else if isEditable, let share {
                Text(name)
                    .type(.headline4)
                    .lineLimit(3)
                    .padding(.horizontal, Metrics.hoverInset)
                    .background(
                        RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                            .fill(isHovering ? Color.macRow : Color.clear)
                    )
                    .padding(.horizontal, -Metrics.hoverInset)
                    .contentShape(Rectangle())
                    .onHover { isHovering = $0 }
                    .onTapGesture { store.send(.editPopoverTapped(share, .label)) }
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint(L10n.Browse.renameTitle)
            } else {
                Text(name)
                    .type(.headline4)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
        }
    }

    #Preview("Title") {
        MacShareTitle(
            store: Store(initialState: sharedPreviewState()) { SharedFeature() },
            name: "Team Roadmap",
            share: Share.previewSharedByMe[0],
            isEditable: true
        )
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacInspectorMetrics.width)
    }
#endif
