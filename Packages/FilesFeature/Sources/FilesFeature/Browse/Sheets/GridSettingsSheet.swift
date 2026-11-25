#if os(iOS)
    import AppStorageKeys
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let contentSpacing: CGFloat = .space24
        static let sectionSpacing: CGFloat = .space8
        static let sizeSpacing: CGFloat = .space12
        static let cardSpacing: CGFloat = .space8
        static let cardPadding: CGFloat = .space12
        static let miniSpacing: CGFloat = .size2
        static let miniRadius: CGFloat = .size2
        static let miniRows = 2
        /// One preview height for every size, so the three cards line up whatever their columns.
        static let miniHeight: CGFloat = .size40
        static let selectedBorderWidth: CGFloat = 2
        static let selectedFillOpacity: Double = .opacityFaint
        static let idleCellOpacity: Double = .opacityDim
        static let horizontalPadding: CGFloat = .space24
        static let verticalPadding: CGFloat = .space24
    }

    /// The toolbar button beside ⋯ that a grid shows: opens `GridSettingsSheet`.
    struct GridSettingsButton: View {
        @State private var isPresented = false

        var body: some View {
            Button {
                isPresented = true
            } label: {
                IconKit.gridOptions
                    .foregroundStyle(Color.primaryDS)
            }
            .buttonStyle(DSPressableButtonStyle())
            .accessibilityLabelWithTooltip(L10n.Grid.settingsButton)
            .accessibilityIdentifier(AccessibilityIdentifiers.Browse.gridSettingsButton)
            .dsSheet(isPresented: $isPresented) {
                GridSettingsSheet { isPresented = false }
            }
        }
    }

    /// How many files every grid shows per row (Browse, Favorites, Offline share it). A device
    /// preference, so the sheet writes it directly.
    struct GridSettingsSheet: View {
        let onDismiss: () -> Void
        @AppStorage(AppStorageKeys.thumbnailSize) private var thumbnailSizeRaw = ThumbnailSize.medium.rawValue

        /// Biggest first, as the tiles read from roomy to dense.
        private static let sizes: [ThumbnailSize] = [.large, .medium, .small]

        private var selectedSize: ThumbnailSize {
            ThumbnailSize(rawValue: thumbnailSizeRaw) ?? .medium
        }

        var body: some View {
            DSDynamicHeightSheet {
                VStack(alignment: .leading, spacing: Constants.contentSpacing) {
                    DSSheetHeader(
                        icon: IconKit.gridOptions,
                        title: L10n.Grid.settingsTitle,
                        closeAccessibilityLabel: L10n.Common.close,
                        onClose: onDismiss
                    )
                    VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
                        DSFieldLabel(L10n.Grid.sizeTitle)
                        HStack(alignment: .top, spacing: Constants.sizeSpacing) {
                            ForEach(Self.sizes) { size in
                                sizeCard(size)
                            }
                        }
                    }
                }
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.vertical, Constants.verticalPadding)
            }
            .hapticFeedback(.selection, trigger: thumbnailSizeRaw)
        }

        private func sizeCard(_ size: ThumbnailSize) -> some View {
            let isSelected = size == selectedSize
            let shape = RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous)
            return Button {
                thumbnailSizeRaw = size.rawValue
            } label: {
                VStack(alignment: .leading, spacing: Constants.cardSpacing) {
                    miniGrid(columns: size.columnCount, isSelected: isSelected)
                    Text(size.title)
                        .type(.body3(.semibold), style: isSelected ? .link : .primaryOnSurface)
                    Text(L10n.Grid.perRow(size.columnCount))
                        .type(.caption(.regular), style: .secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Constants.cardPadding)
                .background(
                    isSelected ? Color.accent.opacity(Constants.selectedFillOpacity) : Color.backgroundSecondary,
                    in: shape
                )
                .overlay {
                    shape.strokeBorder(
                        isSelected ? Color.accent : Color.clear,
                        lineWidth: Constants.selectedBorderWidth
                    )
                }
                .contentShape(shape)
            }
            .buttonStyle(DSPressableButtonStyle())
            .animation(DSMotion.stateFade, value: isSelected)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private func miniGrid(columns: Int, isSelected: Bool) -> some View {
            VStack(spacing: Constants.miniSpacing) {
                ForEach(0 ..< Constants.miniRows, id: \.self) { _ in
                    HStack(spacing: Constants.miniSpacing) {
                        ForEach(0 ..< columns, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: Constants.miniRadius)
                                .fill(isSelected ? Color.accent : Color.secondaryDS.opacity(Constants.idleCellOpacity))
                        }
                    }
                }
            }
            .frame(height: Constants.miniHeight)
            .accessibilityHidden(true)
        }
    }

    #Preview("Sheet") {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                GridSettingsSheet {}
            }
    }

    #Preview("Sheet, dark") {
        Color.clear
            .sheet(isPresented: .constant(true)) {
                GridSettingsSheet {}
            }
            .preferredColorScheme(.dark)
    }

    #Preview("Button") {
        GridSettingsButton()
            .padding(.space16)
    }
#endif
