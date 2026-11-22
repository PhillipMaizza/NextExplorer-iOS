import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private typealias Metrics = APITokensMetrics

struct APITokensPresentations: ViewModifier {
    @Bindable var store: StoreOf<APITokensFeature>

    func body(content: Content) -> some View {
        content
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
                TextField(
                    L10n.ApiTokens.fieldName,
                    text: Binding(get: { store.rename?.name ?? "" }, set: { store.send(.renameNameChanged($0)) })
                )
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
}

extension View {
    func apiTokensPresentations(_ store: StoreOf<APITokensFeature>) -> some View {
        modifier(APITokensPresentations(store: store))
    }
}

extension APIToken {
    func isExpired(now: Date) -> Bool {
        APITokenDates.isExpired(expiresAt, now: now)
    }

    func expiryLine(now: Date) -> String {
        guard let expires = expiresAt.flatMap({ APITokenDates.display($0) }) else {
            return L10n.ApiTokens.neverExpires
        }
        return isExpired(now: now) ? L10n.ApiTokens.expired(expires) : L10n.ApiTokens.expires(expires)
    }

    var createdLine: String? {
        APITokenDates.display(createdAt).map { L10n.ApiTokens.created($0) }
    }

    var usageLine: String {
        guard let used = lastUsedAt.flatMap({ APITokenDates.display($0) }) else {
            return L10n.ApiTokens.neverUsed
        }
        if let ip = lastUsedIp, !ip.isEmpty {
            return L10n.ApiTokens.lastUsedFrom(used, ip)
        }
        return L10n.ApiTokens.lastUsed(used)
    }
}

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

#Preview("Secret") {
    APITokenIssuedSheet(issued: IssuedAPIToken(
        token: APIToken(id: "t1", name: "backup script", scope: .read, createdAt: "2026-11-01T07:00:00.000Z"),
        secret: "nxt_0123456789abcdef.0123456789abcdef0123456789abcdef"
    )) {}
}
