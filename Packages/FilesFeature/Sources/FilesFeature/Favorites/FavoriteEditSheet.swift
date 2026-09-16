import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Metrics {
    static let contentSpacing: CGFloat = .space24
    static let sectionSpacing: CGFloat = .space8
    static let horizontalPadding: CGFloat = .space24
    static let verticalPadding: CGFloat = .space24
    static let iconCell: CGFloat = .size56
    static let iconGlyph: CGFloat = .iconMedium
    static let iconColumnMin: CGFloat = .size56
    static let swatch: CGFloat = .size32
    static let selectionLineWidth: CGFloat = 2.5
    static let swatchIdleBorderWidth: CGFloat = 1
    static let maxHeightFraction: CGFloat = 0.85
}

/// Edit a favorite's name, icon and colour — the iOS counterpart of the web
/// `FavoriteEditDialog.vue`. The favorite's path is fixed and shown read only.
struct FavoriteEditSheet: View {
    @Bindable var store: StoreOf<FavoriteEditFeature>
    let onClose: () -> Void

    private let iconColumns = [GridItem(.adaptive(minimum: Metrics.iconColumnMin), spacing: .space8)]

    private var tint: Color {
        FavoriteColor.resolve(store.colorDraft) ?? .accent
    }

    var body: some View {
        DSDynamicHeightSheet(maxHeightFraction: Metrics.maxHeightFraction) {
            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                DSSheetHeader(
                    icon: FavoriteIcon.symbol(for: store.iconDraft),
                    title: L10n.Favorites.editTitle,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: onClose
                )
                .environment(\.symbolVariants, iconVariant)

                if let error = store.errorMessage {
                    DSErrorCard(error)
                }

                section(L10n.Favorites.editNameLabel, error: nameErrorText) {
                    DSTextField(store.favorite.path, text: $store.nameDraft.sending(\.nameChanged))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                }

                section(L10n.Favorites.editColorLabel) { colorRow }

                section(L10n.Favorites.editIconLabel) {
                    VStack(alignment: .leading, spacing: .space12) {
                        DSSegmentedControl(
                            options: FavoriteEditFeature.IconStyle.allCases,
                            selection: $store.iconStyleDraft.sending(\.iconStyleSelected),
                            label: iconStyleLabel
                        )
                        iconGrid
                    }
                }
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.verticalPadding)
        } footer: {
            DSSheetFooter {
                DSButton(L10n.Favorites.editSave, style: .primary, isLoading: store.isSaving) {
                    store.send(.saveTapped)
                }
                .disabled(!store.isSaveEnabled)
            }
        }
    }

    private var iconVariant: SymbolVariants {
        store.iconStyleDraft == .solid ? .fill : .none
    }

    private var nameErrorText: String? {
        switch store.nameError {
        case .empty: L10n.Favorites.editNameErrorEmpty
        case nil: nil
        }
    }

    private func iconStyleLabel(_ style: FavoriteEditFeature.IconStyle) -> String {
        switch style {
        case .outline: L10n.Favorites.editIconOutline
        case .solid: L10n.Favorites.editIconSolid
        }
    }

    @ViewBuilder
    private func section(
        _ title: String,
        error: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            DSFieldLabel(title)
            content()
            if let error {
                Text(error).type(.body3(.semibold), style: .error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var colorRow: some View {
        HStack(spacing: .space12) {
            swatchButton(fill: defaultSwatchFill, isSelected: store.colorDraft == nil) {
                store.send(.colorSelected(nil))
            }
            .accessibilityLabel(L10n.Favorites.editColorDefault)

            ForEach(FavoriteColor.palette) { swatch in
                swatchButton(
                    fill: AnyShapeStyle(swatch.color),
                    isSelected: FavoriteColor.matches(store.colorDraft, swatch.hex)
                ) {
                    store.send(.colorSelected(swatch.hex))
                }
            }
        }
    }

    private var defaultSwatchFill: AnyShapeStyle {
        AnyShapeStyle(LinearGradient(
            colors: [Color.secondaryDS.opacity(0.5), Color.secondaryDS.opacity(0.2)],
            startPoint: .topLeading, endPoint: .bottomTrailing
        ))
    }

    private func swatchButton(
        fill: AnyShapeStyle,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: .radiusSmall)
                .fill(fill)
                // Selection is an inset `primaryInverted` border on the swatch itself — one
                // colour that reads against every fill in both appearances, matching the icon
                // grid's selected cell. Idle swatches keep the faint hairline.
                .overlay(
                    RoundedRectangle(cornerRadius: .radiusSmall)
                        .strokeBorder(
                            isSelected ? Color.primaryDS : Color.borderPrimary.opacity(0.4),
                            lineWidth: isSelected ? Metrics.selectionLineWidth : Metrics.swatchIdleBorderWidth
                        )
                )
                .frame(width: Metrics.swatch, height: Metrics.swatch)
        }
        .buttonStyle(DSHapticButtonStyle())
    }

    private var iconGrid: some View {
        LazyVGrid(columns: iconColumns, spacing: .space8) {
            ForEach(FavoriteIcon.names, id: \.self) { name in
                Button {
                    store.send(.iconSelected(name))
                } label: {
                    FavoriteIcon.symbol(for: name)
                        .resizable().scaledToFit()
                        .symbolVariant(iconVariant)
                        .foregroundStyle(store.iconDraft == name ? tint : Color.secondaryDS)
                        .frame(width: Metrics.iconGlyph, height: Metrics.iconGlyph)
                        .frame(width: Metrics.iconCell, height: Metrics.iconCell)
                        .background(
                            RoundedRectangle(cornerRadius: .radiusControl)
                                .strokeBorder(tint, lineWidth: store.iconDraft == name ? Metrics.selectionLineWidth : 0)
                        )
                }
                .buttonStyle(DSHapticButtonStyle())
            }
        }
    }
}

@MainActor
private func favoriteEditPreview(
    icon: String = "outline:BriefcaseIcon",
    color: String? = "#009cff",
    _ mutate: @Sendable (inout FavoriteEditFeature.State) -> Void = { _ in }
) -> some View {
    var state = FavoriteEditFeature.State(
        serverURL: URL(string: "https://cloud.example.com")!,
        favorite: Favorite(
            id: "f1", path: "Documents/Projects", label: "Projects",
            icon: icon, color: color, position: 0, createdAt: Date(), updatedAt: Date()
        )
    )
    mutate(&state)
    return Color.clear.sheet(isPresented: .constant(true)) {
        FavoriteEditSheet(store: Store(initialState: state) { FavoriteEditFeature() }, onClose: {})
    }
}

#Preview("Outline") { favoriteEditPreview() }

#Preview("Solid weight") { favoriteEditPreview(icon: "solid:StarIcon", color: "#ff5e5a") }

#Preview("No colour") { favoriteEditPreview(color: nil) }

#Preview("Empty name") { favoriteEditPreview { $0.nameDraft = "" } }

#Preview("Save error") {
    favoriteEditPreview {
        $0.errorMessage = "Couldn't reach the server. Check your connection and try again."
    }
}
