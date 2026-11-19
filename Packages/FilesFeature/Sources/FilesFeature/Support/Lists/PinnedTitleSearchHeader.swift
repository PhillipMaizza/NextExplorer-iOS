import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    /// Height of the fade tail under the header.
    static let fadeHeight: CGFloat = .space8
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
    /// The selection count shown in place of `title` while selecting (`nil` otherwise). It swaps in
    /// and out with the selection circles, in the same step and motion, not when select mode flips.
    var selectionTitle: String?
    @Binding var searchText: String
    var prompt: String = L10n.Common.search
    /// Extra padding above the title. A screen whose nav bar carries no toolbar actions (e.g.
    /// Settings) sits higher than one that does; pass the actions' height here so every tab's
    /// title lines up.
    var extraTopPadding: CGFloat = 0
    /// Whether to render the search field. A screen that only needs the pinned large title
    /// without filtering (Settings) passes `false`.
    var showsSearchField: Bool = true
    /// Whether the short fade below the header melts into scrolling content. A Mac table keeps
    /// its column headers pinned right below, where the fade would only tint them.
    var shouldFadeIntoContent: Bool = true
    /// A search for the typed text is waiting or running: the field's magnifier turns into a
    /// spinner (a thin bar under the header on the Mac, whose field is in the toolbar), so a list
    /// already on screen still says a newer answer is coming.
    var isSearchPending: Bool = false
    /// Rendered below the search field, e.g. a search-scope segmented control plus type filter
    /// chips while searching.
    @ViewBuilder var accessory: () -> Accessory

    @FocusState private var isFocused: Bool
    #if os(macOS)
        @Environment(\.openSpotlight) private var openSpotlight
    #endif
    #if os(iOS)
        @Shared(.inMemory(SearchFocusRequest.key)) private var searchFocusRequests = 0
        @State private var isOnScreen = false
    #endif
    @Environment(\.selectionIndicatorsShown) private var selectionIndicatorsShown

    #if os(iOS)
        /// The selection count is up on the screen on show: the moment slide to select can be tried.
        private var showsSlideTip: Bool {
            isOnScreen && selectionTitle != nil && (selectionIndicatorsShown ?? true)
        }
    #endif

    private var shownTitle: String {
        guard let selectionTitle, selectionIndicatorsShown ?? true else { return title }
        return selectionTitle
    }

    var body: some View {
        #if os(macOS)
            // Like Finder, the Mac names the folder in the window title (`windowTitle`), so the
            // content keeps only the accessory, if any, and the search lives in the toolbar.
            VStack(spacing: 0) {
                accessory()
            }
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) {
                if isSearchPending {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .tint(Color.accent)
                        .accessibilityLabel(L10n.Common.loading)
                        .allowsHitTesting(false)
                }
            }
            // The window's toolbar search button reads this, like ⌘F: both open the search panel.
            .focusedSceneValue(
                \.focusSearchField,
                showsSearchField ? FocusSearchAction { openSpotlight?() } : nil
            )
        #else
            header
                .onAppear { isOnScreen = true }
                .onDisappear { isOnScreen = false }
                // ⌘F from a keyboard focuses the field of the screen on show.
                .onChange(of: searchFocusRequests) {
                    if isOnScreen, showsSearchField {
                        isFocused = true
                    }
                }
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: .space12) {
            Text(shownTitle)
                .type(.headline2, style: .primaryOnSurface)
                .contentTransition(.interpolate)
                .animation(DSMotion.selectModeStep, value: shownTitle)
                .lineLimit(1)
            #if os(iOS)
                .popoverTip(showsSlideTip ? SlideToSelectTip() : nil, arrowEdge: .top)
                .tipImageStyle(Color.accent)
            #endif
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            if showsSearchField {
                searchField
            }
            accessory()
        }
        .padding(.horizontal, .space16)
        .padding(.top, .space8 + extraTopPadding)
        .padding(.bottom, .space4)
        // Solid top color behind the title/search (matches the `backgroundGradient()` top stop,
        // so it reads seamless) so scrolled rows never bleed through the header. A short fade
        // tail sits just below the header edge to melt into the list gradient instead of ending
        // on a hard band. The tail's height is reserved as bottom padding, so at rest the content
        // starts below the fade and only rows scrolled up pass under it.
        .background(Color.backgroundGradientTop.ignoresSafeArea(edges: .top))
        .background(alignment: .bottom) {
            if shouldFadeIntoContent {
                LinearGradient(
                    colors: [Color.backgroundGradientTop, Color.backgroundGradientTop.opacity(0)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: Constants.fadeHeight)
                .offset(y: Constants.fadeHeight)
                .allowsHitTesting(false)
            }
        }
        .padding(.bottom, shouldFadeIntoContent ? Constants.fadeHeight : 0)
    }

    private var searchField: some View {
        HStack(spacing: .space8) {
            // The magnifier keeps its slot while hidden, so the spinner swaps in without moving
            // the text.
            IconKit.search
                .foregroundStyle(Color.secondaryDS)
                .opacity(isSearchPending ? 0 : 1)
                .accessibilityHidden(true)
                .overlay {
                    if isSearchPending {
                        DSSpinner(size: .small)
                    }
                }
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
                .accessibilityIdentifier(AccessibilityIdentifiers.Search.field)
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
        .animation(DSMotion.quickFade, value: searchText.isEmpty)
        .animation(DSMotion.quickFade, value: isSearchPending)
        .roundedFieldStyle(isFocused: isFocused, bordered: false, cornerRadius: .radiusSearchField)
    }
}

extension PinnedTitleSearchHeader where Accessory == EmptyView {
    init(
        title: String,
        selectionTitle: String? = nil,
        searchText: Binding<String>,
        prompt: String = L10n.Common.search,
        extraTopPadding: CGFloat = 0,
        showsSearchField: Bool = true,
        shouldFadeIntoContent: Bool = true,
        isSearchPending: Bool = false
    ) {
        self.init(
            title: title,
            selectionTitle: selectionTitle,
            searchText: searchText,
            prompt: prompt,
            extraTopPadding: extraTopPadding,
            showsSearchField: showsSearchField,
            shouldFadeIntoContent: shouldFadeIntoContent,
            isSearchPending: isSearchPending
        ) { EmptyView() }
    }
}

#if os(macOS)
    /// The Mac toolbar's search: a magnifier opening the panel, shown while the screen has a search.
    struct MacSearchButton: View {
        let action: FocusSearchAction

        var body: some View {
            Button { action() } label: {
                Label { Text(L10n.Common.search) } icon: { IconKit.search }
            }
            .help(L10n.Common.search)
            .accessibilityIdentifier(AccessibilityIdentifiers.Search.field)
        }
    }

    /// Opens the Mac search panel; set once on the main window so every screen can reach it.
    struct OpenSpotlightAction {
        let perform: () -> Void

        func callAsFunction() {
            perform()
        }
    }

    extension EnvironmentValues {
        @Entry var openSpotlight: OpenSpotlightAction?
    }

    /// Focuses the visible screen's search field; published by `PinnedTitleSearchHeader`.
    public struct FocusSearchAction {
        /// False when the screen draws its own search field in the toolbar.
        var showsToolbarButton = true
        let perform: () -> Void

        public func callAsFunction() {
            perform()
        }
    }

    public extension FocusedValues {
        @Entry var focusSearchField: FocusSearchAction?
    }
#endif

#if os(iOS)
    /// ⌘F on an iPad keyboard: the screen on show focuses its search field.
    public enum SearchFocusRequest {
        static let key = "searchFocusRequest"

        @MainActor
        public static func post() {
            @Shared(.inMemory(key)) var requests = 0
            $requests.withLock { $0 += 1 }
        }
    }
#endif

#Preview("Empty") {
    PinnedTitleSearchHeader(title: "Files", searchText: .constant(""))
        .previewCanvasWidth(.sheet)
}

#Preview("Typed") {
    PinnedTitleSearchHeader(title: "Files", searchText: .constant("report"))
        .previewCanvasWidth(.sheet)
}

#Preview("Search pending") {
    PinnedTitleSearchHeader(title: "Files", searchText: .constant("report"), isSearchPending: true)
        .previewCanvasWidth(.sheet)
}
