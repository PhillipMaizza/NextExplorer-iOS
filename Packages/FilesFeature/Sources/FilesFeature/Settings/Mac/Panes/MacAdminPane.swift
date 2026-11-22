#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    extension View {
        /// A text field that shows it can be typed in: the rounded field with an outline that stays
        /// visible against a dark grouped row, where the system border all but disappears.
        func macEditableField() -> some View {
            textFieldStyle(.roundedBorder)
                .overlay(RoundedRectangle(cornerRadius: .radiusXSmall)
                    .strokeBorder(Color.secondary.opacity(MacEditableFieldMetrics.outlineOpacity)))
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

    struct MacAdminPane<Content: View>: View {
        let isUnavailable: Bool
        let unavailableMessage: String
        var failureMessage: String?
        let isLoadingFirstTime: Bool
        var save: MacAdminSave?
        var isFormPage = false
        let onAppear: () -> Void
        @ViewBuilder let content: () -> Content

        var body: some View {
            Group {
                if isFormPage {
                    MacFormPage {
                        if isUnavailable {
                            MacNote(unavailableMessage, kind: .info)
                        } else if let failureMessage {
                            MacNote(failureMessage, kind: .error)
                            Button(L10n.Common.retry, action: onAppear)
                                .buttonStyle(.macDS(.secondary, size: .small))
                        } else if isLoadingFirstTime {
                            MacSpinner()
                                .frame(maxWidth: .infinity)
                        } else {
                            content()
                        }
                    }
                } else if isUnavailable {
                    MacSettingsForm { MacSettingsNote(unavailableMessage) }
                } else if let failureMessage {
                    MacSettingsForm {
                        Text(failureMessage).foregroundStyle(Color.negativeText)
                        Button(L10n.Common.retry, action: onAppear)
                    }
                } else if let save {
                    MacSettingsPane(content: content).macSettingsSaveBar(
                        save.title,
                        isSaving: save.isSaving,
                        isEnabled: save.isEnabled,
                        action: save.action
                    )
                } else {
                    MacSettingsPane(content: content)
                }
            }
            .overlay {
                if isLoadingFirstTime, !isUnavailable, !isFormPage {
                    MacSpinner()
                }
            }
            .disabled(save?.isSaving ?? false)
            .onAppear(perform: onAppear)
        }
    }

    struct MacExcludedPathsGroups: View {
        let environmentTitle: String
        let additionalTitle: String
        let emptyTitle: String
        let placeholder: String
        let addTitle: String
        let environmentPaths: [String]
        let displayedPaths: [String]
        let checkedPaths: [String]
        @Binding var newPath: String
        let isEnabled: Bool
        let onAdd: () -> Void
        let onToggle: (String) -> Void

        var body: some View {
            MacFormGroup(environmentTitle) {
                if environmentPaths.isEmpty {
                    MacFormRow {
                        Text(emptyTitle).foregroundStyle(Color.macChromeSecondary)
                    } control: {
                        EmptyView()
                    }
                }
                ForEach(environmentPaths, id: \.self) { path in
                    MacFormRow {
                        Text(path).monospaced()
                    } control: {
                        EmptyView()
                    }
                }
            }
            MacFormGroup(additionalTitle) {
                ForEach(displayedPaths, id: \.self) { path in
                    pathRow(path, isExcluded: checkedPaths.contains(path))
                }
                MacFormRow {
                    MacTextField(placeholder, text: $newPath, prompt: placeholder)
                        .autocorrectionDisabled()
                        .onSubmit(onAdd)
                } control: {
                    Button(addTitle, action: onAdd)
                        .buttonStyle(.macDS(.secondary, size: .small))
                        .disabled(newPath.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .disabled(!isEnabled)
        }

        private func pathRow(_ path: String, isExcluded: Bool) -> some View {
            MacFormRow {
                Text(path)
                    .monospaced()
                    .strikethrough(!isExcluded)
                    .foregroundStyle(isExcluded ? Color.macChromeText : .macChromeSecondary)
            } control: {
                if isExcluded {
                    Button(L10n.Common.remove, role: .destructive) { onToggle(path) }
                        .buttonStyle(.macDS(.secondary, size: .small))
                } else {
                    Button(addTitle) { onToggle(path) }
                        .buttonStyle(.macDS(.secondary, size: .small))
                }
            }
        }
    }
#endif
