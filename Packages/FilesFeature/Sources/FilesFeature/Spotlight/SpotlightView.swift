#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import Localization
    import SwiftUI

    private enum Constants {
        static let panelWidth: CGFloat = 640
        static let resultsMaxHeight: CGFloat = 360
        static let topOffset: CGFloat = 96
        static let scrimOpacity: Double = 0.18
        static let shadowOpacity: Double = 0.28
        static let shadowRadius: CGFloat = 28
        static let shadowOffset: CGFloat = 12
        static let borderOpacity: Double = 0.12
        static let activeOpacity: Double = 0.1
        static let fieldFont = Font.title2
        static let animationDuration: Double = 0.2
        /// The panel's frost is darkened so the field and hits read clearly over any window.
        static let panelDarkTint: Double = 0.5
        static let panelLightTint: Double = 0.1
    }

    /// The Mac search panel: a frosted card floating over a dimmed window, like Spotlight. Only
    /// shows state and emits intent; the search itself is `SpotlightFeature`.
    struct SpotlightView: View {
        @Bindable var store: StoreOf<SpotlightFeature>
        @FocusState private var isFieldFocused: Bool
        @Environment(\.colorScheme) private var colorScheme
        @State private var isShown = false

        var body: some View {
            ZStack(alignment: .top) {
                Color.black.opacity(isShown ? Constants.scrimOpacity : 0)
                    .ignoresSafeArea()
                    .onTapGesture { store.send(.closeRequested) }
                    .accessibilityHidden(true)
                panel
                    .padding(.top, Constants.topOffset)
                    .opacity(isShown ? 1 : 0)
            }
            .onExitCommand { store.send(.closeRequested) }
            .task {
                withAnimation(.easeOut(duration: Constants.animationDuration)) {
                    isShown = true
                }
            }
        }

        private var panelShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: .radiusLarge, style: .continuous)
        }

        private var panel: some View {
            VStack(spacing: 0) {
                searchField
                if hasBody {
                    Divider()
                    resultsBody
                }
            }
            .frame(width: Constants.panelWidth)
            .background(.regularMaterial, in: panelShape)
            .background(
                Color.black.opacity(colorScheme == .dark ? Constants.panelDarkTint : Constants.panelLightTint),
                in: panelShape
            )
            .overlay(
                RoundedRectangle(cornerRadius: .radiusLarge, style: .continuous)
                    .strokeBorder(Color.primaryDS.opacity(Constants.borderOpacity))
            )
            .shadow(
                color: .black.opacity(Constants.shadowOpacity),
                radius: Constants.shadowRadius,
                y: Constants.shadowOffset
            )
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }

        private var searchField: some View {
            HStack(spacing: .space12) {
                if store.phase == .loading {
                    ProgressView().controlSize(.small)
                        .frame(width: .iconMedium, height: .iconMedium)
                } else {
                    IconKit.search
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.secondaryDS)
                        .frame(width: .iconMedium, height: .iconMedium)
                        .accessibilityHidden(true)
                }
                TextField(L10n.Spotlight.placeholder, text: $store.query.sending(\.queryChanged))
                    .textFieldStyle(.plain)
                    .tint(Color.accent)
                    .font(Constants.fieldFont)
                    .focused($isFieldFocused)
                    .onSubmit { store.send(.submitted) }
                    .onKeyPress(.downArrow) {
                        store.send(.selectionMoved(.down))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        store.send(.selectionMoved(.up))
                        return .handled
                    }
            }
            .padding(.horizontal, .space16)
            .padding(.vertical, .space12)
            // Focus lands once the field is in the window; setting it during the first layout is dropped.
            .task {
                await Task.yield()
                isFieldFocused = true
            }
        }

        private var hasBody: Bool {
            !store.results.isEmpty || statusText != nil || store.canShowMore
        }

        /// What the panel says while there is nothing to list, or after the list.
        private var statusText: String? {
            if store.isTooShort {
                return L10n.Browse.searchTooShort(FilesClient.minimumSearchTermLength)
            }
            switch store.phase {
            case .idle: return nil
            case .loading: return store.results.isEmpty ? L10n.Common.loading : nil
            case let .failed(message): return message
            case .loaded:
                switch store.shortfall {
                case .stoppedEarly: return L10n.Browse.searchStoppedEarly
                case let .firstOnly(count): return L10n.Browse.searchFirstOnly(count)
                case nil: return store.results.isEmpty ? L10n.Browse.searchNoMatchesInFolder(store.query) : nil
                }
            }
        }

        private var resultsBody: some View {
            VStack(spacing: 0) {
                if !store.results.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(store.results.enumerated()), id: \.element.id) { index, result in
                                    SpotlightResultRow(
                                        result: result,
                                        isActive: store.activeIndex == index,
                                        onHover: { store.send(.highlighted($0 ? index : nil)) },
                                        onOpen: { store.send(.resultTapped(result)) }
                                    )
                                    .id(index)
                                }
                            }
                            .padding(.space8)
                        }
                        .frame(maxHeight: Constants.resultsMaxHeight)
                        .onChange(of: store.activeIndex) { _, index in
                            guard let index else { return }
                            withAnimation(.easeOut(duration: Constants.animationDuration)) {
                                proxy.scrollTo(index)
                            }
                        }
                    }
                }
                if let statusText {
                    Text(statusText)
                        .type(.body3(.regular), style: .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, .space16)
                        .padding(.vertical, .space12)
                }
                if store.canShowMore {
                    Button(L10n.Browse.searchShowMore) { store.send(.showMoreTapped) }
                        .buttonStyle(.link)
                        .padding(.bottom, .space12)
                }
            }
        }
    }

    private struct SpotlightResultRow: View {
        let result: SearchResultItem
        let isActive: Bool
        let onHover: (Bool) -> Void
        let onOpen: () -> Void

        var body: some View {
            Button(action: onOpen) {
                SearchResultRow(result: result)
                    .padding(.horizontal, .space8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                            .fill(isActive ? Color.primaryDS.opacity(Constants.activeOpacity) : .clear)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover(perform: onHover)
            .accessibilityAddTraits(isActive ? .isSelected : [])
        }
    }

    private enum PreviewFixture {
        static let serverURL = URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/")

        static func store(
            query: String,
            phase: DataPhase,
            results: [SearchResultItem] = [],
            shortfall: SearchShortfall? = nil
        ) -> StoreOf<SpotlightFeature> {
            var state = SpotlightFeature.State(serverURL: serverURL, basePath: "")
            state.query = query
            state.phase = phase
            state.results = IdentifiedArray(results, uniquingIDsWith: { first, _ in first })
            state.shortfall = shortfall
            return Store(initialState: state) { SpotlightFeature() }
        }

        static let hits = [
            SearchResultItem(name: "Budgets", path: "", kind: SearchResultItem.directoryKind, isNameMatch: true),
            SearchResultItem(
                name: "budget.xlsx",
                path: "Documents",
                kind: SearchResultItem.fileKind,
                isNameMatch: true
            ),
            SearchResultItem(
                name: "notes.md", path: "Documents", kind: SearchResultItem.fileKind,
                matchLine: "budget for the trip", matchLineNumber: 12, isContentMatch: true
            ),
        ]
    }

    #Preview("Empty") {
        SpotlightView(store: PreviewFixture.store(query: "", phase: .idle)).frame(width: 800, height: 400)
    }

    #Preview("Too short") {
        SpotlightView(store: PreviewFixture.store(query: "bu", phase: .idle)).frame(width: 800, height: 400)
    }

    #Preview("Loading") {
        SpotlightView(store: PreviewFixture.store(query: "budget", phase: .loading)).frame(width: 800, height: 400)
    }

    #Preview("Results") {
        SpotlightView(store: PreviewFixture.store(query: "budget", phase: .loaded, results: PreviewFixture.hits))
            .frame(width: 800, height: 500)
    }

    #Preview("Results, first only") {
        SpotlightView(store: PreviewFixture.store(
            query: "budget",
            phase: .loaded,
            results: PreviewFixture.hits,
            shortfall: .firstOnly(count: 100)
        ))
        .frame(width: 800, height: 500)
    }

    #Preview("No matches") {
        SpotlightView(store: PreviewFixture.store(query: "zzzz", phase: .loaded)).frame(width: 800, height: 400)
    }

    #Preview("Failed") {
        SpotlightView(store: PreviewFixture.store(query: "budget", phase: .failed(L10n.Browse.searchFailed)))
            .frame(width: 800, height: 400)
    }
#endif
