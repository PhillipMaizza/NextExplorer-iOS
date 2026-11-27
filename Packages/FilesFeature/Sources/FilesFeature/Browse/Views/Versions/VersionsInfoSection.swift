#if os(iOS)
    import CoreModels
    import Dependencies
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let shownVersions = 2
        static let fadedOpacity: Double = .opacityHalf
        static let rowSpacing: CGFloat = .space12
    }

    struct VersionsInfoSection: View {
        let item: FileItem
        let serverURL: URL
        let account: String
        let model: VersionsModel
        let onShowAll: () -> Void

        var body: some View {
            Group {
                if let history = model.history(for: item), history.rights.canSee {
                    VStack(alignment: .leading, spacing: Metrics.rowSpacing) {
                        DSFieldLabel(L10n.FileInfo.sectionVersions)
                            .accessibilityAddTraits(.isHeader)
                        if history.versions.isEmpty {
                            Text(L10n.FileInfo.versionsNone).type(.body3(.regular), style: .secondary)
                        } else {
                            ForEach(
                                Array(history.versions.prefix(Metrics.shownVersions + 1).enumerated()),
                                id: \.element.id
                            ) { index, version in
                                VersionRow(
                                    title: version.label ?? VersionsModel.date(version.modifiedAt),
                                    subtitle: version.rowSubtitle,
                                    badge: version.isPinned ? L10n.FileInfo.versionKept : nil
                                )
                                .opacity(index < Metrics.shownVersions ? 1 : Metrics.fadedOpacity)
                            }
                            Button(L10n.Browse.actionShowAllVersions, action: onShowAll)
                                .type(.body3(.semibold), style: .link)
                        }
                    }
                    .transition(.opacity)
                }
            }
            .animation(DSMotion.stateFade, value: model.history(for: item))
            .task(id: item.id) { await model.load(item: item, serverURL: serverURL, account: account) }
        }
    }

    #Preview("Folded, three versions") {
        let model = withDependencies {
            $0.filesClient.fetchVersions = { _, _ in
                FileVersionHistory(
                    isEnabled: true,
                    versions: (1 ... 3).map {
                        FileVersion(
                            id: "\($0)",
                            size: 46_000,
                            modifiedAt: .now.addingTimeInterval(-Double($0) * 86_400),
                            capturedAt: .now,
                            isPinned: $0 == 1
                        )
                    },
                    totalBytes: 138_000,
                    rights: .init(canSee: true, canDownload: true, canRestore: true, canRemove: true)
                )
            }
        } operation: {
            VersionsModel()
        }
        VersionsInfoSection(
            item: browsePreviewItems[2],
            serverURL: URL(fileURLWithPath: "/"),
            account: "",
            model: model,
            onShowAll: {}
        )
        .padding(.space24)
    }
#endif
