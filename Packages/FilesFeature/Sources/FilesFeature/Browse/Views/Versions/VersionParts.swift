#if os(iOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let badgeHorizontalPadding: CGFloat = .space8
        static let badgeVerticalPadding: CGFloat = .space2
    }

    struct VersionRow: View {
        let title: String
        let subtitle: String
        var badge: String?

        var body: some View {
            VStack(alignment: .leading, spacing: .space2) {
                HStack(spacing: .space8) {
                    Text(title)
                        .type(.body2(.regular), style: .primaryOnSurface)
                        .lineLimit(1)
                    if let badge {
                        Text(badge)
                            .type(.caption(.semibold), style: .secondary)
                            .padding(.horizontal, Metrics.badgeHorizontalPadding)
                            .padding(.vertical, Metrics.badgeVerticalPadding)
                            .background(Capsule().fill(Color.secondaryDS.opacity(.opacityWash)))
                    }
                }
                Text(subtitle)
                    .type(.body3(.regular), style: .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
        }
    }

    struct VersionActions: View {
        let model: VersionsModel
        let rights: FileVersionHistory.Rights
        let version: FileVersion

        var body: some View {
            let isAvailable = version.isAvailable != false
            if rights.canRestore {
                Button(L10n.FileInfo.versionRestore) { model.versionToRestore = version }
                    .disabled(!isAvailable)
            }
            if rights.canDownload {
                Button(L10n.FileInfo.versionDownload) { model.download(version) }
                    .disabled(!isAvailable)
                Button(L10n.FileInfo.versionSaveCopy) { model.saveCopy(version) }
                    .disabled(!isAvailable)
            }
            if rights.canRestore {
                Divider()
                Button(L10n.FileInfo.versionRename) { model.beginRename(version) }
                Button(version.isPinned ? L10n.FileInfo.versionUnpin : L10n.FileInfo.versionPin) {
                    model.togglePin(version)
                }
            }
            if rights.canRemove {
                Divider()
                Button(L10n.FileInfo.versionDelete, role: .destructive) { model.versionToDelete = version }
            }
        }
    }

    @MainActor
    extension FileVersion {
        var rowTitle: String {
            label ?? modifiedAt.formatted(date: .omitted, time: .shortened)
        }

        var rowSubtitle: String {
            var parts: [String] = []
            if label != nil {
                parts.append(modifiedAt.formatted(date: .omitted, time: .shortened))
            }
            if let author = author?.label {
                parts.append(author)
            }
            parts.append(FileSizeFormat.string(size))
            return parts.joined(separator: " \u{00B7} ")
        }
    }

    struct VersionsDialogs: ViewModifier {
        @Bindable var model: VersionsModel

        func body(content: Content) -> some View {
            content
                .dsAlert(isPresented: isPresented(\.versionToRestore)) {
                    let version = model.versionToRestore
                    return DSAlertSheet(
                        icon: IconKit.restore,
                        title: L10n.FileInfo.restoreTitle,
                        message: version.map { L10n.FileInfo.restoreMessage(VersionsModel.date($0.modifiedAt)) },
                        confirmTitle: L10n.FileInfo.restoreConfirm,
                        dismissTitle: L10n.Common.cancel,
                        closeAccessibilityLabel: L10n.Common.close,
                        onConfirm: {
                            if let version {
                                model.restoreConfirmed(version)
                            }
                        },
                        onDismiss: { model.versionToRestore = nil }
                    )
                }
                .dsAlert(isPresented: isPresented(\.versionToDelete)) {
                    let version = model.versionToDelete
                    return DSAlertSheet(
                        icon: IconKit.delete,
                        title: L10n.FileInfo.deleteTitle,
                        message: L10n.FileInfo.deleteMessage,
                        confirmTitle: L10n.Common.delete,
                        dismissTitle: L10n.Common.cancel,
                        role: .destructive,
                        closeAccessibilityLabel: L10n.Common.close,
                        onConfirm: {
                            if let version {
                                model.deleteConfirmed(version)
                            }
                        },
                        onDismiss: { model.versionToDelete = nil }
                    )
                }
                .dsSheet(item: $model.versionToRename) { version in
                    NameInputSheet(
                        icon: IconKit.rename,
                        title: L10n.FileInfo.renameTitle,
                        placeholder: L10n.FileInfo.renamePlaceholder,
                        confirmTitle: L10n.Common.save,
                        initialName: model.renameDraft,
                        isBusy: false,
                        onConfirm: { name in
                            model.renameDraft = name
                            model.renameConfirmed(version)
                        },
                        onCancel: { model.versionToRename = nil }
                    )
                }
                .keptFilesShareSheet(model.sharedDownload) { model.shareFinished() }
        }

        private func isPresented(_ keyPath: ReferenceWritableKeyPath<VersionsModel, (some Any)?>) -> Binding<Bool> {
            Binding(
                get: { model[keyPath: keyPath] != nil },
                set: { isPresented in
                    if !isPresented {
                        model[keyPath: keyPath] = nil
                    }
                }
            )
        }
    }

    #Preview("Rows") {
        List {
            VersionRow(title: "09:12", subtitle: "48 KB", badge: L10n.FileInfo.versionCurrent)
            VersionRow(title: "Final draft", subtitle: "18:40 \u{00B7} 47 KB", badge: L10n.FileInfo.versionKept)
            VersionRow(title: "11:20", subtitle: "Phillip \u{00B7} 46 KB")
        }
    }
#endif
