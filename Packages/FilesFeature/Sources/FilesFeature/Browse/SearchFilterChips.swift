import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowSpacing: CGFloat = .space8
    static let chipSpacing: CGFloat = .space8
    static let chipHorizontalPadding: CGFloat = .space12
    static let chipVerticalPadding: CGFloat = .space8
    static let iconSize: CGFloat = .iconXSmall
    static let selectionSpringResponse: Double = 0.3
    static let selectionSpringDamping: Double = 0.85
}

/// Horizontally scrolling "Filter by type" chip row shown below the search scope control while
/// searching. A leading "All" chip resets the filter; one chip per `FileCategory` actually present
/// in the results (`availableCategories`) toggles independently. An empty selection means "all",
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
                chip(icon: IconKit.selectAll, title: L10n.Filter.all, isSelected: selectedCategories.isEmpty, action: onSelectAll)
                ForEach(availableCategories, id: \.self) { category in
                    chip(icon: category.icon, title: category.title, isSelected: selectedCategories.contains(category)) {
                        onToggle(category)
                    }
                }
            }
        }
        .animation(.spring(response: Constants.selectionSpringResponse, dampingFraction: Constants.selectionSpringDamping), value: selectedCategories)
    }

    private func chip(icon: Image, title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Constants.chipSpacing) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.iconSize, height: Constants.iconSize)
                Text(title)
                    .type(.body2(isSelected ? .semibold : .regular))
            }
            .foregroundStyle(isSelected ? Color.accentText : Color.secondaryDS)
            .padding(.horizontal, Constants.chipHorizontalPadding)
            .padding(.vertical, Constants.chipVerticalPadding)
            // Same `backgroundSecondary` track as the scope segmented control, but selection reads
            // as an accent outline instead of a filled pill, so the two rows never look alike.
            .background(
                RoundedRectangle(cornerRadius: .radiusFull)
                    .fill(Color.backgroundSecondary)
            )
            .overlay(
                RoundedRectangle(cornerRadius: .radiusFull)
                    .strokeBorder(isSelected ? Color.accent : Color.clear, lineWidth: .borderWidthFocused)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .hapticFeedback(.selection, trigger: isSelected)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
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

#Preview("Filtered") {
    SearchFilterChips(
        availableCategories: [.folder, .image, .video, .audio, .document, .archive, .other],
        selectedCategories: [.image, .video],
        onToggle: { _ in },
        onSelectAll: {}
    )
    .padding()
}
