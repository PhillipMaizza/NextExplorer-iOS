import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let contentSpacing: CGFloat = .space24
    static let rowSpacing: CGFloat = .space12
    static let rowVerticalPadding: CGFloat = .space16
    static let horizontalPadding: CGFloat = .space24
    static let topPadding: CGFloat = .space24
    static let bottomPadding: CGFloat = .space24
    static let rowIconSize: CGFloat = .iconSmall
    static let checkSize: CGFloat = .iconSmall
    static let selectionAnimationDuration: Double = 0.2
    static let fullOpacity: Double = 1.0
    static let zeroOpacity: Double = 0.0
}

/// Multi-select "Filter by type" sheet for search results, styled to match `SortSheet`. Lists an
/// "All Types" reset row plus one row per category actually present in the results
/// (`availableCategories`), each toggling independently. An empty selection means "all".
struct SearchFilterSheet: View {
    let availableCategories: [FileCategory]
    let selectedCategories: Set<FileCategory>
    let onToggle: (FileCategory) -> Void
    let onSelectAll: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        DSDynamicHeightSheet {
            content
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            DSSheetHeader(
                icon: IconKit.filter,
                title: L10n.Filter.sheetTitle,
                closeAccessibilityLabel: L10n.Common.close,
                onClose: onDismiss
            )

            VStack(spacing: 0) {
                row(icon: IconKit.selectAll, title: L10n.Filter.all, isChecked: selectedCategories.isEmpty, action: onSelectAll)
                ForEach(availableCategories, id: \.self) { category in
                    row(icon: category.icon, title: category.title, isChecked: selectedCategories.contains(category)) {
                        onToggle(category)
                    }
                }
            }
            .dsCard()
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.topPadding)
        .padding(.bottom, Constants.bottomPadding)
    }

    private func row(icon: Image, title: String, isChecked: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Constants.rowSpacing) {
                icon
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
                Text(title)
                    .type(.body1(isChecked ? .semibold : .regular), style: .primary(for: .label))
                Spacer()
                ZStack {
                    IconKit.radioUnselected
                        .resizable()
                        .foregroundStyle(Color.secondaryDS)
                        .opacity(isChecked ? Constants.zeroOpacity : Constants.fullOpacity)
                    IconKit.checkmarkCircleFill
                        .resizable()
                        .foregroundStyle(Color.accent)
                        .opacity(isChecked ? Constants.fullOpacity : Constants.zeroOpacity)
                }
                .frame(width: Constants.checkSize, height: Constants.checkSize)
            }
            .padding(.vertical, Constants.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSHapticButtonStyle())
        .animation(.easeInOut(duration: Constants.selectionAnimationDuration), value: isChecked)
        .hapticFeedback(.selection, trigger: isChecked)
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

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            SearchFilterSheet(
                availableCategories: [.folder, .image, .video, .document, .other],
                selectedCategories: [.image, .video],
                onToggle: { _ in },
                onSelectAll: {},
                onDismiss: {}
            )
        }
}
