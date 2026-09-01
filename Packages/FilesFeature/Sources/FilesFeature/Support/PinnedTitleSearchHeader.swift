import DesignSystem
import Localization
import SwiftUI

/// A large title and an always-visible search field pinned ABOVE the scrolling list, instead of
/// in the navigation bar. A system large title only stays large while the scroll offset is 0 and
/// collapses to inline the instant the content settles below an always-on `.searchable` drawer
/// (or a fresh scroll container lands its offset there on load). Rendering the title and search
/// as ordinary pinned content sidesteps that entirely: the title never collapses and the search
/// field never scrolls away.
///
/// The host keeps its navigation bar for the back button and toolbar actions, but with the
/// system title hidden (`.navigationBarTitleDisplayMode(.inline)` + no title text).
struct PinnedTitleSearchHeader<Accessory: View>: View {
    let title: String
    @Binding var searchText: String
    var prompt: String = L10n.Common.search
    /// Rendered below the search field, e.g. a search-scope segmented control while searching.
    @ViewBuilder var accessory: () -> Accessory

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: .space12) {
            Text(title)
                .type(.headline2, style: .primary(for: .label))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            searchField
            accessory()
        }
        .padding(.horizontal, .space16)
        .padding(.top, .space8)
        .padding(.bottom, .space12)
        // Fades from the screen's top gradient color to clear so the pinned header blends into
        // the `backgroundGradient()` behind it instead of sitting on a hard opaque band.
        .background(
            LinearGradient(
                colors: [Color.backgroundGradientTop, Color.backgroundGradientTop.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
        )
    }

    private var searchField: some View {
        HStack(spacing: .space8) {
            IconKit.search
                .foregroundStyle(Color.secondaryDS)
            TextField(
                text: $searchText,
                prompt: Text(prompt).foregroundColor(Color.secondaryDS)
            ) { EmptyView() }
                .focused($isFocused)
                .type(.body1(.regular))
                .tint(Color.accent)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .submitLabel(.search)
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    IconKit.closeCircle.foregroundStyle(Color.secondaryDS)
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: searchText.isEmpty)
        .roundedFieldStyle()
    }
}

extension PinnedTitleSearchHeader where Accessory == EmptyView {
    init(title: String, searchText: Binding<String>, prompt: String = L10n.Common.search) {
        self.init(title: title, searchText: searchText, prompt: prompt) { EmptyView() }
    }
}
