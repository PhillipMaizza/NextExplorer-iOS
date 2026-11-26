#if os(macOS)
    import AppKit
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI
    import UserNotifications

    private enum Metrics {
        static let ringSize: CGFloat = 16
        static let ringLineWidth: CGFloat = .borderWidthStrong
        /// The progress ring sits just outside the glyph.
        static let ringFrameSize: CGFloat = ringSize + .size6
    }

    struct MacToolbarRingGlyph: View {
        let glyph: Image
        let progress: Double?
        let hasFailures: Bool

        var body: some View {
            ZStack {
                (hasFailures && progress == nil ? IconKit.error : glyph)
                    .macToolbarGlyph()
                    .foregroundStyle(
                        hasFailures && progress == nil
                            ? AnyShapeStyle(Color.negativeText)
                            : AnyShapeStyle(ForegroundStyle())
                    )
                if let progress {
                    MacProgressRing(progress: progress, lineWidth: Metrics.ringLineWidth)
                        .frame(width: Metrics.ringFrameSize, height: Metrics.ringFrameSize)
                }
            }
        }
    }

    struct MacUploadsActivity {
        let progress: Double?
        let failedCount: Int
        let open: () -> Void
    }

    struct MacUploadsActivityButton: View {
        let activity: MacUploadsActivity

        var body: some View {
            Button(action: activity.open) {
                MacToolbarRingGlyph(
                    glyph: IconKit.upload,
                    progress: activity.progress,
                    hasFailures: activity.failedCount > 0
                )
            }
            .buttonStyle(.macToolbarCircle)
            .accessibilityLabelWithTooltip(L10n.Uploads.navigationTitle)
            .accessibilityValue(
                activity.progress?.formatted(.percent.precision(.fractionLength(0)))
                    ?? (activity.failedCount > 0 ? TransferFailureText.uploads(activity.failedCount) : "")
            )
            .accessibilityIdentifier(AccessibilityIdentifiers.Browse.uploadMenu)
        }
    }

    struct MacTransferActivityButton: View {
        let store: StoreOf<MainTabFeature>
        @Environment(\.locale) private var locale

        var body: some View {
            let activity = MacDownloadActivity(store: store, locale: locale)
            let progress = activity.isActive ? activity.fraction ?? .zero : nil
            Button(action: activity.showAll) {
                MacToolbarRingGlyph(glyph: IconKit.download, progress: progress, hasFailures: activity.hasFailures)
            }
            .accessibilityLabelWithTooltip(L10n.DownloadQueue.navigationTitle)
            .accessibilityValue(
                progress?.formatted(.percent.precision(.fractionLength(0)))
                    ?? (activity.hasFailures ? activity.failureTitle : "")
            )
        }
    }

    /// A system notification when the upload or download queue finishes while the app is in
    /// the background, so a long transfer needs no watching.
    struct MacTransferNotifications: ViewModifier {
        let uploadsRemaining: Int
        let uploadsCompleted: Int
        let uploadsFailed: Int
        let downloadsRemaining: Int
        let downloadsSaved: Int
        let downloadsFailed: Int
        /// Where the last save landed in Finder, which the downloads notification names.
        var lastSavedURL: URL?

        func body(content: Content) -> some View {
            content
                .onChange(of: uploadsRemaining) { old, new in
                    guard drained(old: old, new: new), uploadsCompleted + uploadsFailed > 0 else { return }
                    notify(
                        title: uploadsFailed > 0 ? TransferFailureText.uploads(uploadsFailed) : L10n.Uploads.notifyDone,
                        body: L10n.Uploads.notifyBody(uploadsCompleted)
                    )
                }
                .onChange(of: downloadsRemaining) { old, new in
                    guard drained(old: old, new: new), downloadsSaved + downloadsFailed > 0 else { return }
                    notify(
                        title: downloadsFailed > 0
                            ? TransferFailureText.downloads(downloadsFailed)
                            : L10n.DownloadQueue.notifyDone,
                        body: downloadsBody
                    )
                }
        }

        private var downloadsBody: String {
            if let lastSavedURL {
                return MainTabFeature.macSavedMessage(count: downloadsSaved, lastSavedURL: lastSavedURL)
            }
            return downloadsSaved == 1 ? L10n.DownloadQueue.savedOne : L10n.DownloadQueue.savedMany(downloadsSaved)
        }

        /// Asks for permission when a queue starts; true once it drains. The finished counts
        /// cover the whole run, since a queue drops its finished items only when a new run
        /// starts, so items added midway are counted too.
        private func drained(old: Int, new: Int) -> Bool {
            if Self.didStart(old: old, new: new) {
                requestAuthorization()
            }
            return Self.didDrain(old: old, new: new)
        }

        static func didStart(old: Int, new: Int) -> Bool {
            old == 0 && new > 0
        }

        static func didDrain(old: Int, new: Int) -> Bool {
            old > 0 && new == 0
        }

        private func requestAuthorization() {
            // Nonisolated: the callback arrives on a background queue.
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { @Sendable _, _ in }
        }

        private func notify(title: String, body: String) {
            guard !NSApp.isActive else { return }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request)
        }
    }

    @MainActor
    private func transferPreviewStore() -> StoreOf<MainTabFeature> {
        Store(initialState: MainTabFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            user: User.preview
        )) { MainTabFeature() } withDependencies: { $0.filesClient = .previewValue }
    }

    #Preview("Uploads button") {
        HStack(spacing: .space8) {
            MacUploadsActivityButton(activity: MacUploadsActivity(progress: 0.4, failedCount: 0) {})
            MacUploadsActivityButton(activity: MacUploadsActivity(progress: nil, failedCount: 2) {})
        }
        .padding(.space24)
    }

    #Preview("Ring glyph") {
        HStack(spacing: .space16) {
            MacToolbarRingGlyph(glyph: IconKit.transfers, progress: 0.65, hasFailures: false)
            MacToolbarRingGlyph(glyph: IconKit.transfers, progress: nil, hasFailures: true)
            MacToolbarRingGlyph(glyph: IconKit.upload, progress: nil, hasFailures: false)
        }
        .padding(.space24)
    }

    #Preview("Activity button") {
        MacTransferActivityButton(store: transferPreviewStore())
            .padding(.space24)
    }

    #Preview("Notifications") {
        Text(verbatim: "Finished transfers notify while the app is in the background")
            .padding(.space24)
            .modifier(MacTransferNotifications(
                uploadsRemaining: 0, uploadsCompleted: 0, uploadsFailed: 0,
                downloadsRemaining: 0, downloadsSaved: 0, downloadsFailed: 0
            ))
    }
#endif
