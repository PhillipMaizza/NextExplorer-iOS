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
                            if version.pinned {
                                Image(systemName: "pin.fill")
                                    .foregroundStyle(.secondary)
                                    .accessibilityLabel(L10n.FileInfo.versionKept)
                            }
                            actionsMenu(version)
                        }
                    } label: {
                        MacRowTitle(title: version.label ?? MacVersionsModel.date(version.modifiedAt), subtitle: subtitle(for: version))
                    }
                }
                if history.rights.remove, !history.versions.isEmpty {
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
            let isAvailable = version.available != false
            return Menu {
                if history.rights.restore {
                    Button(L10n.FileInfo.versionRestore) { model.versionToRestore = version }
                        .disabled(!isAvailable)
                }
                if history.rights.download {
                    Button(L10n.FileInfo.versionDownload) { model.download(version) }
                        .disabled(!isAvailable)
                    Button(L10n.FileInfo.versionSaveCopy) { model.saveCopy(version) }
                        .disabled(!isAvailable)
                }
                if history.rights.restore {
                    Divider()
                    Button(L10n.FileInfo.versionRename) { model.beginRename(version) }
                    Button(version.pinned ? L10n.FileInfo.versionUnpin : L10n.FileInfo.versionPin) { model.togglePin(version) }
                }
                if history.rights.remove {
                    Divider()
                    Button(L10n.FileInfo.versionDelete, role: .destructive) { model.versionToDelete = version }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
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
            parts.append(SettingsFormat.byteFormatter.string(fromByteCount: version.size))
            return parts.joined(separator: " · ")
        }
    }
#endif
