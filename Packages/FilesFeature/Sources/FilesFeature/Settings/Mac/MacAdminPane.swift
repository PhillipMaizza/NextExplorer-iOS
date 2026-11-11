#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    extension View {
        /// A text field that shows it can be typed in: the rounded field with an outline that stays
        /// visible against a dark grouped row, where the system border all but disappears.
        func macEditableField() -> some View {
            textFieldStyle(.roundedBorder)
                .overlay(RoundedRectangle(cornerRadius: .radiusXSmall).strokeBorder(Color.secondary.opacity(MacEditableFieldMetrics.outlineOpacity)))
        }
    }

    private enum MacEditableFieldMetrics {
        static let outlineOpacity: Double = 0.45
    }

    /// What a Mac admin pane saves with its bar under the form.
    struct MacAdminSave {
        let title: String
        let isSaving: Bool
        let isEnabled: Bool
        let action: () -> Void
    }

    /// The shell every admin pane shares: a message for a non admin, a failed first load with a retry
    /// instead of a form of defaults, a spinner over a first load, and the save bar when the pane
    /// has something to save.
    struct MacAdminPane<Content: View>: View {
        let isUnavailable: Bool
        let unavailableMessage: String
        var failureMessage: String?
        let isLoadingFirstTime: Bool
        var save: MacAdminSave?
        let onAppear: () -> Void
        @ViewBuilder let content: () -> Content

        var body: some View {
            Group {
                if isUnavailable {
                    MacSettingsForm { MacSettingsNote(unavailableMessage) }
                } else if let failureMessage {
                    MacSettingsForm {
                        Text(failureMessage).foregroundStyle(Color.negativeText)
                        Button(L10n.Common.retry, action: onAppear)
                    }
                } else if let save {
                    form.macSettingsSaveBar(save.title, isSaving: save.isSaving, isEnabled: save.isEnabled, action: save.action)
                } else {
                    form
                }
            }
            .overlay {
                if isLoadingFirstTime, !isUnavailable {
                    MacSpinner()
                }
            }
            .onAppear(perform: onAppear)
        }

        private var form: some View {
            MacSettingsPane {
                content()
            }
            .disabled(save?.isSaving ?? false)
        }
    }

    /// The folders a feature skips, as grouped sections: the environment's own, then the admin's,
    /// each a checkbox that is ticked while the folder is excluded, and a field to add another.
    struct MacExcludedPathsSections: View {
        let environmentTitle: String
        let additionalTitle: String
        let emptyTitle: String
        let placeholder: String
        let addTitle: String
        let discardTitle: String
        let environmentPaths: [String]
        let displayedPaths: [String]
        let checkedPaths: [String]
        @Binding var newPath: String
        let isDirty: Bool
        let isEnabled: Bool
        let onAdd: () -> Void
        let onToggle: (String) -> Void
        let onDiscard: () -> Void

        var body: some View {
            if !environmentPaths.isEmpty {
                Section(environmentTitle) {
                    ForEach(environmentPaths, id: \.self) { path in
                        Text(path).monospaced()
                    }
                }
            }
            Section(additionalTitle) {
                if displayedPaths.isEmpty {
                    Text(emptyTitle).foregroundStyle(.secondary)
                }
                ForEach(displayedPaths, id: \.self) { path in
                    Toggle(isOn: Binding(get: { checkedPaths.contains(path) }, set: { _ in onToggle(path) })) {
                        Text(path).monospaced()
                    }
                    .toggleStyle(.checkbox)
                }
                HStack(spacing: .space8) {
                    TextField(placeholder, text: $newPath, prompt: Text(placeholder))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .onSubmit(onAdd)
                    Button(addTitle, action: onAdd)
                        .disabled(newPath.trimmingCharacters(in: .whitespaces).isEmpty)
                    if isDirty {
                        Button(discardTitle, action: onDiscard)
                    }
                }
            }
            .disabled(!isEnabled)
        }
    }
#endif
