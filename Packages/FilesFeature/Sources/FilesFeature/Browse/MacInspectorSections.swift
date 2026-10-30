#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// Get Info's Sharing section: the share links made for this item, each with Copy, and
    /// Share… to make another.
    struct MacInspectorSharingSection: View {
        let shares: [Share]
        let serverURL: URL
        var onShare: (() -> Void)?

        var body: some View {
            Section(L10n.FileInfo.sectionSharing) {
                if shares.isEmpty {
                    Text(L10n.FileInfo.notShared).foregroundStyle(.secondary)
                }
                ForEach(shares) { share in
                    LabeledContent {
                        Button(L10n.Common.copy) { PlatformPasteboard.copy(share.shareLink(serverURL: serverURL)) }
                    } label: {
                        MacRowTitle(title: share.label ?? share.displayName, subtitle: subtitle(for: share))
                    }
                }
                if let onShare {
                    HStack {
                        Spacer()
                        Button(L10n.Common.share + "…", action: onShare)
                    }
                }
            }
        }

        private func subtitle(for share: Share) -> String {
            var parts = [share.accessMode.title]
            if let expiresAt = share.expiresAt {
                parts.append(expiresAt <= Date() ? L10n.Shared.badgeExpired : expiresAt.formatted(date: .abbreviated, time: .omitted))
            }
            return parts.joined(separator: " · ")
        }
    }

    /// Get Info's Versions section: the file's saved versions, newest first, each with a menu of
    /// what the caller's rights allow, and Delete All Versions under them.
    struct MacInspectorVersionsSection: View {
        let model: MacVersionsModel
        let history: FileVersionHistory

        var body: some View {
            Section {
                if history.versions.isEmpty {
                    Text(L10n.FileInfo.versionsNone).foregroundStyle(.secondary)
                }
                ForEach(history.versions) { version in
                    LabeledContent {
                        HStack(spacing: .space4) {
                            if version.isPinned {
                                IconKit.pinFill
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(L10n.FileInfo.versionKept)
                            }
                            actionsMenu(version)
                        }
                    } label: {
                        MacRowTitle(title: version.label ?? MacVersionsModel.date(version.modifiedAt), subtitle: subtitle(for: version))
                    }
                }
                if history.rights.canRemove, !history.versions.isEmpty {
                    HStack {
                        Spacer()
                        Button(L10n.FileInfo.deleteAll, role: .destructive) { model.isConfirmingDeleteAll = true }
                    }
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage).foregroundStyle(Color.negativeText)
                }
            } header: {
                Text(L10n.FileInfo.sectionVersions)
            }
        }

        private func actionsMenu(_ version: FileVersion) -> some View {
            let isAvailable = version.isAvailable != false
            return Menu {
                if history.rights.canRestore {
                    Button(L10n.FileInfo.versionRestore) { model.versionToRestore = version }
                        .disabled(!isAvailable)
                }
                if history.rights.canDownload {
                    Button(L10n.FileInfo.versionDownload) { model.download(version) }
                        .disabled(!isAvailable)
                    Button(L10n.FileInfo.versionSaveCopy) { model.saveCopy(version) }
                        .disabled(!isAvailable)
                }
                if history.rights.canRestore {
                    Divider()
                    Button(L10n.FileInfo.versionRename) { model.beginRename(version) }
                    Button(version.isPinned ? L10n.FileInfo.versionUnpin : L10n.FileInfo.versionPin) { model.togglePin(version) }
                }
                if history.rights.canRemove {
                    Divider()
                    Button(L10n.FileInfo.versionDelete, role: .destructive) { model.versionToDelete = version }
                }
            } label: {
                IconKit.moreOptions
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(L10n.FileInfo.versionActions)
        }

        private func subtitle(for version: FileVersion) -> String {
            var parts: [String] = []
            if version.label != nil {
                parts.append(MacVersionsModel.date(version.modifiedAt))
            }
            if let author = version.author?.label {
                parts.append(author)
            }
            parts.append(FileSizeFormat.string(version.size))
            return parts.joined(separator: " · ")
        }
    }

    #Preview("Sharing") {
        Form {
            MacInspectorSharingSection(
                shares: [.previewCard(), .previewCard(target: .users, hasPassword: true)],
                serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
                onShare: {}
            )
        }
        .formStyle(.grouped)
        .previewCanvas(.inspector)
    }

    #Preview("Not shared") {
        Form {
            MacInspectorSharingSection(shares: [], serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"), onShare: {})
        }
        .formStyle(.grouped)
        .previewCanvas(.inspector)
    }

    #Preview("Versions") {
        let hour: TimeInterval = 3_600
        let history = FileVersionHistory(
            isEnabled: true,
            versions: [
                FileVersion(id: "v2", size: 18_400, modifiedAt: Date().addingTimeInterval(-hour * 3), capturedAt: Date().addingTimeInterval(-hour * 2)),
                FileVersion(id: "v1", size: 16_100, modifiedAt: Date().addingTimeInterval(-hour * 50), capturedAt: Date().addingTimeInterval(-hour * 49), label: "Before edits", isPinned: true),
            ],
            totalBytes: 34_500,
            rights: .init(canSee: true, canDownload: true, canRestore: true, canRemove: true)
        )
        return Form {
            MacInspectorVersionsSection(model: MacVersionsModel(), history: history)
        }
        .formStyle(.grouped)
        .previewCanvas(.inspector)
    }
#endif
