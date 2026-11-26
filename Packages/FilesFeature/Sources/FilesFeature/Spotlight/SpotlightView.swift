#if os(macOS)
    import AppKit
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import FilesClient
    import FolderPickerFeature
    import Localization
    import SwiftUI

    private enum Constants {
        static let panelWidth: CGFloat = 720
        static let panelRadius: CGFloat = .radiusLarge
        static let rowRadius: CGFloat = .radiusControl
        static let resultsMaxHeight: CGFloat = 400
        static let topOffset: CGFloat = 76
        static let fieldHeight: CGFloat = 62
        static let scrimDarkOpacity: Double = 0.55
        static let scrimLightOpacity: Double = 0.28
        static let shadowOpacity: Double = 0.35
        static let shadowRadius: CGFloat = 45
        static let shadowOffset: CGFloat = 30
        static let zoomScale: CGFloat = 0.94
    }

    /// The Mac search panel: a frosted card floating over a dimmed window, like Spotlight. Only
    /// shows state and emits intent; the search itself is `SpotlightFeature`.
    struct SpotlightView: View {
        @Bindable var store: StoreOf<SpotlightFeature>
        @FocusState private var isFieldFocused: Bool
        /// Where the pointer was at the last arrow key press.
        @State private var keyboardMouseLocation: CGPoint?
        @State private var resultsHeight: CGFloat = .zero
        @Environment(\.colorScheme) private var colorScheme

        var body: some View {
            ZStack(alignment: .top) {
                Color.black.opacity(colorScheme == .dark ? Constants.scrimDarkOpacity : Constants.scrimLightOpacity)
                    .ignoresSafeArea()
                    .onTapGesture { store.send(.closeRequested) }
                    .accessibilityHidden(true)
                    .transition(.opacity)
                // Zooms in from just under full size, and back out the same way on the way out,
                // like the system Spotlight.
                panel
                    .padding(.top, Constants.topOffset)
                    .transition(.scale(scale: Constants.zoomScale, anchor: .top).combined(with: .opacity))
            }
            .onExitCommand { store.send(.closeRequested) }
        }

        private var panelShape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Constants.panelRadius, style: .continuous)
        }

        private var panel: some View {
            VStack(spacing: 0) {
                searchField
                if hasBody {
                    separator
                    resultsBody
                }
                separator
                footer
            }
            .frame(width: Constants.panelWidth)
            .background(Color.macCard, in: panelShape)
            .clipShape(panelShape)
            .overlay(panelShape.strokeBorder(Color.macLine))
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
                    IconKit.macToolbarSearch
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.secondaryDS)
                        .frame(width: .iconMedium, height: .iconMedium)
                        .accessibilityHidden(true)
                }
                TextField(L10n.Spotlight.placeholder, text: $store.query.sending(\.queryChanged))
                    .textFieldStyle(.plain)
                    .tint(Color.accent)
                    .type(.subtitle1)
                    .focused($isFieldFocused)
                    .accessibilityIdentifier(AccessibilityIdentifiers.Search.spotlightField)
                    .onSubmit { store.send(.submitted) }
                    .onKeyPress(.downArrow) {
                        keyboardMouseLocation = NSEvent.mouseLocation
                        store.send(.selectionMoved(.down))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        keyboardMouseLocation = NSEvent.mouseLocation
                        store.send(.selectionMoved(.up))
                        return .handled
                    }
            }
            .padding(.horizontal, .space24)
            .macMinHeight(points: Constants.fieldHeight)
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
                return SearchHint.tooShort
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

        private var separator: some View {
            Rectangle()
                .fill(Color.macLine)
                .frame(height: .borderWidthHairline)
        }

        private var footer: some View {
            HStack(spacing: .space16) {
                footerHint(MacShortcutHint.arrows, L10n.Spotlight.hintMove)
                footerHint(MacShortcutHint.enter, L10n.Spotlight.hintOpen)
                Spacer(minLength: .zero)
                Button { store.send(.closeRequested) } label: {
                    footerHint(MacShortcutHint.escape, L10n.Common.close)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, .space24)
            .padding(.vertical, .space8)
        }

        private func footerHint(_ key: String, _ title: String) -> some View {
            HStack(spacing: .space4) {
                MacKeyHint(key)
                Text(title).type(.caption(.regular), style: .secondary)
            }
            .accessibilityElement(children: .combine)
        }

        private func sectionHeader(_ title: String) -> some View {
            Text(title)
                .type(.body3(.semibold), style: .secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, .space12)
                .padding(.top, .space12)
                .padding(.bottom, .space4)
                .accessibilityAddTraits(.isHeader)
        }

        private func rows(_ hits: [SearchResultItem], startingAt offset: Int) -> some View {
            ForEach(Array(hits.enumerated()), id: \.element.id) { position, result in
                let index = offset + position
                SpotlightResultRow(
                    result: result,
                    serverURL: store.serverURL,
                    shouldShowThumbnails: store.preferences.shouldShowThumbnails,
                    isActive: (store.activeIndex ?? 0) == index,
                    onHover: { isInside in
                        // Entering a row highlights it; leaving never clears, since the exit of the row
                        // left can land after the enter of the next and drop the highlight. A pointer
                        // resting still while the arrow keys scroll rows under it must not take it back.
                        guard isInside, NSEvent.mouseLocation != keyboardMouseLocation else { return }
                        store.send(.highlighted(index))
                    },
                    onOpen: { store.send(.resultTapped(result)) }
                )
                .id(index)
            }
        }

        private var resultsBody: some View {
            VStack(spacing: 0) {
                if !store.results.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                let sections = store.sections
                                if sections.isSplit {
                                    sectionHeader(L10n.Search.onDevice)
                                }
                                rows(sections.onDevice, startingAt: 0)
                                if sections.isSplit {
                                    sectionHeader(L10n.Search.remote)
                                }
                                rows(sections.remote, startingAt: sections.onDevice.count)
                            }
                            .padding(.horizontal, .space8)
                            .padding(.vertical, .space8)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { resultsHeight = $0 }
                        }
                        .frame(height: min(resultsHeight, Constants.resultsMaxHeight))
                        .onChange(of: store.activeIndex) { _, index in
                            guard let index else { return }
                            withAnimation(DSMotion.stateFade) {
                                proxy.scrollTo(index)
                            }
                        }
                    }
                }
                if let statusText {
                    Text(statusText)
                        .type(.body3(.regular), style: .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, .space24)
                        .padding(.vertical, .space12)
                }
                if store.canShowMore {
                    Button { store.send(.showMoreTapped) } label: {
                        Text(L10n.Browse.searchShowMore)
                            .type(.body3(.semibold), style: .secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, .space24)
                            .padding(.bottom, .space12)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private struct SpotlightResultRow: View {
        let result: SearchResultItem
        let serverURL: URL
        let shouldShowThumbnails: Bool
        let isActive: Bool
        let onHover: (Bool) -> Void
        let onOpen: () -> Void

        private var subtitle: String {
            [searchResultLocation(result), searchResultRowLabel(result)]
                .compactMap(\.self)
                .joined(separator: " \u{00B7} ")
        }

        var body: some View {
            Button(action: onOpen) {
                HStack(spacing: .space12) {
                    FileRowView(
                        name: result.name,
                        isDirectory: result.isDirectory,
                        subtitle: subtitle,
                        kind: result.displayKind,
                        thumbnailFile: result.thumbnailFile,
                        serverURL: serverURL,
                        shouldShowThumbnails: shouldShowThumbnails
                    )
                    if isActive {
                        MacKeyHint(MacShortcutHint.enter)
                            .accessibilityHidden(true)
                    }
                }
                .padding(.horizontal, .space12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Constants.rowRadius, style: .continuous)
                        .fill(isActive ? Color.macRow : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover(perform: onHover)
            .accessibilityAddTraits(isActive ? .isSelected : [])
        }
    }

    @MainActor
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
        SpotlightView(store: PreviewFixture.store(query: "b", phase: .idle)).frame(width: 800, height: 400)
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
