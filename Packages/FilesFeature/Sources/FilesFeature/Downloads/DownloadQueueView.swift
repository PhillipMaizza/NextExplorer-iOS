import ComposableArchitecture
import CoreModels
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

/// The download queue, opened by tapping the progress bar. One row per item with live progress,
/// cancel while it runs, retry on failure, and a shortcut to the Downloads tab.
struct DownloadQueueView: View {
    @Bindable var store: StoreOf<DownloadQueueFeature>
    let onOpenDownloads: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(L10n.DownloadQueue.navigationTitle)
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
                    ToolbarItem(placement: .bottomBar) {
                        Button(L10n.DownloadQueue.openDownloads, action: onOpenDownloads)
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if store.jobs.isEmpty {
            EmptyStateView(icon: IconKit.download, message: L10n.DownloadQueue.emptyList)
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

    private func row(_ job: DownloadQueueFeature.DownloadJob) -> some View {
        HStack(spacing: Constants.rowSpacing) {
            FileTypeIcon(kind: (job.fileName as NSString).pathExtension)
                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
            VStack(alignment: .leading, spacing: Constants.textSpacing) {
                Text(job.fileName)
                    .type(.body2(.regular), style: .primaryOnSurface)
                    .lineLimit(1)
                    .truncationMode(.middle)
                subtitle(job)
            }
            Spacer(minLength: Constants.rowSpacing)
            control(job)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func subtitle(_ job: DownloadQueueFeature.DownloadJob) -> some View {
        switch job.status {
        case .queued:
            Text(L10n.Uploads.statusWaiting).type(.body3(.regular), style: .secondary)
        case .downloading:
            VStack(alignment: .leading, spacing: Constants.textSpacing) {
                Group {
                    if let progress = job.progress {
                        ProgressView(value: progress).tint(Color.positive)
                    } else {
                        IndeterminateProgressBar()
                    }
                }
                .frame(width: Constants.progressWidth)
                if let detail = DownloadProgressText.detail(for: job, locale: locale) {
                    Text(detail)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(2)
                        .monospacedDigit()
                }
            }
        case .completed:
            Text(savedLabel(job)).type(.body3(.regular), style: .secondary)
        case let .failed(message):
            Text(message).type(.body3(.regular), style: .secondary).lineLimit(1)
        }
    }

    private func savedLabel(_ job: DownloadQueueFeature.DownloadJob) -> String {
        guard job.receivedBytes > 0 else { return L10n.DownloadQueue.statusSaved }
        return L10n.DownloadQueue.statusSaved + " · " + DownloadProgressText.bytes(job.receivedBytes, locale: locale)
    }

    @ViewBuilder
    private func control(_ job: DownloadQueueFeature.DownloadJob) -> some View {
        switch job.status {
        case .queued, .downloading:
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
}

private extension DownloadQueueFeature.State {
    static func preview(_ jobs: [DownloadQueueFeature.DownloadJob]) -> Self {
        var state = Self(serverURL: URL(string: "https://example.com") ?? URL(fileURLWithPath: "/"))
        state.jobs = IdentifiedArray(uniqueElements: jobs)
        return state
    }
}

private func previewJob(
    _ name: String, kind: String, status: DownloadQueueFeature.DownloadJob.Status,
    received: Int64 = 0, expected: Int64? = nil, rate: Double? = nil
) -> DownloadQueueFeature.DownloadJob {
    var job = DownloadQueueFeature.DownloadJob(
        id: UUID(),
        item: FileItem(name: name, path: "Files", dateModified: Date(), size: 0, kind: kind),
        status: status
    )
    job.receivedBytes = received
    job.expectedBytes = expected
    job.bytesPerSecond = rate
    return job
}

#Preview("Mixed") {
    DownloadQueueView(
        store: Store(initialState: .preview([
            previewJob("Holiday.mp4", kind: "mp4", status: .downloading, received: 420_000_000, expected: 1_600_000_000, rate: 12_000_000),
            previewJob("Photos", kind: "directory", status: .downloading, received: 312_000_000),
            previewJob("Report.pdf", kind: "pdf", status: .completed, received: 2_400_000),
            previewJob("Big.iso", kind: "iso", status: .failed("Couldn't reach the server.")),
        ])) {
            DownloadQueueFeature()
        },
        onOpenDownloads: {}
    )
}

#Preview("Empty") {
    DownloadQueueView(
        store: Store(initialState: DownloadQueueFeature.State.preview([DownloadQueueFeature.DownloadJob]())) {
            DownloadQueueFeature()
        },
        onOpenDownloads: {}
    )
}
