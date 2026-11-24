#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct ArchivePeekCard: View {
        let store: StoreOf<ArchiveBrowserFeature>
        let onExtract: ([String]?) -> Void
        let onClose: () -> Void

        @FocusState private var isFocused: Bool

        private var openedFile: ArchiveListingEntry? {
            store.entry.flatMap { opened in store.files.first { $0.path == opened.path } }
        }

        var body: some View {
            VStack(spacing: .zero) {
                header
                MacPeekSeparator()
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                MacPeekSeparator()
                footer
            }
            .macPeekCardChrome()
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onAppear {
                isFocused = true
                store.send(.task)
            }
            .onDisappear { store.send(.closed) }
            .onKeyPress(.leftArrow) { step(-1) }
            .onKeyPress(.rightArrow) { step(1) }
            .onExitCommand(perform: onClose)
            .focusedSceneValue(
                \.archiveFolderBack,
                FocusedMenuAction(perform: goBack)
            )
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
            .accessibilityLabel(store.archive.name)
        }

        private var header: some View {
            HStack(spacing: .space12) {
                if store.isAtRoot {
                    MacItemTile(kind: store.archive.kind, isDirectory: false, size: MacPeekMetrics.iconSize)
                } else {
                    MacIconButton(IconKit.back, label: L10n.Common.back) { store.send(.backTapped) }
                }
                VStack(alignment: .leading, spacing: .space2) {
                    ArchivePeekCrumbs(names: store.crumbs, onTap: { store.send(.crumbTapped($0)) })
                    Text(subtitle)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if store.canExtract, store.phase == .loaded {
                    Button(L10n.Browse.actionExtract) { onExtract(store.extractPaths) }
                        .buttonStyle(.macDS(.primary, size: .small))
                }
                MacIconButton(IconKit.close, label: L10n.Common.close, action: onClose)
            }
            .padding(.leading, .space24)
            .padding(.trailing, .space16)
            .padding(.vertical, .space16)
        }

        @ViewBuilder
        private var content: some View {
            if let message = store.phase.errorMessage {
                FileSummaryView(item: store.archive, message: message)
            } else if store.phase != .loaded {
                DSSpinner()
            } else if let entry = store.entry, let openedFile {
                ArchivePeekStage(
                    file: openedFile,
                    phase: entry.phase,
                    files: store.files,
                    onStep: { store.send(.stepped($0)) },
                    onPick: { store.send(.fileOpened($0)) }
                )
            } else if store.entries.isEmpty {
                EmptyStateView(
                    icon: IconKit.folderFill,
                    message: store.path.isEmpty ? L10n.Archive.unreadable : L10n.Archive.emptyFolder
                )
            } else {
                ArchivePeekGrid(
                    entries: store.entries,
                    thumbnails: ArchiveThumbnailLoader(
                        archive: store.archive,
                        serverURL: store.serverURL,
                        source: store.source
                    )
                ) { store.send(.fileOpened($0)) }
            }
        }

        private var footer: some View {
            HStack(spacing: .space16) {
                if store.phase == .loaded {
                    Text(L10n.Shared.itemCount(store.entries.count))
                        .type(.caption(.regular), style: .secondary)
                        .monospacedDigit()
                }
                Spacer(minLength: .zero)
                if store.entry != nil {
                    MacPeekHint(key: MacShortcutHint.sideArrows, title: L10n.Spotlight.hintMove)
                }
                if !store.isAtRoot {
                    MacPeekHint(key: MacShortcutHint.back, title: L10n.Common.back)
                }
                MacPeekHint(key: MacShortcutHint.escape, title: L10n.Common.close)
            }
            .padding(.horizontal, .space24)
            .padding(.vertical, .space12)
        }

        private var subtitle: String {
            if let openedFile, let index = store.openedIndex {
                return ArchivePeekText.detail(
                    openedFile,
                    position: L10n.PdfPreview.pageIndicator(index + 1, store.files.count)
                )
            }
            guard store.path.isEmpty else { return L10n.FileInfo.navigationTitleFolder }
            return [store.archive.kind.uppercased(), FileSizeFormat.string(store.archive.size)]
                .joined(separator: MacPeekMetrics.separator)
        }

        private func goBack() {
            if store.isAtRoot {
                onClose()
            } else {
                store.send(.backTapped)
            }
        }

        private func step(_ offset: Int) -> KeyPress.Result {
            guard store.entry != nil else { return .ignored }
            store.send(.stepped(offset))
            return .handled
        }
    }

    @MainActor
    enum ArchivePeekText {
        static func detail(_ entry: ArchiveListingEntry, position: String? = nil) -> String {
            guard !entry.isDirectory else { return L10n.FileInfo.navigationTitleFolder }
            return ([entry.fileItem.previewTypeText, entry.size.map(FileSizeFormat.string), position]
                .compactMap(\.self))
                .joined(separator: MacPeekMetrics.separator)
        }
    }

    struct ArchivePeekCrumbs: View {
        let names: [String]
        let onTap: (Int) -> Void

        var body: some View {
            HStack(spacing: .space4) {
                ForEach(Array(names.enumerated()), id: \.offset) { index, name in
                    if index > 0 {
                        IconKit.chevronRight
                            .font(.system(size: .iconXSmall))
                            .foregroundStyle(Color.secondaryText)
                            .accessibilityHidden(true)
                    }
                    if index == names.count - 1 {
                        Text(name)
                            .type(.subtitle2)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Button(name) { onTap(index) }
                            .buttonStyle(.plain)
                            .type(.body2(.regular), style: .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    #Preview("Archive card") {
        ArchivePeekCard(
            store: Store(
                initialState: ArchiveBrowserFeature.State(
                    archive: FileItem(
                        name: "Brand Kit.zip",
                        path: "Files",
                        dateModified: .distantPast,
                        size: 10_200_000,
                        kind: "zip"
                    ),
                    serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")
                )
            ) {
                ArchiveBrowserFeature()
            },
            onExtract: { _ in },
            onClose: {}
        )
        .padding(MacPeekMetrics.margin)
        .frame(width: 960, height: 820)
        .background(Color.macChrome)
    }
#endif
