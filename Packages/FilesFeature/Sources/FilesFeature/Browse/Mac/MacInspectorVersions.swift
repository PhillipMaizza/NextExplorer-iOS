#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let dotSize: CGFloat = .size16
        static let dotStroke: CGFloat = .borderWidthFocused
        static let lineWidth: CGFloat = .size2
        static let rowSpacing: CGFloat = .space12
        static let headerSpacing: CGFloat = .space8
        static let ringInset: CGFloat = -.space8
        static let ringRadius: CGFloat = .radiusMedium
        static let ringHold: Duration = .seconds(1)
    }

    struct MacInspectorVersionsSection: View {
        static let anchor = "versions"

        let model: MacVersionsModel
        let history: FileVersionHistory
        let current: FileItem
        var onReveal: () -> Void = {}
        @State private var isRinged = false

        var body: some View {
            section
                .overlay {
                    RoundedRectangle(cornerRadius: Metrics.ringRadius, style: .continuous)
                        .strokeBorder(Color.accent, lineWidth: .borderWidthFocused)
                        .padding(Metrics.ringInset)
                        .opacity(isRinged ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .onChange(of: model.revealRequest, initial: true) {
                    guard model.revealRequest == current.id else { return }
                    model.revealRequest = nil
                    onReveal()
                    withAnimation(DSMotion.quickFade) { isRinged = true }
                }
                .task(id: isRinged) {
                    guard isRinged else { return }
                    try? await Task.sleep(for: Metrics.ringHold)
                    guard !Task.isCancelled else { return }
                    withAnimation(DSMotion.fadeOut) { isRinged = false }
                }
        }

        private var section: some View {
            VStack(alignment: .leading, spacing: Metrics.headerSpacing) {
                MacInspectorSectionHeader(
                    title: L10n.FileInfo.sectionVersions,
                    count: history.versions.isEmpty ? nil : history.versions.count,
                    actionTitle: canDeleteAll ? L10n.FileInfo.deleteAll : nil,
                    isDestructive: true,
                    action: canDeleteAll ? { model.isConfirmingDeleteAll = true } : nil
                )
                VStack(alignment: .leading, spacing: .zero) {
                    entry(isCurrent: true, isLast: history.versions.isEmpty) {
                        HStack(spacing: .space8) {
                            Text(MacVersionsModel.date(current.dateModified)).type(.body3(.regular))
                            MacChip(text: L10n.FileInfo.versionCurrent, tone: .amber, size: .small)
                        }
                        Text(FileSizeFormat.string(current.size)).type(.caption(.regular), style: .secondary)
                    }
                    ForEach(history.versions) { version in
                        entry(isCurrent: false, isLast: version.id == history.versions.last?.id) {
                            HStack(spacing: .space8) {
                                Text(version.label ?? MacVersionsModel.date(version.modifiedAt))
                                    .type(.body3(.regular))
                                    .lineLimit(1)
                                if version.isPinned {
                                    MacChip(text: L10n.FileInfo.versionKept, tone: .gray, size: .small)
                                }
                                Spacer(minLength: .zero)
                                actionsMenu(version)
                            }
                            Text(subtitle(for: version)).type(.caption(.regular), style: .secondary)
                        }
                    }
                }
                if history.versions.isEmpty {
                    Text(L10n.FileInfo.versionsNone).type(.body3(.regular), style: .secondary)
                }
                if let errorMessage = model.errorMessage {
                    Text(errorMessage).type(.body3(.regular), style: .error)
                } else if let statusMessage = model.statusMessage {
                    Text(statusMessage).type(.body3(.regular), style: .secondary)
                }
            }
        }

        private var canDeleteAll: Bool {
            history.rights.canRemove && !history.versions.isEmpty
        }

        private func entry(
            isCurrent: Bool,
            isLast: Bool,
            @ViewBuilder content: () -> some View
        ) -> some View {
            HStack(alignment: .top, spacing: Metrics.rowSpacing) {
                Circle()
                    .strokeBorder(isCurrent ? Color.accent : Color.macLine, lineWidth: Metrics.dotStroke)
                    .background(Circle().fill(isCurrent ? Color.accent : Color.macCard))
                    .frame(width: Metrics.dotSize, height: Metrics.dotSize)
                    .padding(.top, .space2)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: .space2) {
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.bottom, isLast ? .zero : Metrics.rowSpacing)
            .background(alignment: .topLeading) {
                if !isLast {
                    Rectangle()
                        .fill(Color.macLine)
                        .frame(width: Metrics.lineWidth)
                        .padding(.top, Metrics.dotSize + .space2)
                        .padding(.leading, (Metrics.dotSize - Metrics.lineWidth) / 2)
                }
            }
            .accessibilityElement(children: .combine)
        }

        private func actionsMenu(_ version: FileVersion) -> some View {
            let isAvailable = version.isAvailable != false
            return Menu {
                if history.rights.canRestore {
                    Button(L10n.FileInfo.versionRestore) { model.versionToRestore = version }
                        .disabled(!isAvailable)
                }
                if model.canViewText {
                    Button(L10n.FileInfo.versionViewText) { model.viewText(version) }
                        .disabled(!isAvailable)
                }
                if history.rights.canDownload {
                    Button(L10n.FileInfo.versionDownload) { model.download(version) }
                        .disabled(!isAvailable)
                    Button(L10n.FileInfo.versionSaveCopy) { model.saveCopy(version) }
                        .disabled(!isAvailable)
                    Button(L10n.FileInfo.versionReplace) { model.beginReplace(version) }
                        .disabled(!isAvailable)
                }
                if history.rights.canRestore {
                    Divider()
                    Button(L10n.FileInfo.versionRename) { model.beginRename(version) }
                    Button(version.isPinned ? L10n.FileInfo.versionUnpin : L10n.FileInfo.versionPin) {
                        model.togglePin(version)
                    }
                }
                if history.rights.canRemove {
                    Divider()
                    Button(L10n.FileInfo.versionDelete, role: .destructive) { model.versionToDelete = version }
                }
            } label: {
                IconKit.moreOptions.foregroundStyle(Color.secondaryDS)
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
            return parts.joined(separator: " \u{00B7} ")
        }
    }

    #Preview("Versions") {
        let hour: TimeInterval = 3_600
        let history = FileVersionHistory(
            isEnabled: true,
            versions: [
                FileVersion(
                    id: "v2",
                    size: 18_400,
                    modifiedAt: Date().addingTimeInterval(-hour * 3),
                    capturedAt: Date().addingTimeInterval(-hour * 2)
                ),
                FileVersion(
                    id: "v1",
                    size: 16_100,
                    modifiedAt: Date().addingTimeInterval(-hour * 50),
                    capturedAt: Date().addingTimeInterval(-hour * 49),
                    label: "Before edits",
                    isPinned: true
                ),
            ],
            totalBytes: 34_500,
            rights: .init(canSee: true, canDownload: true, canRestore: true, canRemove: true)
        )
        return MacInspectorVersionsSection(
            model: MacVersionsModel(),
            history: history,
            current: FileItem(name: "notes.md", path: "Docs", dateModified: Date(), size: 19_000, kind: "md")
        )
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacInspectorMetrics.width)
        .background(Color.macCard)
    }
#endif
