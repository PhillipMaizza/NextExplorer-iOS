#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let tileSize: CGFloat = 42
        static let tileGlyph: CGFloat = 21
        static let keyAngle: Double = -45
        static let rowHeight: CGFloat = .size72
        static let menuSize: CGFloat = 38
        static let menuGlyph: CGFloat = .size12
    }

    struct MacAPITokensPane: View {
        @Bindable var store: StoreOf<APITokensFeature>

        var body: some View {
            MacFormPage {
                switch store.phase {
                case .loading:
                    MacSpinner()
                        .frame(maxWidth: .infinity)
                case let .failed(message):
                    MacNote(message, kind: .error)
                    RetryLinkButton { store.send(.retryTapped) }
                case .loaded:
                    loadedContent
                }
            }
            .task { store.send(.task) }
            .macAPITokenSheets(store)
        }

        @ViewBuilder
        private var loadedContent: some View {
            if let message = store.errorMessage, store.createForm == nil, store.rename == nil {
                MacNote(message, kind: .error)
            }
            VStack(alignment: .leading, spacing: .space8) {
                MacFormGroup {
                    if store.tokens.isEmpty {
                        MacFormRow {
                            MacFormRowTitle(title: L10n.ApiTokens.emptyTitle, subtitle: L10n.ApiTokens.emptyMessage)
                        } control: {
                            EmptyView()
                        }
                    } else {
                        ForEach(store.tokens) { token in
                            MacAPITokenRow(token: token) {
                                store.send(.renameTapped(token))
                            } onRevoke: {
                                store.send(.revokeTapped(token))
                            }
                        }
                    }
                }
                MacFormFootnote(
                    store.hasReachedLimit
                        ? L10n.ApiTokens.limitReached(APITokenLimits.maxTokensPerAccount)
                        : L10n.ApiTokens.intro
                )
            }
        }
    }

    private struct MacAPITokenRow: View {
        let token: APIToken
        let onRename: () -> Void
        let onRevoke: () -> Void
        @Dependency(\.date.now) private var now

        var body: some View {
            let isExpired = token.isExpired(now: now)
            MacFormRow {
                HStack(spacing: .space16) {
                    keyTile
                    VStack(alignment: .leading, spacing: .space2) {
                        HStack(spacing: .space8) {
                            Text(token.name)
                                .lineLimit(1)
                            if isExpired {
                                MacChip(text: L10n.ApiTokens.badgeExpired, tone: .red)
                            }
                        }
                        Text(details)
                            .type(.body3(.regular), style: .secondary)
                            .lineLimit(1)
                    }
                }
            } control: {
                HStack(spacing: .space12) {
                    MacChip(text: token.scope.title, tone: token.scope == .write ? .green : .gray)
                    menu
                }
            }
            .frame(minHeight: Metrics.rowHeight)
        }

        private var keyTile: some View {
            RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                .fill(Color.macTagAmberFill)
                .frame(width: Metrics.tileSize, height: Metrics.tileSize)
                .overlay {
                    IconKit.keyHorizontal
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.tileGlyph, height: Metrics.tileGlyph)
                        .rotationEffect(.degrees(Metrics.keyAngle))
                        .foregroundStyle(Color.macTagAmber)
                }
                .accessibilityHidden(true)
        }

        private var menu: some View {
            Menu {
                Button(L10n.ellipsized(L10n.ApiTokens.renameAction), action: onRename)
                Button(L10n.ellipsized(L10n.ApiTokens.revokeAction), role: .destructive, action: onRevoke)
            } label: {
                IconKit.ellipsis
                    .resizable()
                    .scaledToFit()
                    .frame(width: Metrics.menuGlyph, height: Metrics.menuGlyph)
                    .foregroundStyle(Color.macChromeSecondary)
                    .frame(width: Metrics.menuSize, height: Metrics.menuSize)
                    .background(Circle().fill(Color.macSegment))
                    .contentShape(Circle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(L10n.ApiTokens.menuAccessibilityLabel(token.name))
        }

        private var details: String {
            ServerSettingsMetrics.joined(
                [token.createdLine, token.lastUsedAt == nil ? nil : token.usageLine, token.expiryLine(now: now)]
                    .compactMap(\.self)
            )
        }
    }

    struct MacAPITokensNewButton: View {
        let store: StoreOf<APITokensFeature>

        var body: some View {
            Button {
                store.send(.newTokenTapped)
            } label: {
                Label {
                    Text(L10n.ellipsized(L10n.ApiTokens.newButton))
                } icon: {
                    IconKit.plus
                }
            }
            .buttonStyle(.macDS(.primary))
            .disabled(store.phase != .loaded || store.hasReachedLimit || store.isWorking)
        }
    }

    private enum PreviewFixtures {
        static let serverURL = URL(string: "https://nextexplorer.example.com") ?? URL(fileURLWithPath: "/")
        static let tokens = [
            APIToken(
                id: "t1",
                name: "backup script",
                scope: .read,
                createdAt: "2026-11-01T07:00:00.000Z",
                expiresAt: "2027-02-01T00:00:00.000Z",
                lastUsedAt: "2026-11-10T08:00:00.000Z",
                lastUsedIp: "10.0.0.5"
            ),
            APIToken(id: "t2", name: "home automation", scope: .write, createdAt: "2026-11-10T07:00:00.000Z"),
            APIToken(
                id: "t3",
                name: "old test",
                scope: .read,
                createdAt: "2025-01-01T07:00:00.000Z",
                expiresAt: "2025-06-01T00:00:00.000Z"
            ),
        ]

        @MainActor
        static func pane(_ state: APITokensFeature.State) -> some View {
            let store = Store(initialState: state) { EmptyReducer<APITokensFeature.State, APITokensFeature.Action>() }
            return MacPaneCard(title: L10n.ApiTokens.navigationTitle, subtitle: nil) {
                MacAPITokensPane(store: store)
            } tools: {
                MacAPITokensNewButton(store: store)
            }
            .background(Color.macChrome)
            .previewCanvas(.settingsPane)
        }
    }

    #Preview("Tokens") {
        PreviewFixtures.pane(.init(
            serverURL: PreviewFixtures.serverURL,
            phase: .loaded,
            tokens: PreviewFixtures.tokens
        ))
    }

    #Preview("Empty") {
        PreviewFixtures.pane(.init(serverURL: PreviewFixtures.serverURL, phase: .loaded))
    }

    #Preview("Loading") {
        PreviewFixtures.pane(.init(serverURL: PreviewFixtures.serverURL, phase: .loading))
    }

    #Preview("Failed") {
        PreviewFixtures.pane(.init(
            serverURL: PreviewFixtures.serverURL,
            phase: .failed("This installation runs without accounts, so it issues no tokens.")
        ))
    }

    #Preview("At the limit") {
        PreviewFixtures.pane(.init(
            serverURL: PreviewFixtures.serverURL,
            phase: .loaded,
            tokens: (0 ..< APITokenLimits.maxTokensPerAccount).map {
                APIToken(id: "t\($0)", name: "token \($0)", scope: .read, createdAt: "2026-11-01T07:00:00.000Z")
            }
        ))
    }
#endif
