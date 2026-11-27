#if os(iOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let contentSpacing: CGFloat = .space24
        static let sectionSpacing: CGFloat = .space8
        static let rowSpacing: CGFloat = .space12
        static let rowVerticalPadding: CGFloat = .space16
        static let padding: CGFloat = .space24
        static let radioSize: CGFloat = .iconSmall
    }

    struct BrowseDownloadChoiceSheet: View {
        let count: Int
        let archiveName: String
        let onSave: (BrowseFeature.BulkDownloadChoice, DeviceSaveDestination) -> Void
        let onCancel: () -> Void

        @State private var choice = BrowseFeature.BulkDownloadChoice.oneArchive

        var body: some View {
            DSDynamicHeightSheet {
                VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                    DSSheetHeader(
                        icon: IconKit.menuDownload,
                        title: L10n.Browse.downloadAsTitle(count),
                        closeAccessibilityLabel: L10n.Common.cancel,
                        onClose: onCancel
                    )
                    VStack(spacing: 0) {
                        radioRow(.oneArchive, title: L10n.Browse.downloadOneArchive, subtitle: archiveName)
                        radioRow(
                            .separateFiles,
                            title: L10n.Browse.downloadSeparateFiles,
                            subtitle: L10n.Browse.downloadSeparateFilesHint
                        )
                    }
                    .dsCard()
                    VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                        DSFieldLabel(L10n.Browse.downloadSaveTo)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            DSNavigationRow(
                                title: L10n.Browse.downloadToFilesApp,
                                icon: IconKit.folder,
                                accessory: .none
                            ) {
                                onSave(choice, .files)
                            }
                            DSNavigationRow(
                                title: L10n.Browse.downloadToShareSheet,
                                icon: IconKit.share,
                                accessory: .none
                            ) {
                                onSave(choice, .share)
                            }
                        }
                        .dsCard()
                    }
                }
                .padding(Metrics.padding)
            }
        }

        private func radioRow(
            _ option: BrowseFeature.BulkDownloadChoice,
            title: String,
            subtitle: String
        ) -> some View {
            let isSelected = option == choice
            return Button {
                choice = option
            } label: {
                HStack(spacing: Metrics.rowSpacing) {
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(title)
                            .type(.body1(isSelected ? .semibold : .regular), style: .primaryOnSurface)
                        Text(subtitle)
                            .type(.body3(.regular), style: .secondary)
                    }
                    Spacer()
                    (isSelected ? IconKit.radioSelected : IconKit.radioUnselected)
                        .resizable()
                        .foregroundStyle(isSelected ? Color.accent : Color.secondaryDS)
                        .frame(width: Metrics.radioSize, height: Metrics.radioSize)
                }
                .padding(.vertical, Metrics.rowVerticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableButtonStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .animation(DSMotion.stateFade, value: isSelected)
            .hapticFeedback(.selection, trigger: isSelected)
        }
    }

    #Preview {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                BrowseDownloadChoiceSheet(
                    count: 5,
                    archiveName: "Projects.zip",
                    onSave: { _, _ in },
                    onCancel: {}
                )
            }
    }
#endif
