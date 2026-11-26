#if os(macOS)
    import ComposableArchitecture
    @testable import FilesFeature
    import Foundation
    import Localization
    import Testing

    @Suite(.isolatedDependencies)
    @MainActor
    struct MacDownloadActivityTests: MainTabTestSupport {
        private func activity(_ configure: (inout OfflineDownloadProgress) -> Void) -> MacDownloadActivity {
            let state = makeState { $0.$offlineProgress.withLock(configure) }
            let store = Store(initialState: state) { MainTabFeature() }
            return MacDownloadActivity(store: store, locale: Locale(identifier: "en_US"))
        }

        @Test("A downloading offline run is one active row with its file count")
        func downloadingRunIsAnActiveRow() {
            let activity = activity {
                $0.phase = .downloading
                $0.filesTotal = 4
                $0.filesDone = 1
                $0.unitsDone = 1
            }

            #expect(activity.isActive)
            #expect(activity.offlineRow?.id == MacDownloadActivity.offlineRowID)
            #expect(activity.offlineRow?.subtitle == L10n.Offline.progressCount(2, 4))
            #expect(activity.offlineRow?.status == .running(progress: 0.25, detail: nil))
            #expect(activity.fraction == 0.25)
        }

        @Test("Preparing shows an indeterminate row with no file count")
        func preparingIsIndeterminate() {
            let activity = activity { $0.phase = .preparing }

            #expect(activity.isActive)
            #expect(activity.offlineRow?.status == .running(progress: nil, detail: nil))
            #expect(activity.offlineRow?.subtitle == nil)
        }

        @Test("A failed run stays as a failed row and counts as a failure, not activity")
        func failedRunIsAFailedRow() {
            let activity = activity { $0.phase = .failed("Lost connection") }

            #expect(!activity.isActive)
            #expect(activity.hasFailures)
            #expect(activity.failureTitle == "Lost connection")
            #expect(activity.offlineRow?.status == .failed("Lost connection"))
            #expect(activity.notification {} == nil)
        }

        @Test("An idle or finished run shows no row and no notification")
        func idleRunShowsNothing() {
            for phase in [OfflineDownloadProgress.Phase.idle, .completed] {
                let activity = activity { $0.phase = phase }

                #expect(!activity.isActive)
                #expect(activity.offlineRow == nil)
                #expect(activity.notification {} == nil)
            }
        }
    }
#endif
