#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let width: CGFloat = 520
        static let tile: CGFloat = .size56
        static let iconColumns = 9
        static let iconCell: CGFloat = .size44
        static let iconGlyph: CGFloat = .size20
        static let selectedOpacity: Double = 0.18
        static let selectedRing: CGFloat = 1.5
        static let swatch: CGFloat = .size24
        static let swatchRing: CGFloat = .size2
    }

    private enum SelectionID {
        case icon
        case color
    }

    struct MacFavoriteEditForm: View {
        @Bindable var store: StoreOf<FavoriteEditFeature>
        let onClose: () -> Void

        @Namespace private var selection

        var body: some View {
            MacFormSheet(
                title: L10n.Favorites.editTitle,
                confirmTitle: L10n.Favorites.editSave,
                isConfirmEnabled: store.isSaveEnabled,
                isWorking: store.isSaving,
                errorMessage: store.errorMessage,
                width: Metrics.width,
                layout: .stacked,
                onCancel: onClose,
                onConfirm: { store.send(.saveTapped) },
                content: {
                    nameRow
                    palette
                },
                below: { EmptyView() }
            )
        }

        private var nameRow: some View {
            HStack(alignment: .top, spacing: .space12) {
                MacFolderTile(
                    size: Metrics.tile,
                    glyph: FavoriteIcon.symbol(for: store.iconDraft),
                    tint: store.tint
                )
                .symbolVariant(store.iconVariant)
                .contentTransition(.symbolEffect(.replace))
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: .space4) {
                    Text(L10n.Favorites.editNameLabel)
                        .type(.body2(.semibold), style: .secondary)
                    MacTextField(
                        L10n.Favorites.editNameLabel,
                        text: $store.nameDraft.sending(\.nameChanged),
                        prompt: store.favorite.folderName,
                        isInvalid: store.nameErrorText != nil
                    )
                    .autocorrectionDisabled()
                    MacFieldError(message: store.nameErrorText)
                }
            }
        }

        private var palette: some View {
            VStack(spacing: .space12) {
                HStack(spacing: .space12) {
                    sectionTitle(L10n.Favorites.editIconLabel)
                    MacSegmentedPicker(
                        L10n.Favorites.editIconLabel,
                        options: FavoriteEditFeature.IconStyle.allCases,
                        selection: $store.iconStyleDraft.sending(\.iconStyleSelected),
                        label: \.title
                    )
                }
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: .space4),
                        count: Metrics.iconColumns
                    ),
                    spacing: .space4
                ) {
                    ForEach(FavoriteIcon.names, id: \.self) { name in
                        iconCell(name)
                    }
                }
                Rectangle()
                    .fill(Color.macLine)
                    .frame(height: .borderWidthHairline)
                HStack(spacing: .space12) {
                    sectionTitle(L10n.Favorites.editColorLabel)
                    swatches
                }
            }
            .padding(.space16)
            .background(RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous).fill(Color.macField))
            .overlay(RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous).strokeBorder(Color.macLine))
        }

        private func sectionTitle(_ title: String) -> some View {
            Text(title)
                .type(.body2(.semibold), style: .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        private func iconCell(_ name: String) -> some View {
            let isSelected = store.iconDraft == name
            let shape = RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
            return Button { store.send(.iconSelected(name), animation: DSMotion.controlMorph) } label: {
                FavoriteIcon.symbol(for: name)
                    .resizable()
                    .scaledToFit()
                    .symbolVariant(store.iconVariant)
                    .foregroundStyle(isSelected ? store.tint : Color.secondaryDS)
                    .frame(width: Metrics.iconGlyph, height: Metrics.iconGlyph)
                    .frame(maxWidth: .infinity)
                    .frame(height: Metrics.iconCell)
                    .background {
                        if isSelected {
                            shape
                                .fill(store.tint.opacity(Metrics.selectedOpacity))
                                .overlay(shape.strokeBorder(store.tint, lineWidth: Metrics.selectedRing))
                                .matchedGeometryEffect(id: SelectionID.icon, in: selection)
                        }
                    }
                    .contentShape(shape)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private var swatches: some View {
            HStack(spacing: .space8) {
                swatch(Color.accent, isSelected: store.colorDraft == nil) {
                    store.send(.colorSelected(nil), animation: DSMotion.controlMorph)
                }
                .accessibilityLabel(L10n.Favorites.editColorDefault)
                ForEach(FavoriteColor.palette) { option in
                    swatch(option.color, isSelected: FavoriteColor.matches(store.colorDraft, option.hex)) {
                        store.send(.colorSelected(option.hex), animation: DSMotion.controlMorph)
                    }
                    .accessibilityLabel(option.name)
                }
            }
        }

        private func swatch(_ color: Color, isSelected: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Circle()
                    .fill(color)
                    .frame(width: Metrics.swatch, height: Metrics.swatch)
                    .padding(Metrics.swatchRing + .space2)
                    .overlay {
                        if isSelected {
                            Circle()
                                .strokeBorder(Color.primaryDS, lineWidth: Metrics.swatchRing)
                                .matchedGeometryEffect(id: SelectionID.color, in: selection)
                        }
                    }
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }
    }

    #Preview("Outline, blue") { favoriteEditPreview() }

    #Preview("Solid, default colour") { favoriteEditPreview(icon: "solid:StarIcon", color: nil) }

    #Preview("Empty name") { favoriteEditPreview { $0.nameDraft = "" } }
#endif
