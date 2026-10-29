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

    /// Get Info's Versions section: the file's saved versions, newest first, each with Restore…
    /// when the caller may restore and the version's storage is still there.
    struct MacInspectorVersionsSection: View {
        let history: FileVersionHistory
        let errorMessage: String?
        let onRestore: (FileVersion) -> Void

        var body: some View {
            Section {
                if history.versions.isEmpty {
                    Text(L10n.FileInfo.versionsNone).foregroundStyle(.secondary)
                }
                ForEach(history.versions) { version in
                    LabeledContent {
                        if history.rights.restore, version.available != false {
                            Button(L10n.FileInfo.versionRestore) { onRestore(version) }
                        }
                    } label: {
                        MacRowTitle(title: version.label ?? Self.date(version.modifiedAt), subtitle: subtitle(for: version))
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color.negativeText)
                }
            } header: {
                Text(L10n.FileInfo.sectionVersions)
            }
        }

        private func subtitle(for version: FileVersion) -> String {
            var parts: [String] = []
            if version.label != nil {
                parts.append(Self.date(version.modifiedAt))
            }
            if let author = version.author?.label {
                parts.append(author)
            }
            parts.append(SettingsFormat.byteFormatter.string(fromByteCount: version.size))
            return parts.joined(separator: " · ")
        }

        static func date(_ date: Date) -> String {
            date.formatted(date: .abbreviated, time: .shortened)
        }
    }
#endif
