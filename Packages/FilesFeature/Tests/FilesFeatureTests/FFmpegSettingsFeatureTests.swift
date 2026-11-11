import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct FFmpegSettingsFeatureTests {
    private let serverURL = URL(string: "https://files.example.com")!

    private func store(
        state: FFmpegSettingsFeature.State? = nil,
        settings: @escaping @Sendable () throws -> SystemSettings = { SystemSettings(ffmpeg: FFmpegSettings()) },
        update: @escaping @Sendable (SystemSettingsPatch) throws -> SystemSettings = { _ in SystemSettings() }
    ) -> TestStoreOf<FFmpegSettingsFeature> {
        let store = TestStore(initialState: state ?? FFmpegSettingsFeature.State(serverURL: serverURL)) {
            FFmpegSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in try settings() }
            $0.filesClient.updateSystemSettings = { _, patch in try update(patch) }
        }
        store.exhaustivity = .off
        return store
    }

    private func loadedState(_ ffmpeg: FFmpegSettings = FFmpegSettings()) -> FFmpegSettingsFeature.State {
        var state = FFmpegSettingsFeature.State(serverURL: serverURL)
        state.loaded = ffmpeg
        state.draft = ffmpeg
        state.phase = .loaded
        return state
    }

    @Test
    func loadingSeedsTheDraft() async {
        let ffmpeg = FFmpegSettings(ffmpegPath: "/usr/bin/ffmpeg", ffprobePath: "/usr/bin/ffprobe")
        let store = store(settings: { SystemSettings(ffmpeg: ffmpeg) })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.loaded == ffmpeg)
        #expect(store.state.draft == ffmpeg)
        #expect(!store.state.isDirty)
    }

    @Test
    func aNonAdminResponseIsUnavailable() async {
        let store = store(settings: { SystemSettings() })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.isUnavailable)
    }

    @Test
    func aLoadFailureIsTheFailedPhase() async {
        let store = store(settings: { throw FilesClientError.offline })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.phase.errorMessage != nil)
    }

    @Test
    func reloadingKeepsAnEditInProgress() async {
        var state = loadedState()
        state.draft.ffmpegPath = "/typed"
        let store = store(state: state, settings: { SystemSettings(ffmpeg: FFmpegSettings(ffprobePath: "/server")) })

        await store.send(.onAppear)
        await store.skipReceivedActions()

        #expect(store.state.draft.ffmpegPath == "/typed")
        #expect(store.state.loaded?.ffprobePath == "/server")
    }

    @Test
    func pathsAreKeptAsTypedAndTrimmedWhenSent() async {
        let store = store(state: loadedState())

        await store.send(.ffmpegPathChanged("  /usr/bin/ffmpeg "))
        await store.send(.ffprobePathChanged("\t/usr/bin/ffprobe"))

        #expect(store.state.draft.ffmpegPath == "  /usr/bin/ffmpeg ")
        #expect(store.state.trimmedDraft == FFmpegSettings(ffmpegPath: "/usr/bin/ffmpeg", ffprobePath: "/usr/bin/ffprobe"))
    }

    @Test(arguments: ["ffmpeg", "bin/ffmpeg", "./ffmpeg"])
    func aRelativePathIsInvalidAndCannotBeSaved(path: String) async {
        let store = store(state: loadedState())

        await store.send(.ffmpegPathChanged(path))
        await store.send(.saveTapped)

        #expect(!store.state.isValid)
        #expect(!store.state.isSaveEnabled)
        #expect(!store.state.isSaving)
    }

    @Test
    func emptyPathsAreValidSoAnOverrideCanBeCleared() async {
        let store = store(state: loadedState(FFmpegSettings(ffmpegPath: "/usr/bin/ffmpeg")))

        await store.send(.ffmpegPathChanged(""))

        #expect(store.state.isValid)
        #expect(store.state.isSaveEnabled)
    }

    @Test
    func savingSendsOnlyTheChangedPathAndAdoptsTheEcho() async {
        let sent = LockIsolated<SystemSettingsPatch?>(nil)
        let echoed = FFmpegSettings(ffmpegPath: "/opt/ffmpeg", ffprobePath: "")
        let store = store(state: loadedState(), update: { patch in
            sent.setValue(patch)
            return SystemSettings(ffmpeg: echoed)
        })

        await store.send(.ffmpegPathChanged("/opt/ffmpeg"))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(sent.value?.ffmpeg == SystemSettingsPatch.FFmpegPatch(ffmpegPath: "/opt/ffmpeg"))
        #expect(sent.value?.uploads == nil)
        #expect(store.state.loaded == echoed)
        #expect(!store.state.isDirty)
        #expect(!store.state.isSaving)
    }

    @Test
    func savingIsOffUntilSomethingChanges() async {
        let store = store(state: loadedState(FFmpegSettings(ffmpegPath: "/a")))

        await store.send(.saveTapped)

        #expect(!store.state.isSaveEnabled)
        #expect(!store.state.isSaving)
    }

    @Test
    func aFailedSaveKeepsTheDraftAndShowsTheMessage() async {
        let store = store(state: loadedState(), update: { _ in throw FilesClientError.serverMessage(statusCode: 400, message: "Both paths must be absolute.") })

        await store.send(.ffmpegPathChanged("/a"))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(store.state.errorMessage == "Both paths must be absolute.")
        #expect(store.state.draft.ffmpegPath == "/a")
        #expect(store.state.isDirty)
    }

    @Test
    func anEchoWithoutFFmpegIsAFailedSave() async {
        let store = store(state: loadedState(), update: { _ in SystemSettings() })

        await store.send(.ffmpegPathChanged("/a"))
        await store.send(.saveTapped)
        await store.skipReceivedActions()

        #expect(store.state.errorMessage != nil)
        #expect(!store.state.isSaving)
    }

    // MARK: Typing

    @Test
    func aSpaceInTheMiddleOfAPathIsKept() async {
        var state = FFmpegSettingsFeature.State(serverURL: URL(string: "https://files.example.com")!)
        state.loaded = FFmpegSettings()
        state.phase = .loaded
        let store = TestStore(initialState: state) { FFmpegSettingsFeature() }
        store.exhaustivity = .off

        await store.send(.ffmpegPathChanged("/opt/my "))
        await store.send(.ffmpegPathChanged("/opt/my tools/ffmpeg"))

        #expect(store.state.draft.ffmpegPath == "/opt/my tools/ffmpeg")
        #expect(store.state.isValid)
    }

    @Test
    func spacesAroundAPathAreTrimmedOnlyWhenItIsSent() {
        var state = FFmpegSettingsFeature.State(serverURL: URL(string: "https://files.example.com")!)
        state.loaded = FFmpegSettings()
        state.phase = .loaded
        state.draft = FFmpegSettings(ffmpegPath: "  /usr/bin/ffmpeg ", ffprobePath: "")

        #expect(state.trimmedDraft == FFmpegSettings(ffmpegPath: "/usr/bin/ffmpeg", ffprobePath: ""))
        #expect(state.isDirty)
        #expect(state.isSaveEnabled)
    }

    @Test
    func onlyTheChangedPathIsSent() {
        var state = FFmpegSettingsFeature.State(serverURL: URL(string: "https://files.example.com")!)
        state.loaded = FFmpegSettings(ffmpegPath: "/gone/ffmpeg", ffprobePath: "/usr/bin/ffprobe")
        state.draft = FFmpegSettings(ffmpegPath: "/gone/ffmpeg", ffprobePath: "/opt/ffprobe")

        #expect(state.patch == SystemSettingsPatch.FFmpegPatch(ffprobePath: "/opt/ffprobe"))
    }

    @Test
    func clearingAPathSendsItAsEmpty() {
        var state = FFmpegSettingsFeature.State(serverURL: URL(string: "https://files.example.com")!)
        state.loaded = FFmpegSettings(ffmpegPath: "/usr/bin/ffmpeg", ffprobePath: "")
        state.draft = FFmpegSettings(ffmpegPath: "", ffprobePath: "")

        #expect(state.patch == SystemSettingsPatch.FFmpegPatch(ffmpegPath: ""))
    }
}
