#if os(macOS)
    import CoreModels
    import DesignSystem
    import FolderPickerFeature
    import Localization
    import SwiftUI

    struct MacVersionsDialogs: ViewModifier {
        @Bindable var model: VersionsModel

        func body(content: Content) -> some View {
            content
                .sheet(isPresented: isPresented(\.versionToRestore)) {
                    let version = model.versionToRestore
                    MacAlertSheet(
                        icon: .restore,
                        title: L10n.FileInfo.restoreTitle,
                        message: version.map { L10n.FileInfo.restoreMessage(VersionsModel.date($0.modifiedAt)) },
                        confirmTitle: L10n.FileInfo.restoreConfirm,
                        isDestructive: false,
                        onConfirm: {
                            if let version {
                                _ = model.restoreConfirmed(version)
                            }
                        },
                        onCancel: { model.versionToRestore = nil }
                    )
                }
                .sheet(isPresented: isPresented(\.versionToRename)) {
                    let version = model.versionToRename
                    MacFormSheet(
                        title: L10n.FileInfo.renameTitle,
                        confirmTitle: L10n.Common.save,
                        onCancel: { model.versionToRename = nil },
                        onConfirm: {
                            if let version {
                                model.renameConfirmed(version)
                            }
                        }
                    ) {
                        MacTextField(
                            L10n.FileInfo.renamePlaceholder,
                            text: Binding(
                                get: { model.renameDraft },
                                set: { model.renameDraft = FileVersion.cappedLabel($0) }
                            ),
                            prompt: L10n.FileInfo.renamePlaceholder
                        )
                        .onSubmit {
                            if let version {
                                model.renameConfirmed(version)
                            }
                        }
                    }
                }
                .sheet(isPresented: isPresented(\.versionToDelete)) {
                    let version = model.versionToDelete
                    MacAlertSheet(
                        icon: .delete,
                        title: L10n.FileInfo.deleteTitle,
                        message: L10n.FileInfo.deleteMessage,
                        confirmTitle: L10n.Common.delete,
                        onConfirm: {
                            if let version {
                                model.deleteConfirmed(version)
                            }
                        },
                        onCancel: { model.versionToDelete = nil }
                    )
                }
                .sheet(isPresented: isPresented(\.replacePicker)) {
                    if let store = model.replacePicker {
                        DestinationPickerView(store: store)
                    }
                }
                .sheet(isPresented: isPresented(\.replacement)) {
                    let replacement = model.replacement
                    MacAlertSheet(
                        icon: .warning,
                        title: L10n.FileInfo.replaceTitle,
                        message: replacement.map {
                            L10n.FileInfo.replaceMessage(
                                ($0.targetPath as NSString).lastPathComponent,
                                VersionsModel.date($0.version.modifiedAt)
                            )
                        },
                        confirmTitle: L10n.Browse.transferConflictReplace,
                        onConfirm: {
                            if let replacement {
                                _ = model.replaceConfirmed(replacement)
                            }
                        },
                        onCancel: { model.replacement = nil }
                    )
                }
                .sheet(item: $model.textPreview) { preview in
                    MacVersionTextSheet(preview: preview)
                }
                .sheet(isPresented: $model.isConfirmingDeleteAll) {
                    MacAlertSheet(
                        icon: .delete,
                        title: L10n.FileInfo.deleteAllTitle,
                        message: L10n.FileInfo.deleteMessage,
                        confirmTitle: L10n.Common.delete,
                        onConfirm: { model.deleteAllConfirmed() },
                        onCancel: { model.isConfirmingDeleteAll = false }
                    )
                }
        }

        private func isPresented(_ keyPath: ReferenceWritableKeyPath<VersionsModel, (some Any)?>) -> Binding<Bool> {
            Binding(get: { model[keyPath: keyPath] != nil }, set: {
                if !$0 {
                    model[keyPath: keyPath] = nil
                }
            })
        }
    }

    #Preview("Delete all confirmation") {
        let model = VersionsModel()
        model.isConfirmingDeleteAll = true
        return Text(verbatim: "report.pdf")
            .previewCanvas(.inspector)
            .modifier(MacVersionsDialogs(model: model))
    }
#endif
