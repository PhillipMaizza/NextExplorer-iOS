import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    /// Cross fade for the clear button appearing with text.
    static let fieldAnimationDuration: Double = 0.15
}

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
    /// Extra padding above the title. A screen whose nav bar carries no toolbar actions (e.g.
    /// Settings) sits higher than one that does; pass the actions' height here so every tab's
    /// title lines up.
    var extraTopPadding: CGFloat = 0
    /// Rendered below the search field, e.g. a search-scope segmented control plus type filter
    /// chips while searching.
    @ViewBuilder var accessory: () -> Accessory

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: .space12) {
            Text(title)
                .type(.headline2, style: .primary(for: .label))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            searchField
            accessory()
        }
        .padding(.horizontal, .space16)
        .padding(.top, .space8 + extraTopPadding)
        .padding(.bottom, .space12)
        // Solid top color behind the title/search (matches the `backgroundGradient()` top stop,
        // so it reads seamless) so scrolled rows never bleed through the header. A short fade
        // tail sits just below the header edge to melt into the list gradient instead of ending
        // on a hard band.
        .background(Color.backgroundGradientTop.ignoresSafeArea(edges: .top))
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [Color.backgroundGradientTop, Color.backgroundGradientTop.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: .space16)
            .offset(y: .space16)
        }
    }

    private var searchField: some View {
        HStack(spacing: .space8) {
            IconKit.search
                .foregroundStyle(Color.secondaryDS)
                .accessibilityHidden(true)
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
            // Trailing clear (x) button appears whenever there's text. The type filter now lives
            // in chips below the field (Browse search), so it no longer contends for this slot.
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    IconKit.closeCircle
                        .foregroundStyle(Color.secondaryDS)
                        .frame(minWidth: .size44, minHeight: .size44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Common.clear)
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: Constants.fieldAnimationDuration), value: searchText.isEmpty)
        .roundedFieldStyle(isFocused: isFocused)
    }
}

extension PinnedTitleSearchHeader where Accessory == EmptyView {
    init(
        title: String,
        searchText: Binding<String>,
        prompt: String = L10n.Common.search,
        extraTopPadding: CGFloat = 0
    ) {
        self.init(title: title, searchText: searchText, prompt: prompt, extraTopPadding: extraTopPadding) { EmptyView() }
    }
}
