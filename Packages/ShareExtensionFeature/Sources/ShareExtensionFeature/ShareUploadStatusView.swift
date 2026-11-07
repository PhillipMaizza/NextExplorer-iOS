import ComposableArchitecture
import CoreModels
import Dependencies
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let sectionSpacing: CGFloat = .space12
    static let progressSpacing: CGFloat = .space8
    static let failureLineLimit = 3
}

extension ItemFailureCause {
    var message: String {
        switch self {
        case .cannotRead: L10n.ShareUpload.causeCannotRead
        case .notEnoughSpace: L10n.ShareUpload.causeNotEnoughSpace
        case .other: L10n.ShareUpload.causeUnknown
        }
    }
}

extension ItemFailure {
    /// "IMG_0042.MOV: It couldn't be read."
    var line: String {
        L10n.ShareUpload.failedItemLine(name, cause.message)
    }
}

/// The line under the title (iPhone and iPad): how many files, the progress while preparing, or
/// why nothing can be uploaded and what to do about it.
struct ShareUploadStatus: View {
    let store: StoreOf<ShareUploadFeature>
    @Dependency(\.openApp) private var openApp

    var body: some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            switch store.phase {
            case .loading:
                DSSpinner().frame(maxWidth: .infinity)
            case .signedOut:
                DSErrorCard(L10n.ShareUpload.signedOut)
                if !openApp.isAvailable {
                    Text(L10n.ShareUpload.openAppInstructions).type(.body3(.regular), style: .secondary)
                }
            case .sessionUnreadable:
                DSErrorCard(L10n.ShareUpload.sessionUnreadable)
            case .nothingToUpload:
                DSErrorCard(L10n.ShareUpload.nothingToUpload)
            case .failed:
                DSErrorCard(L10n.ShareUpload.failed)
                ShareUploadFailureList(failures: store.failures)
            case .partiallyPrepared:
                Text(L10n.ShareUpload.readyCount(store.stagedCount)).type(.body2(.semibold))
                ShareUploadFailureList(failures: store.failures)
            case .certificateRequired:
                DSErrorCard(L10n.ShareUpload.certificateRequired)
            case .certificateRejected:
                DSErrorCard(L10n.ShareUpload.certificateRejected)
            case .checking:
                Text(L10n.ShareUpload.itemCount(store.itemCount)).type(.body2(.regular), style: .secondary)
                livePhotoNote
                HStack(spacing: Constants.progressSpacing) {
                    DSSpinner(size: .small, accessibilityLabel: L10n.ShareUpload.checking(store.serverName))
                    Text(L10n.ShareUpload.checking(store.serverName)).type(.body3(.regular), style: .secondary)
                }
            case .ready:
                Text(L10n.ShareUpload.itemCount(store.itemCount)).type(.body2(.regular), style: .secondary)
                livePhotoNote
                if store.notice == .defaultFolderUnavailable {
                    DSInfoCard(L10n.ShareUpload.defaultFolderUnavailable)
                }
            case .preparing:
                VStack(alignment: .leading, spacing: Constants.progressSpacing) {
                    ProgressView(value: store.preparationFraction)
                        .tint(Color.accent)
                    Text(L10n.ShareUpload.preparing(min(store.progress.completed + 1, store.preparingTotal), store.preparingTotal))
                        .type(.body2(.regular), style: .secondary)
                    Text(L10n.ShareUpload.keepOpen).type(.body3(.regular), style: .secondary)
                }
                .accessibilityElement(children: .combine)
            case .started:
                Label {
                    Text(L10n.ShareUpload.started).type(.body2(.regular))
                } icon: {
                    IconKit.checkmark.foregroundStyle(Color.positiveText)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private extension ShareUploadStatus {
    @ViewBuilder
    var livePhotoNote: some View {
        if store.livePhotoCount > 0 {
            Text(L10n.ShareUpload.livePhotoNote).type(.body3(.regular), style: .secondary)
        }
    }
}

/// The files that could not be prepared, each by name with the cause.
struct ShareUploadFailureList: View {
    let failures: [ItemFailure]

    var body: some View {
        if !failures.isEmpty {
            VStack(alignment: .leading, spacing: .space8) {
                Text(L10n.ShareUpload.failedItemsHeader).type(.body3(.semibold))
                LazyVStack(alignment: .leading, spacing: .space4) {
                    ForEach(failures) { failure in
                        Text(failure.line)
                            .type(.body3(.regular), style: .secondary)
                            .lineLimit(Constants.failureLineLimit)
                            .truncationMode(.middle)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .dsCard()
            .accessibilityElement(children: .contain)
        }
    }
}

/// The buttons under the status (iPhone and iPad), by phase: Upload while there is something to
/// send, the choice between the ready files and the failed ones, or Try Again for a state that
/// can be retried.
struct ShareUploadActions: View {
    let store: StoreOf<ShareUploadFeature>

    var body: some View {
        switch store.phase {
        case .checking, .ready, .preparing:
            DSButton(L10n.ShareUpload.upload, style: .primary, isLoading: store.phase == .preparing || store.phase == .checking) {
                store.send(.uploadTapped)
            }
            .disabled(!store.canUpload)
        case .partiallyPrepared:
            VStack(spacing: .space8) {
                DSButton(L10n.ShareUpload.uploadReady, style: .primary) { store.send(.uploadReadyTapped) }
                DSButton(L10n.ShareUpload.retryFailed, style: .secondary) { store.send(.retryTapped) }
            }
        case .signedOut, .sessionUnreadable, .certificateRequired, .certificateRejected, .failed:
            DSButton(L10n.Common.retry, style: .secondary) { store.send(.retryTapped) }
        case .loading, .nothingToUpload, .started:
            EmptyView()
        }
    }
}

extension ShareUploadFeature.State {
    /// Whether the footer has anything to show.
    var hasActions: Bool {
        ![.loading, .nothingToUpload, .started].contains(phase)
    }
}

#Preview("Status, every phase") {
    ScrollView {
        VStack(alignment: .leading, spacing: .space16) {
            ForEach(ShareUploadFeature.Phase.previewCases, id: \.self) { phase in
                ShareUploadStatus(store: .preview(phase))
            }
        }
        .padding(.space24)
    }
}

#Preview("Status, with Live Photos") {
    ShareUploadStatus(store: .preview(.ready, livePhotos: 3))
        .padding(.space24)
}

#Preview("Status, default folder gone") {
    ShareUploadStatus(store: .preview(.ready, notice: .defaultFolderUnavailable))
        .padding(.space24)
}

#Preview("Failed items") {
    ShareUploadStatus(store: .preview(.partiallyPrepared, failures: ItemFailure.previews))
        .padding(.space24)
}

#Preview("Failure list") {
    ShareUploadFailureList(failures: ItemFailure.previews)
        .padding(.space24)
}

#Preview("Actions") {
    VStack(spacing: .space24) {
        ForEach([ShareUploadFeature.Phase.ready, .checking, .partiallyPrepared, .failed, .signedOut], id: \.self) { phase in
            ShareUploadActions(store: .preview(phase))
        }
    }
    .padding(.space24)
}

extension ShareUploadFeature.Phase {
    static let previewCases: [ShareUploadFeature.Phase] = [
        .loading, .checking, .ready, .preparing, .partiallyPrepared, .started, .signedOut, .sessionUnreadable,
        .nothingToUpload, .failed, .certificateRequired, .certificateRejected,
    ]
}

extension ItemFailure {
    static let previews = [
        ItemFailure(index: 1, name: "IMG_0042.MOV", cause: .notEnoughSpace),
        ItemFailure(index: 4, name: "Quarterly report with a very long file name that keeps going.pdf", cause: .cannotRead),
        ItemFailure(index: 7, name: "File 8", cause: .other),
    ]
}
