#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct ArchivePeekStage: View {
        let file: ArchiveListingEntry
        let phase: ArchiveBrowserFeature.OpenedEntry.Phase
        let files: [ArchiveListingEntry]
        let onStep: (Int) -> Void
        let onPick: (ArchiveListingEntry) -> Void

        private var index: Int {
            files.firstIndex(of: file) ?? .zero
        }

        var body: some View {
            VStack(spacing: .space16) {
                HStack(spacing: .space16) {
                    MacIconButton(IconKit.back, label: L10n.VersionedFiles.previous) { onStep(-1) }
                        .disabled(index == .zero)
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    MacIconButton(IconKit.chevronRight, label: L10n.VersionedFiles.next) { onStep(1) }
                        .disabled(index >= files.count - 1)
                }
                if files.count > 1 {
                    strip
                }
            }
            .padding(.space24)
            .background(Color.macChrome)
        }

        @ViewBuilder
        private var content: some View {
            switch phase {
            case .loading:
                DSSpinner()
            case let .failed(message):
                FileSummaryView(item: file.fileItem, message: message)
            case let .loaded(url):
                ArchiveEntryBody(item: file.fileItem, fileURL: url)
            }
        }

        private var strip: some View {
            ScrollView(.horizontal) {
                HStack(spacing: .space8) {
                    ForEach(files) { sibling in
                        Button {
                            onPick(sibling)
                        } label: {
                            MacItemTile(kind: sibling.kind, isDirectory: false, size: MacPeekMetrics.iconSize)
                                .padding(.space4)
                                .overlay {
                                    RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                                        .strokeBorder(
                                            sibling == file ? Color.accent : .clear,
                                            lineWidth: .borderWidthFocused
                                        )
                                }
                                .opacity(sibling == file ? 1 : MacPeekMetrics.dimmedOpacity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(sibling.name)
                    }
                }
                .padding(.horizontal, .space4)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
            .defaultScrollAnchor(.center, for: .alignment)
        }
    }

    struct ArchiveEntryBody: View {
        let item: FileItem
        let fileURL: URL

        @State private var text: String?

        private var isText: Bool {
            PreviewKind(item) == .text && item.size <= MacPeekContent.Kind.maxTextBytes
        }

        var body: some View {
            if item.isUnsupportedForPreview || item.isArchive {
                FileSummaryView(item: item, message: nil)
            } else if isText {
                Group {
                    if let text {
                        CodeEditorView(kind: item.kind, text: .constant(text), isEditable: false)
                            .background(
                                Color.macCard,
                                in: RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                            )
                    } else {
                        DSSpinner()
                    }
                }
                .task(id: fileURL) { await loadText() }
            } else {
                QuickLookPreview(url: fileURL)
                    .id(fileURL)
            }
        }

        private func loadText() async {
            let url = fileURL
            let loaded = await Task.detached(priority: .userInitiated) {
                (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) }
            }.value
            guard !Task.isCancelled else { return }
            text = loaded ?? ""
        }
    }

    #Preview("Loading") {
        let file = ArchiveListingEntry(path: "cover.jpg", name: "cover.jpg", isDirectory: false, size: 820_000)
        ArchivePeekStage(file: file, phase: .loading, files: [file], onStep: { _ in }, onPick: { _ in })
            .frame(width: MacPeekMetrics.previewWidth, height: MacPeekMetrics.previewHeight)
    }

    #Preview("Failed") {
        let file = ArchiveListingEntry(path: "Contract.pdf", name: "Contract.pdf", isDirectory: false, size: 640_000)
        let other = ArchiveListingEntry(path: "cover.jpg", name: "cover.jpg", isDirectory: false, size: 820_000)
        ArchivePeekStage(
            file: file,
            phase: .failed(L10n.Archive.entryEncrypted),
            files: [file, other],
            onStep: { _ in },
            onPick: { _ in }
        )
        .frame(width: MacPeekMetrics.previewWidth, height: MacPeekMetrics.previewHeight)
    }
#endif
