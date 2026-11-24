#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let chevron: CGFloat = 9
        static let chevronOpenAngle: Double = 90
    }

    struct MacShareLinkField: View {
        let share: Share
        let serverURL: URL
        var showsDirectLink = false
        let onCopied: (String) -> Void

        @State private var isDirectOpen = false
        @State private var pickedChoice = DirectLinkChoice.openInBrowser

        private var directChoices: [DirectLinkChoice] {
            showsDirectLink ? share.directLinkChoices : []
        }

        private var directChoice: DirectLinkChoice? {
            directChoices.contains(pickedChoice) ? pickedChoice : directChoices.first
        }

        var body: some View {
            VStack(alignment: .leading, spacing: .space12) {
                VStack(alignment: .leading, spacing: .space8) {
                    Text(L10n.Shared.link)
                        .type(.caption(.semibold), style: .secondary)
                    MacCopyField(attributed(share.shareLink(serverURL: serverURL)), copyLabel: L10n.Shared.copyLink) {
                        onCopied(share.copyShareLink(serverURL: serverURL))
                    }
                }
                if let directChoice {
                    disclosure
                    if isDirectOpen {
                        direct(directChoice)
                            .transition(.opacity)
                    }
                }
            }
            .padding(.horizontal, .space12)
            .padding(.vertical, .space16)
            .macGroupedRows()
        }

        private var disclosure: some View {
            Button {
                withAnimation(DSMotion.contentReveal) { isDirectOpen.toggle() }
            } label: {
                HStack(spacing: .space4) {
                    IconKit.chevronRight
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.chevron, height: Metrics.chevron)
                        .rotationEffect(.degrees(isDirectOpen ? Metrics.chevronOpenAngle : .zero))
                    Text(share.isDirectory ? L10n.Shared.directZip : L10n.Shared.directDownloadLink)
                        .type(.body3(.semibold))
                }
                .foregroundStyle(Color.accentText)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isDirectOpen ? .isSelected : [])
        }

        private func direct(_ choice: DirectLinkChoice) -> some View {
            VStack(alignment: .leading, spacing: .space12) {
                if directChoices.count > 1 {
                    MacSegmentedPicker(
                        L10n.CreateShare.directLinkMode,
                        options: directChoices,
                        selection: Binding(get: { choice }, set: { pickedChoice = $0 })
                    ) { $0.title }
                }
                MacCopyField(
                    attributed(share.directLink(serverURL: serverURL, mode: choice.mode)),
                    copyLabel: share.isDirectory ? L10n.Shared.copyFolderLink : L10n.Shared.copyFileLink
                ) {
                    onCopied(share.copyDirectLink(serverURL: serverURL, mode: choice.mode))
                }
                Text(share.isDirectory ? L10n.Shared.directZipDetail : L10n.Shared.directHint)
                    .type(.caption(.regular), style: .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func attributed(_ link: String) -> AttributedString {
            var text = AttributedString(link)
            text.foregroundColor = Color.secondaryDS
            if let range = text.range(of: share.shareToken, options: .backwards) {
                text[range].inlinePresentationIntent = .stronglyEmphasized
                text[range].foregroundColor = Color.primaryDS
            }
            return text
        }
    }

    #Preview("Link field") {
        VStack(spacing: .space16) {
            MacShareLinkField(
                share: Share.previewSharedByMe[0],
                serverURL: sharedPreviewServerURL,
                showsDirectLink: true
            ) { _ in }
            MacShareLinkField(share: Share.previewSharedWithMe[0], serverURL: sharedPreviewServerURL) { _ in }
        }
        .padding(MacInspectorMetrics.padding)
        .frame(width: MacInspectorMetrics.width)
        .background(Color.macCard)
    }
#endif
