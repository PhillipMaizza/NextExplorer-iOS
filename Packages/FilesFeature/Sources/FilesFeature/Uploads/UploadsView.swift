import ComposableArchitecture
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let rowIconSize: CGFloat = .iconMedium
    static let rowSpacing: CGFloat = .space12
    static let textSpacing: CGFloat = .space4
    static let controlSize: CGFloat = .iconSmall
    static let progressWidth: CGFloat = 96
}

/// The full upload queue, opened by tapping the persistent progress bar. One row per file with
/// live progress, a cancel button while it runs, and retry on failure.
struct UploadsView: View {
    @Bindable var store: StoreOf<UploadsFeature>

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.Uploads.navigationTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { store.send(.sheetPresented(false)) } label: {
                            IconKit.close.foregroundStyle(Color.primaryDS)
                        }
                        .accessibilityLabel(L10n.Common.close)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(L10n.Uploads.clear) { store.send(.clearFinishedTapped, animation: .default) }
                            .disabled(!store.hasClearableJobs)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.jobs.isEmpty {
            EmptyStateView(icon: IconKit.upload, message: L10n.Uploads.emptyList)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(store.jobs) { job in
                    row(job)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.backgroundPrimary)
        }
    }

    private func row(_ job: UploadsFeature.UploadJob) -> some View {
        HStack(spacing: Constants.rowSpacing) {
            FileTypeIcon(kind: (job.fileName as NSString).pathExtension)
                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
            VStack(alignment: .leading, spacing: Constants.textSpacing) {
                Text(job.fileName)
                    .type(.body2(.regular), style: .primary(for: .label))
                    .lineLimit(1)
                    .truncationMode(.middle)
                subtitle(job)
            }
            Spacer(minLength: Constants.rowSpacing)
            control(job)
        }
    }

    @ViewBuilder
    private func subtitle(_ job: UploadsFeature.UploadJob) -> some View {
        switch job.status {
        case .queued:
            Text(L10n.Uploads.statusWaiting).type(.body3(.regular), style: .secondary)
        case .uploading:
            ProgressView(value: job.progress)
                .tint(Color.positive)
                .frame(width: Constants.progressWidth)
        case .completed:
            Text(destinationLabel(job.destination)).type(.body3(.regular), style: .secondary).lineLimit(1)
        case let .failed(message):
            Text(message).type(.body3(.regular), style: .secondary).lineLimit(1)
        }
    }

    @ViewBuilder
    private func control(_ job: UploadsFeature.UploadJob) -> some View {
        switch job.status {
        case .queued, .uploading:
            Button { store.send(.cancelJobTapped(id: job.id), animation: .default) } label: {
                IconKit.closeCircle
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.controlSize, height: Constants.controlSize)
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(L10n.Common.cancel)
        case .completed:
            IconKit.checkmarkCircleFill
                .resizable().scaledToFit()
                .foregroundStyle(Color.positive)
                .frame(width: Constants.controlSize, height: Constants.controlSize)
        case .failed:
            Button { store.send(.retryTapped(id: job.id), animation: .default) } label: {
                IconKit.retry
                    .resizable().scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: Constants.controlSize, height: Constants.controlSize)
            }
            .buttonStyle(DSHapticButtonStyle())
            .accessibilityLabel(L10n.Common.retry)
        }
    }

    private func destinationLabel(_ path: String) -> String {
        path.isEmpty ? L10n.Browse.locations : (path as NSString).lastPathComponent
    }
}

#Preview {
    UploadsView(
        store: Store(initialState: UploadsFeature.State(serverURL: URL(string: "https://example.com")!)) {
            UploadsFeature()
        }
    )
}
