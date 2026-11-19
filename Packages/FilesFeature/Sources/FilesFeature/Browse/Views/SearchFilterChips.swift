import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowSpacing: CGFloat = .space8
    static let chipHorizontalPadding: CGFloat = .space16
    static let chipVerticalPadding: CGFloat = .space8
    /// The header's side margin, which the row reaches past.
    static let edgeInset: CGFloat = .space16
}

/// Horizontally scrolling "Filter by type" chip row under the search field, over search results or
/// a folder's own items. A leading "All" chip resets the filter; one chip per `FileCategory`
/// actually present (`availableCategories`) toggles independently. An empty selection means "all",
/// so the "All" chip reads selected exactly when no category is picked. Replaces the old
/// focus gated filter button + `SearchFilterSheet`.
struct SearchFilterChips: View {
    let availableCategories: [FileCategory]
    let selectedCategories: Set<FileCategory>
    let onToggle: (FileCategory) -> Void
    let onSelectAll: () -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Constants.rowSpacing) {
                chip(
                    title: L10n.Filter.all,
                    isSelected: selectedCategories.isEmpty,
                    action: onSelectAll
                )
                ForEach(availableCategories, id: \.self) { category in
                    chip(
                        title: category.title,
                        isSelected: selectedCategories.contains(category)
                    ) {
                        onToggle(category)
                    }
                }
            }
        }
        // Runs to the screen edges, starting in line with the header's text.
        .contentMargins(.horizontal, Constants.edgeInset, for: .scrollContent)
        .padding(.horizontal, -Constants.edgeInset)
        .animation(
            DSMotion.pop,
            value: selectedCategories
        )
    }

    private func chip(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .type(.body3(isSelected ? .semibold : .regular))
                .foregroundStyle(isSelected ? Color.primaryInverted : Color.secondaryDS)
                .padding(.horizontal, Constants.chipHorizontalPadding)
                .padding(.vertical, Constants.chipVerticalPadding)
                // A filled pill: the picked chip in the text colour, the rest on the surface.
                .background(
                    Capsule()
                        .fill(isSelected ? Color.primaryDS : Color.backgroundSecondary)
                )
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .hapticFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(AccessibilityIdentifiers.Browse.filterChip)
    }
}

extension FileCategory {
    var title: String {
        switch self {
        case .folder: L10n.Filter.folders
        case .image: L10n.Filter.images
        case .video: L10n.Filter.videos
        case .audio: L10n.Filter.audio
        case .document: L10n.Filter.documents
        case .archive: L10n.Filter.archives
        case .other: L10n.Filter.other
        }
    }

    var icon: Image {
        switch self {
        case .folder: IconKit.folder
        case .image: IconKit.photo
        case .video: IconKit.film
        case .audio: IconKit.music
        case .document: IconKit.document
        case .archive: IconKit.extract
        case .other: IconKit.moreOptions
        }
    }
}

#Preview("No filter") {
    SearchFilterChips(
        availableCategories: [.folder, .image, .video, .document, .other],
        selectedCategories: [],
        onToggle: { _ in },
        onSelectAll: {}
    )
    .padding()
}

#Preview("No filter, dark") {
    SearchFilterChips(
        availableCategories: [.folder, .image, .video, .document],
        selectedCategories: [],
        onToggle: { _ in },
        onSelectAll: {}
    )
    .padding()
    .background(Color.backgroundPrimary)
    .preferredColorScheme(.dark)
}

#Preview("Filtered") {
    SearchFilterChips(
        availableCategories: [.folder, .image, .video, .audio, .document, .archive, .other],
        selectedCategories: [.image, .video],
        onToggle: { _ in },
        onSelectAll: {}
    )
    .padding()
}
