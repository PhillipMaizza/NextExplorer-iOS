#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// Finder's search bar above the results: which kinds of file to show.
    /// It lives in the window rather than in the toolbar's search field, so typing never loses
    /// the field's focus.
    struct MacSearchScopeBar: View {
        let availableCategories: [FileCategory]
        let selectedCategories: Set<FileCategory>
        let onToggle: (FileCategory) -> Void
        let onShowAll: () -> Void

        var body: some View {
            HStack(spacing: .space12) {
                Spacer()
                if !availableCategories.isEmpty {
                    kindMenu
                }
            }
            .padding(.horizontal, .space12)
            .padding(.vertical, .space8)
        }

        private var kindMenu: some View {
            Menu {
                Toggle(isOn: Binding(get: { selectedCategories.isEmpty }, set: { _ in onShowAll() })) {
                    Text(L10n.Filter.all)
                }
                Divider()
                ForEach(availableCategories, id: \.self) { category in
                    Toggle(isOn: Binding(
                        get: { selectedCategories.contains(category) },
                        set: { _ in onToggle(category) }
                    )) {
                        Label { Text(category.title) } icon: { category.icon }
                    }
                }
            } label: {
                Label {
                    Text(L10n.Sort.kind)
                } icon: {
                    selectedCategories.isEmpty ? IconKit.filter : IconKit.filterFill
                }
            }
            .menuStyle(.button)
            .labelStyle(.titleAndIcon)
            .fixedSize()
            // The filled glyph alone says a filter is on; VoiceOver hears which kinds.
            .accessibilityValue(selectedCategories.isEmpty
                ? L10n.Filter.all
                : availableCategories.filter(selectedCategories.contains).map(\.title).formatted(.list(type: .and)))
        }
    }

    #Preview("Kinds") {
        MacSearchScopeBar(
            availableCategories: [.folder, .image, .document],
            selectedCategories: [.image],
            onToggle: { _ in },
            onShowAll: {}
        )
        .previewCanvasWidth(.sheet)
    }
#endif
