import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

enum APITokensMetrics {
    static let sectionSpacing: CGFloat = .space16
    static let horizontalPadding: CGFloat = .space16
    static let rowIconSize: CGFloat = .iconSmall
    static let sheetMinWidth: CGFloat = 420
    static let sheetMinHeight: CGFloat = 460
}

private typealias Metrics = APITokensMetrics

/// Turns the server's ISO 8601 timestamps into something to read, and says whether one has passed.
enum APITokenDates {
    private static func parse(_ iso: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFraction.date(from: iso) ?? plain.date(from: iso)
    }

    /// `nil` for a timestamp that is not a date, so the row leaves the line out instead of showing noise.
    static func display(_ iso: String, locale: Locale = .current, timeZone: TimeZone = .current) -> String? {
        guard let date = parse(iso) else { return nil }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale, timeZone: timeZone)
        style.calendar = Calendar(identifier: .gregorian)
        return date.formatted(style)
    }

    static func isExpired(_ iso: String?, now: Date) -> Bool {
        guard let iso, let date = parse(iso) else { return false }
        return date <= now
    }
}

/// The signed in account's API tokens. Mirrors the web client's token settings.
struct APITokensView: View {
    @Bindable var store: StoreOf<APITokensFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                switch store.phase {
                case .loading:
                    ProgressView().frame(maxWidth: .infinity)
                case let .failed(message):
                    DSErrorCard(message)
                    RetryLinkButton { store.send(.retryTapped) }
                case .loaded:
                    loadedContent
                }
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.vertical, Metrics.sectionSpacing)
        }
        .backgroundGradient()
        .navigationTitle(L10n.ApiTokens.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { store.send(.task) }
        .sheet(isPresented: Binding(get: { store.createForm != nil }, set: {
            if !$0 {
                store.send(.createCancelled)
            }
        })) {
            APITokenCreateSheet(store: store)
        }
        .sheet(item: Binding(get: { store.issued }, set: {
            if $0 == nil {
                store.send(.issuedDismissed)
            }
        })) { issued in
            APITokenIssuedSheet(issued: issued) { store.send(.issuedDismissed) }
        }
        .alert(L10n.ApiTokens.renameTitle, isPresented: Binding(get: { store.rename != nil }, set: {
            if !$0 {
                store.send(.renameCancelled)
            }
        })) {
            TextField(L10n.ApiTokens.fieldName, text: Binding(get: { store.rename?.name ?? "" }, set: { store.send(.renameNameChanged($0)) }))
            Button(L10n.ApiTokens.renameSave) { store.send(.renameSubmitted) }
                .disabled(!store.isRenameEnabled)
            Button(L10n.Common.cancel, role: .cancel) { store.send(.renameCancelled) }
        }
        .dsAlert(isPresented: Binding(get: { store.tokenPendingRevoke != nil }, set: { _ in })) {
            DSAlertSheet(
                icon: IconKit.delete,
                title: L10n.ApiTokens.revokeTitle,
                message: L10n.ApiTokens.revokeMessage(store.tokenPendingRevoke?.name ?? ""),
                confirmTitle: L10n.ApiTokens.revokeConfirm,
                dismissTitle: L10n.Common.cancel,
                role: .destructive,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: { store.send(.revokeConfirmed) },
                onDismiss: { store.send(.revokeCancelled) }
            )
        }
    }

    // MARK: - Loaded

    @ViewBuilder
    private var loadedContent: some View {
        Card {
            HStack(alignment: .top, spacing: .space8) {
                IconKit.key
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Metrics.rowIconSize, height: Metrics.rowIconSize)
                    .padding(.top, .space2)
                Text(L10n.ApiTokens.intro).type(.body3(.regular), style: .secondary)
            }
        }
        if let message = store.errorMessage, store.createForm == nil {
            DSErrorCard(message)
        }
        if store.tokens.isEmpty {
            VStack(spacing: .space4) {
                Text(L10n.ApiTokens.emptyTitle).type(.body2(.semibold), style: .primaryOnSurface)
                Text(L10n.ApiTokens.emptyMessage).type(.body3(.regular), style: .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, .space16)
        } else {
            ForEach(store.tokens) { token in
                APITokenRow(token: token) {
                    store.send(.renameTapped(token))
                } onRevoke: {
                    store.send(.revokeTapped(token))
                }
            }
        }
        if store.hasReachedLimit {
            Text(L10n.ApiTokens.limitReached(APITokenLimits.maxTokensPerAccount))
                .type(.body3(.regular), style: .secondary)
        }
        DSButton(L10n.ApiTokens.newButton, style: .primary) {
            store.send(.newTokenTapped)
        }
        .disabled(store.hasReachedLimit || store.isWorking)
        .formActionAlignment()
    }
}

private struct APITokenRow: View {
    let token: APIToken
    let onRename: () -> Void
    let onRevoke: () -> Void

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: .space8) {
                VStack(alignment: .leading, spacing: .space4) {
                    Text(token.name).type(.body2(.semibold), style: .primaryOnSurface)
                    Text(scopeText).type(.body3(.regular), style: .secondary)
                    ForEach(detailLines, id: \.self) { line in
                        Text(line).type(.body3(.regular), style: .secondary)
                    }
                }
                Spacer(minLength: 0)
                expiryText
                Menu {
                    Button(L10n.ApiTokens.renameAction, action: onRename)
                    Button(L10n.ApiTokens.revokeAction, role: .destructive, action: onRevoke)
                } label: {
                    IconKit.moreOptions.accessibilityLabel(L10n.ApiTokens.menuAccessibilityLabel(token.name))
                }
            }
        }
    }

    /// On the right, in the accent color, so what lapses and when reads at a glance. A token that
    /// has lapsed says so in the danger color instead.
    private var expiryText: some View {
        let isExpired = APITokenDates.isExpired(token.expiresAt, now: Date())
        return Text(expiryLine)
            .type(.body3(.regular), style: .link)
            .foregroundStyle(isExpired ? Color.negativeText : Color.accentText)
            .multilineTextAlignment(.trailing)
    }

    private var expiryLine: String {
        guard let expires = token.expiresAt.flatMap({ APITokenDates.display($0) }) else {
            return L10n.ApiTokens.neverExpires
        }
        return APITokenDates.isExpired(token.expiresAt, now: Date()) ? L10n.ApiTokens.expired(expires) : L10n.ApiTokens.expires(expires)
    }

    private var scopeText: String {
        token.scope == .write ? L10n.ApiTokens.scopeWrite : L10n.ApiTokens.scopeRead
    }

    private var detailLines: [String] {
        var lines: [String] = []
        if let created = APITokenDates.display(token.createdAt) {
            lines.append(L10n.ApiTokens.created(created))
        }
        if let used = token.lastUsedAt.flatMap({ APITokenDates.display($0) }) {
            if let ip = token.lastUsedIp, !ip.isEmpty {
                lines.append(L10n.ApiTokens.lastUsedFrom(used, ip))
            } else {
                lines.append(L10n.ApiTokens.lastUsed(used))
            }
        } else {
            lines.append(L10n.ApiTokens.neverUsed)
        }
        return lines
    }
}

/// The only time the secret is on screen, so it cannot be swiped away by accident.
private struct APITokenIssuedSheet: View {
    let issued: IssuedAPIToken
    let onDone: () -> Void
    @State private var isCopied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    Text(L10n.ApiTokens.issuedIntro).type(.body3(.regular), style: .secondary)
                    Card {
                        Text(issued.secret)
                            .type(.body2(.regular), style: .primaryOnSurface)
                            .monospaced()
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    DSButton(isCopied ? L10n.ApiTokens.copiedToken : L10n.ApiTokens.copyToken, style: .secondary) {
                        PlatformPasteboard.copy(issued.secret)
                        isCopied = true
                    }
                    .formActionAlignment()
                    DSButton(L10n.ApiTokens.issuedDone, style: .primary, action: onDone)
                        .formActionAlignment()
                }
                .padding(.horizontal, Metrics.horizontalPadding)
                .padding(.vertical, Metrics.sectionSpacing)
            }
            .backgroundGradient()
            .navigationTitle(L10n.ApiTokens.issuedTitle)
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
        #if os(macOS)
            .frame(minWidth: Metrics.sheetMinWidth, minHeight: Metrics.sheetMinHeight)
        #endif
    }
}

private enum PreviewFixtures {
    static let serverURL = URL(string: "https://nextexplorer.example.com")!
    static let tokens = [
        APIToken(id: "t1", name: "backup script", scope: .read, createdAt: "2026-11-01T07:00:00.000Z", expiresAt: "2027-02-01T00:00:00.000Z", lastUsedAt: "2026-11-10T08:00:00.000Z", lastUsedIp: "10.0.0.5"),
        APIToken(id: "t2", name: "home automation", scope: .write, createdAt: "2026-10-01T07:00:00.000Z"),
        APIToken(id: "t3", name: "old test", scope: .read, createdAt: "2025-01-01T07:00:00.000Z", expiresAt: "2025-06-01T00:00:00.000Z"),
    ]

    @MainActor
    static func view(_ state: APITokensFeature.State) -> some View {
        NavigationStack {
            APITokensView(store: Store(initialState: state) { EmptyReducer() })
        }
    }
}

#Preview("Loading") { PreviewFixtures.view(.init(serverURL: PreviewFixtures.serverURL, phase: .loading)) }
#Preview("Failed") { PreviewFixtures.view(.init(serverURL: PreviewFixtures.serverURL, phase: .failed("This installation runs without accounts, so it issues no tokens."))) }
#Preview("Empty") { PreviewFixtures.view(.init(serverURL: PreviewFixtures.serverURL, phase: .loaded)) }
#Preview("Tokens") { PreviewFixtures.view(.init(serverURL: PreviewFixtures.serverURL, phase: .loaded, tokens: PreviewFixtures.tokens)) }
#Preview("At the limit") {
    PreviewFixtures.view(.init(
        serverURL: PreviewFixtures.serverURL,
        phase: .loaded,
        tokens: (0 ..< APITokenLimits.maxTokensPerAccount).map { APIToken(id: "t\($0)", name: "token \($0)", scope: .read, createdAt: "2026-11-01T07:00:00.000Z") }
    ))
}

#Preview("Create form") {
    PreviewFixtures.view({
        var state = APITokensFeature.State(serverURL: PreviewFixtures.serverURL, phase: .loaded, tokens: PreviewFixtures.tokens)
        state.createForm = .init(name: "ci runner", scope: .write)
        return state
    }())
}

#Preview("Create form, wrong password") {
    PreviewFixtures.view({
        var state = APITokensFeature.State(serverURL: PreviewFixtures.serverURL, phase: .loaded, tokens: PreviewFixtures.tokens)
        state.createForm = .init(name: "ci runner")
        state.errorMessage = "That password is not right."
        return state
    }())
}

#Preview("Create form, no password") {
    PreviewFixtures.view({
        var state = APITokensFeature.State(serverURL: PreviewFixtures.serverURL, requiresPassword: false, phase: .loaded)
        state.createForm = .init(name: "ci runner")
        return state
    }())
}

#Preview("Secret") {
    PreviewFixtures.view({
        var state = APITokensFeature.State(serverURL: PreviewFixtures.serverURL, phase: .loaded, tokens: PreviewFixtures.tokens)
        state.issued = IssuedAPIToken(token: PreviewFixtures.tokens[0], secret: "nxt_0123456789abcdef.0123456789abcdef0123456789abcdef")
        return state
    }())
}

#Preview("Revoke") {
    PreviewFixtures.view({
        var state = APITokensFeature.State(serverURL: PreviewFixtures.serverURL, phase: .loaded, tokens: PreviewFixtures.tokens)
        state.tokenPendingRevoke = PreviewFixtures.tokens[0]
        return state
    }())
}
