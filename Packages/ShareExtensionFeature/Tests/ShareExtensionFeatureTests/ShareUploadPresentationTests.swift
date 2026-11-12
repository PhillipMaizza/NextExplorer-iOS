import AuthClient
import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
import NetworkClient
@testable import ShareExtensionFeature
import ShareUploads
import Testing
import TestUtils

/// Opening the app, what each phase offers and accessibility announcements. Nested in `ShareUploadFeatureTests` so it inherits `.serialized` with every other share upload suite.
extension ShareUploadFeatureTests {
    @MainActor
    @Suite(.isolatedDependencies)
    struct ShareUploadPresentationTests: ShareUploadHarness {
        @Test
        func openNextExplorerAsksTheSystemToOpenTheApp() async {
            let opened = LockIsolated(0)
            var state = ShareUploadFeature.State()
            state.phase = .signedOut
            let store = TestStore(initialState: state) {
                ShareUploadFeature()
            } withDependencies: {
                $0.openApp = OpenAppClient(isAvailable: true) { opened.withValue { $0 += 1 } }
            }
            await store.send(.openAppTapped)
            await store.finish()
            #expect(opened.value == 1)
        }

        @Test(arguments: [true, false])
        func eachPhaseOffersItsOwnButtons(canOpenApp: Bool) {
            let expected: [ShareUploadFeature.Phase: (primary: ShareUploadFeature.Control?, secondary: ShareUploadFeature.Control?)] = [
                .loading: (nil, nil),
                .checking: (.upload, nil),
                .ready: (.upload, nil),
                .preparing: (.upload, nil),
                .handingOff: (.upload, nil),
                .partiallyPrepared: (.uploadReady, .retryFailed),
                .started: (nil, nil),
                .failed: (.retry, nil),
                .nothingToUpload: (nil, nil),
                .signedOut: (canOpenApp ? .openApp : nil, canOpenApp ? .retry : nil),
                .sessionUnreadable: (canOpenApp ? .openApp : nil, canOpenApp ? .retry : nil),
                .certificateRequired: (canOpenApp ? .openApp : nil, canOpenApp ? .retry : nil),
                .certificateRejected: (canOpenApp ? .openApp : nil, canOpenApp ? .retry : nil),
            ]
            #expect(expected.count == ShareUploadFeature.Phase.previewCases.count, "every phase is covered")
            for (phase, buttons) in expected {
                var state = ShareUploadFeature.State()
                state.phase = phase
                #expect(state.primaryAction(canOpenApp: canOpenApp) == buttons.primary, "primary of \(phase)")
                #expect(state.secondaryAction(canOpenApp: canOpenApp) == buttons.secondary, "secondary of \(phase)")
                #expect(state.hasActions(canOpenApp: canOpenApp) == (buttons.primary != nil || buttons.secondary != nil), "footer of \(phase)")
            }
        }

        @Test
        func theAccountIsNamedWithItsUserAndServerThroughTheLocalizedFormat() {
            #expect(ShareUploadFeature.State.name(for: .preview) == L10n.ShareUpload.accountSummary("phillip", "files.example.com"))
            var anonymous = SessionCredentials.preview
            anonymous.username = nil
            #expect(ShareUploadFeature.State.name(for: anonymous) == "files.example.com")
            anonymous.username = ""
            #expect(ShareUploadFeature.State.name(for: anonymous) == "files.example.com")
        }

        @Test
        func retryDoesNothingWhereItMakesNoSense() async {
            for phase in [ShareUploadFeature.Phase.ready, .started, .nothingToUpload, .preparing, .handingOff, .checking, .loading] {
                var state = ShareUploadFeature.State()
                state.phase = phase
                let store = TestStore(initialState: state) { ShareUploadFeature() }
                await store.send(.retryTapped)
            }
        }

        @Test
        func theResultIsAnnouncedAndTheSheetClosesAfterTheShortDelay() async {
            let announcements = LockIsolated<[String]>([])
            let clock = TestClock()
            let store = store(defaults: UploadDefaults(folderPath: "Photos"), clock: clock, announcements: announcements)
            await becomeReady(store, folder: "Photos")
            await uploadCleanly(store)

            #expect(announcements.value == [L10n.ShareUpload.started])
            await clock.advance(by: .seconds(1.5))
            await store.receive(.delegate(.close(completed: true)))
        }

        @Test
        func withVoiceOverTheSheetStaysOpenLongerThanTheShortDelay() async {
            let announcements = LockIsolated<[String]>([])
            let clock = TestClock()
            let store = store(defaults: UploadDefaults(folderPath: "Photos"), clock: clock, isAssistive: true, announcements: announcements)
            await becomeReady(store, folder: "Photos")
            await uploadCleanly(store)

            await clock.advance(by: .seconds(2))
            #expect(store.state.phase == .started, "still open after the short delay")
            await clock.advance(by: .seconds(6))
            await store.receive(.delegate(.close(completed: true)))
            #expect(announcements.value == [L10n.ShareUpload.started])
        }
    }
}
