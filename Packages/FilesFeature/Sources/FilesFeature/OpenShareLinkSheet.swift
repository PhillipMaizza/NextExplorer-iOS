import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI
import UIKit

private enum Constants {
    static let contentSpacing: CGFloat = .space16
    static let sectionSpacing: CGFloat = .space8
    static let horizontalPadding: CGFloat = .space24
    static let verticalPadding: CGFloat = .space24
    static let cardPadding: CGFloat = .space16
    static let cardCornerRadius: CGFloat = .radiusCard
    static let summaryIconSize: CGFloat = .iconMedium
    static let rowIconSize: CGFloat = .iconSmall
    static let maxHeightFraction: CGFloat = 0.9
}

/// "Open a shared link" — paste a share URL or token, look it up via
/// `GET /api/share/<token>/info`, then hand `share/<token>` to the Browse tab.
struct OpenShareLinkSheet: View {
    @Bindable var store: StoreOf<OpenShareLinkFeature>
    @Environment(\.dismiss) private var dismiss
    @State private var didCheckClipboard = false

    private static let expiryFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        DynamicHeightSheet(maxHeightFraction: Constants.maxHeightFraction) {
            VStack(alignment: .leading, spacing: Constants.contentSpacing) {
                DSSheetHeader(
                    icon: IconKit.shareLink,
                    title: L10n.OpenShareLink.title,
                    closeAccessibilityLabel: L10n.Common.close,
                    onClose: { dismiss() }
                )

                VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
                    DSFieldLabel(L10n.OpenShareLink.fieldLabel)
                    DSTextField(
                        L10n.OpenShareLink.fieldPrompt,
                        text: $store.linkText.sending(\.linkTextChanged)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.go)
                    .onSubmit { store.send(.lookUpTapped) }
                }

                DSButton(L10n.OpenShareLink.lookUp, style: .secondary, isLoading: store.isResolving) {
                    store.send(.lookUpTapped)
                }
                .disabled(!store.canLookUp)

                if let errorMessage = store.errorMessage {
                    DSErrorCard(errorMessage)
                }

                if let info = store.info {
                    summaryCard(info)
                }
            }
            .padding(.horizontal, Constants.horizontalPadding)
            .padding(.vertical, Constants.verticalPadding)
        } footer: {
            if store.info != nil {
                footer
            }
        }
        .onAppear(perform: prefillFromClipboard)
    }

    /// The sheet's whole job is to paste a share link, so when it opens with an empty field
    /// and the clipboard already holds something link shaped, drop it straight in. Guarded so
    /// a deliberately cleared field isn't refilled on a re-appear.
    private func prefillFromClipboard() {
        guard !didCheckClipboard else { return }
        didCheckClipboard = true
        guard store.linkText.isEmpty,
              UIPasteboard.general.hasStrings,
              let pasted = UIPasteboard.general.string,
              OpenShareLinkFeature.token(from: pasted) != nil
        else { return }
        store.send(.linkTextChanged(pasted))
    }

    private var footer: some View {
        DSButton(L10n.OpenShareLink.open, style: .primary) {
            store.send(.openTapped)
            dismiss()
        }
        .disabled(!store.canOpen)
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.top, Constants.sectionSpacing)
        .padding(.bottom, Constants.verticalPadding)
        .frame(maxWidth: .infinity)
        .background(Color.backgroundPrimary)
    }

    private func summaryCard(_ info: ShareInfo) -> some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            HStack(spacing: .space12) {
                (info.isDirectory ? IconKit.folderFill : IconKit.document)
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: Constants.summaryIconSize, height: Constants.summaryIconSize)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(info.label ?? (info.isDirectory ? L10n.OpenShareLink.sharedFolder : L10n.OpenShareLink.sharedFile))
                        .type(.body2(.bold), style: .primary(for: .label))
                        .lineLimit(2)
                    Text(info.isDirectory ? L10n.OpenShareLink.sharedFolder : L10n.OpenShareLink.sharedFile)
                        .type(.caption(.regular), style: .secondary)
                }
                Spacer(minLength: 0)
            }

            if let expiresAt = info.expiresAt {
                metaRow(IconKit.calendar, L10n.OpenShareLink.expiresPrefix(Self.expiryFormatter.string(from: expiresAt)))
            }
            if info.hasPassword {
                metaRow(IconKit.lock, L10n.OpenShareLink.passwordProtected)
            }
            if info.isRestrictedToUsers {
                metaRow(IconKit.people, L10n.OpenShareLink.restrictedNote)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Constants.cardPadding)
        .background(RoundedRectangle(cornerRadius: Constants.cardCornerRadius).fill(Color.backgroundSecondary))
    }

    private func metaRow(_ icon: Image, _ text: String) -> some View {
        HStack(spacing: .space8) {
            icon
                .resizable().scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
            Text(text).type(.body3(.regular), style: .secondary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Previews

@MainActor
private func openShareLinkPreview(
    _ state: OpenShareLinkFeature.State,
    configureClient: @Sendable (inout FilesClient) -> Void = { _ in }
) -> some View {
    var client = FilesClient.previewValue
    configureClient(&client)
    return Color.clear.sheet(isPresented: .constant(true)) {
        OpenShareLinkSheet(
            store: Store(initialState: state) {
                OpenShareLinkFeature()
            } withDependencies: {
                $0.filesClient = client
            }
        )
    }
}

private let previewServerURL = URL(string: "https://cloud.example.com")!

private func previewState(linkText: String = "", info: ShareInfo? = nil, errorMessage: String? = nil) -> OpenShareLinkFeature.State {
    var state = OpenShareLinkFeature.State(serverURL: previewServerURL)
    state.linkText = linkText
    state.info = info
    state.errorMessage = errorMessage
    return state
}

#Preview("Empty") {
    openShareLinkPreview(previewState())
}

#Preview("Folder resolved") {
    openShareLinkPreview(previewState(
        linkText: "https://cloud.example.com/share/AbC123xyz0",
        info: ShareInfo(shareToken: "AbC123xyz0", label: "Q3 Report", isDirectory: true, sharingType: .anyone)
    ))
}

#Preview("File, password, expiry") {
    openShareLinkPreview(previewState(
        linkText: "AbC123xyz0",
        info: ShareInfo(
            shareToken: "AbC123xyz0", label: "passport.pdf", isDirectory: false,
            hasPassword: true, sharingType: .anyone,
            expiresAt: Date().addingTimeInterval(86_400 * 5)
        )
    ))
}

#Preview("Restricted to users") {
    openShareLinkPreview(previewState(
        linkText: "https://cloud.example.com/share/AbC123xyz0",
        info: ShareInfo(shareToken: "AbC123xyz0", label: "Team Roadmap", isDirectory: true, sharingType: .users)
    ))
}

#Preview("Not found") {
    openShareLinkPreview(previewState(linkText: "https://cloud.example.com/share/nope00", errorMessage: L10n.OpenShareLink.errorNotFound))
}
