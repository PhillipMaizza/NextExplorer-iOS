#if os(iOS)
    import CoreModels
    import Dependencies
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    struct VersionsPage: View {
        let item: FileItem
        let serverURL: URL
        let account: String
        let model: VersionsModel
        let onFilesChanged: () -> Void

        @State private var phase: DataPhase = .loading

        var body: some View {
            content
                .navigationTitle(L10n.FileInfo.sectionVersions)
                .navigationBarTitleDisplayMode(.inline)
                .modifier(VersionsDialogs(model: model))
                .task(id: item.id) { await load() }
        }

        @ViewBuilder
        private var content: some View {
            if let history = model.history(for: item), history.rights.canSee {
                list(history)
            } else if let failure = phase.errorMessage {
                EmptyStateView(icon: IconKit.warning, message: failure) {
                    Task { await load() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if phase == .loading {
                DSSpinner()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                EmptyStateView(icon: IconKit.time, message: L10n.FileInfo.versionsNone)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        private func list(_ history: FileVersionHistory) -> some View {
            List {
                Section {
                    VersionRow(
                        title: item.dateModified.formatted(date: .abbreviated, time: .shortened),
                        subtitle: FileSizeFormat.string(item.size),
                        badge: L10n.FileInfo.versionCurrent
                    )
                } header: {
                    DSFieldLabel(item.name)
                } footer: {
                    if let message = model.errorMessage ?? model.statusMessage {
                        Text(message).type(.body3(.regular), style: model.errorMessage == nil ? .secondary : .error)
                    } else if history.versions.isEmpty {
                        Text(L10n.FileInfo.versionsNone).type(.body3(.regular), style: .secondary)
                    }
                }
                ForEach(Self.days(history.versions), id: \.day) { group in
                    Section {
                        ForEach(group.versions) { version in
                            row(version, rights: history.rights)
                        }
                    } header: {
                        DSFieldLabel(group.day.formatted(date: .complete, time: .omitted))
                    }
                }
            }
            .listStyle(.insetGrouped)
            .refreshable { await load() }
        }

        private func row(_ version: FileVersion, rights: FileVersionHistory.Rights) -> some View {
            HStack(spacing: .space8) {
                VersionRow(
                    title: version.rowTitle,
                    subtitle: version.rowSubtitle,
                    badge: version.isPinned ? L10n.FileInfo.versionKept : nil
                )
                if rights.hasVersionActions {
                    Menu {
                        VersionActions(model: model, rights: rights, version: version)
                    } label: {
                        IconKit.moreOptions
                            .foregroundStyle(Color.secondaryDS)
                            .frame(width: .size44, height: .size44)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(L10n.FileInfo.versionActions)
                }
            }
            .contextMenu {
                VersionActions(model: model, rights: rights, version: version)
            }
            .swipeActions(edge: .trailing) {
                if rights.canRestore, version.isAvailable != false {
                    Button(L10n.FileInfo.restoreConfirm) { model.versionToRestore = version }
                        .tint(Color.accent)
                }
            }
        }

        private func load() async {
            phase = .loading
            model.onFilesChanged = onFilesChanged
            await model.load(item: item, serverURL: serverURL, account: account)
            guard !Task.isCancelled else { return }
            phase = model.history(for: item) == nil ? .failed(L10n.FileInfo.versionsLoadFailed) : .loaded
        }

        static func days(_ versions: [FileVersion]) -> [(day: Date, versions: [FileVersion])] {
            let calendar = Calendar.current
            return Dictionary(grouping: versions) { calendar.startOfDay(for: $0.modifiedAt) }
                .map { (day: $0.key, versions: $0.value.sorted { $0.modifiedAt > $1.modifiedAt }) }
                .sorted { $0.day > $1.day }
        }
    }

    @MainActor
    private func versionsPreview(_ history: FileVersionHistory?) -> some View {
        let model = withDependencies {
            $0.filesClient.fetchVersions = { _, _ in
                guard let history else { throw FilesClientError.offline }
                return history
            }
        } operation: {
            VersionsModel()
        }
        return NavigationStack {
            VersionsPage(
                item: browsePreviewItems[2],
                serverURL: URL(fileURLWithPath: "/"),
                account: "",
                model: model,
                onFilesChanged: {}
            )
        }
    }

    private let previewHistory = FileVersionHistory(
        isEnabled: true,
        versions: [
            FileVersion(
                id: "1",
                size: 47_000,
                modifiedAt: .now.addingTimeInterval(-3_600),
                capturedAt: .now,
                label: "Final draft",
                isPinned: true
            ),
            FileVersion(id: "2", size: 46_000, modifiedAt: .now.addingTimeInterval(-90_000), capturedAt: .now),
            FileVersion(id: "3", size: 45_000, modifiedAt: .now.addingTimeInterval(-260_000), capturedAt: .now),
        ],
        totalBytes: 138_000,
        rights: .init(canSee: true, canDownload: true, canRestore: true, canRemove: true)
    )

    #Preview("Versions") {
        versionsPreview(previewHistory)
    }

    #Preview("Failed, dark") {
        versionsPreview(nil)
            .preferredColorScheme(.dark)
    }
#endif
