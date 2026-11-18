import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Localization
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct FFmpegSettingsFeatureTests {
    private typealias Store = TestStoreOf<FFmpegSettingsFeature>

    private let serverURL = SettingsTestSupport.serverURL
    private let fetchedURLs = LockIsolated<[URL]>([])
    private let patches = LockIsolated<[SystemSettingsPatch]>([])

    private func store(
        state: FFmpegSettingsFeature.State? = nil,
        settings: @escaping @Sendable () throws -> SystemSettings = { SystemSettings(ffmpeg: FFmpegSettings()) },
        update: @escaping @Sendable (SystemSettingsPatch) throws -> SystemSettings = { _ in SystemSettings() }
    ) -> Store {
        let fetchedURLs = fetchedURLs
        let patches = patches
        return TestStore(initialState: state ?? FFmpegSettingsFeature.State(serverURL: serverURL)) {
            FFmpegSettingsFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { url in
                fetchedURLs.withValue { $0.append(url) }
                return try settings()
            }
            $0.filesClient.updateSystemSettings = { _, patch in
                patches.withValue { $0.append(patch) }
                return try update(patch)
            }
        }
    }

    private func loadedState(_ ffmpeg: FFmpegSettings = FFmpegSettings()) -> FFmpegSettingsFeature.State {
        var state = FFmpegSettingsFeature.State(serverURL: serverURL)
        state.loaded = ffmpeg
        state.draft = ffmpeg
        state.phase = .loaded
        return state
    }

    // MARK: Loading

    @Test
    func loadingSeedsTheDraft() async {
        let ffmpeg = FFmpegSettings(ffmpegPath: Constants.ffmpegPath, ffprobePath: "/usr/bin/ffprobe")
        let store = store(settings: { SystemSettings(ffmpeg: ffmpeg) })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.loaded = ffmpeg
            $0.draft = ffmpeg
        }

        #expect(!store.state.isDirty)
        #expect(fetchedURLs.value == [serverURL])
    }

    @Test
    func aNonAdminResponseIsUnavailable() async {
        let store = store(settings: { SystemSettings() })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.success) {
            $0.phase = .loaded
            $0.isUnavailable = true
        }
    }

    @Test
    func aLoadFailureIsTheFailedPhase() async {
        let store = store(settings: { throw FilesClientError.offline })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse.failure) { $0.phase = .failed(L10n.Error.offline) }
    }

    @Test
    func aReloadFailureKeepsTheFormAndShowsTheMessage() async {
        let store = store(
            state: loadedState(FFmpegSettings(ffmpegPath: "/a")),
            settings: { throw FilesClientError.timedOut }
        )

        await store.send(.onAppear)
        await store.receive(\.loadResponse.failure) { $0.errorMessage = L10n.Error.timedOut }
    }

    @Test
    func reloadingKeepsAnEditInProgress() async {
        var state = loadedState()
        state.draft.ffmpegPath = "/typed"
        let store = store(state: state, settings: { SystemSettings(ffmpeg: FFmpegSettings(ffprobePath: "/server")) })

        await store.send(.onAppear)
        await store.receive(\.loadResponse.success) {
            $0.loaded = FFmpegSettings(ffprobePath: "/server")
        }

        #expect(store.state.draft == FFmpegSettings(ffmpegPath: "/typed"))
    }

    @Test
    func nothingReloadsWhileASaveIsInFlight() async {
        var state = loadedState()
        state.isSaving = true
        let store = store(state: state)

        await store.send(.onAppear)
        await store.send(.loadResponse(.success(SystemSettings(ffmpeg: FFmpegSettings(ffmpegPath: "/stale")))))

        #expect(fetchedURLs.value.isEmpty)
    }

    // MARK: Typing

    @Test
    func pathsAreKeptAsTypedAndTrimmedWhenSent() async {
        let store = store(state: loadedState())

        await store.send(.ffmpegPathChanged("  /usr/bin/ffmpeg ")) { $0.draft.ffmpegPath = "  /usr/bin/ffmpeg " }
        await store.send(.ffprobePathChanged("\t/usr/bin/ffprobe")) { $0.draft.ffprobePath = "\t/usr/bin/ffprobe" }

        #expect(store.state.trimmedDraft == FFmpegSettings(
            ffmpegPath: Constants.ffmpegPath,
            ffprobePath: "/usr/bin/ffprobe"
        ))
    }

    @Test
    func aSpaceInTheMiddleOfAPathSurvivesTypingAndTrimming() async {
        let store = store(state: loadedState())

        await store.send(.ffmpegPathChanged("/opt/my ")) { $0.draft.ffmpegPath = "/opt/my " }
        await store.send(.ffmpegPathChanged("/opt/my tools/ffmpeg ")) { $0.draft.ffmpegPath = "/opt/my tools/ffmpeg " }

        #expect(store.state.trimmedDraft.ffmpegPath == "/opt/my tools/ffmpeg")
        #expect(store.state.isValid)
    }

    @Test
    func typingClearsAShownError() async {
        var state = loadedState()
        state.errorMessage = "Both paths must be absolute."
        let store = store(state: state)

        await store.send(.ffprobePathChanged("/p")) {
            $0.draft.ffprobePath = "/p"
            $0.errorMessage = nil
        }
    }

    @Test(arguments: ["ffmpeg", "bin/ffmpeg", "./ffmpeg"])
    func aRelativePathIsInvalidAndCannotBeSaved(path: String) async {
        let store = store(state: loadedState())

        await store.send(.ffmpegPathChanged(path)) { $0.draft.ffmpegPath = path }
        await store.send(.saveTapped)

        #expect(!store.state.isValid)
        #expect(!store.state.isSaveEnabled)
        #expect(patches.value.isEmpty)
    }

    @Test
    func emptyPathsAreValidSoAnOverrideCanBeCleared() async {
        let store = store(state: loadedState(FFmpegSettings(ffmpegPath: Constants.ffmpegPath)))

        await store.send(.ffmpegPathChanged("")) { $0.draft.ffmpegPath = "" }

        #expect(store.state.isValid)
        #expect(store.state.isSaveEnabled)
    }

    // MARK: Saving

    @Test
    func savingSendsOnlyTheChangedPathAndAdoptsTheEcho() async {
        let echoed = FFmpegSettings(ffmpegPath: "/opt/ffmpeg", ffprobePath: "")
        let store = store(state: loadedState(), update: { _ in SystemSettings(ffmpeg: echoed) })

        await store.send(.ffmpegPathChanged("/opt/ffmpeg")) { $0.draft.ffmpegPath = "/opt/ffmpeg" }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) {
            $0.isSaving = false
            $0.loaded = echoed
            $0.draft = echoed
        }
        await store.receive(.delegate(.saved))

        #expect(patches.value.map(\.ffmpeg) == [SystemSettingsPatch.FFmpegPatch(ffmpegPath: "/opt/ffmpeg")])
        #expect(patches.value.map(\.uploads) == [nil])
        #expect(!store.state.isDirty)
    }

    @Test
    func savingIsOffUntilSomethingChanges() async {
        let store = store(state: loadedState(FFmpegSettings(ffmpegPath: "/a")))

        await store.send(.saveTapped)

        #expect(!store.state.isSaveEnabled)
        #expect(patches.value.isEmpty)
    }

    @Test
    func aFailedSaveKeepsTheDraftAndShowsTheMessage() async {
        let store = store(state: loadedState(), update: { _ in
            throw FilesClientError.serverMessage(statusCode: 400, message: "Both paths must be absolute.")
        })

        await store.send(.ffmpegPathChanged("/a")) { $0.draft.ffmpegPath = "/a" }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.failure) {
            $0.isSaving = false
            $0.errorMessage = "Both paths must be absolute."
        }

        #expect(store.state.isDirty)
    }

    @Test
    func anEchoWithoutFFmpegIsAFailedSave() async {
        let store = store(state: loadedState(), update: { _ in SystemSettings() })

        await store.send(.ffmpegPathChanged("/a")) { $0.draft.ffmpegPath = "/a" }
        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.failure) {
            $0.isSaving = false
            $0.errorMessage = L10n.Error.decoding
        }
    }

    // MARK: Derived state

    struct TrimCase: Sendable {
        let draft: FFmpegSettings
        let trimmed: FFmpegSettings
    }

    @Test(arguments: [
        TrimCase(
            draft: FFmpegSettings(ffmpegPath: "  /usr/bin/ffmpeg ", ffprobePath: ""),
            trimmed: FFmpegSettings(ffmpegPath: Constants.ffmpegPath, ffprobePath: "")
        ),
        TrimCase(
            draft: FFmpegSettings(ffmpegPath: "/a", ffprobePath: "\t/b\t"),
            trimmed: FFmpegSettings(ffmpegPath: "/a", ffprobePath: "/b")
        ),
        TrimCase(
            draft: FFmpegSettings(ffmpegPath: " /opt/my tools/ffmpeg", ffprobePath: ""),
            trimmed: FFmpegSettings(ffmpegPath: "/opt/my tools/ffmpeg", ffprobePath: "")
        ),
    ])
    func spacesAroundAPathAreTrimmedOnlyWhenItIsSent(_ testCase: TrimCase) {
        var state = loadedState()
        state.draft = testCase.draft

        #expect(state.trimmedDraft == testCase.trimmed)
        #expect(state.isDirty)
        #expect(state.isSaveEnabled)
    }

    struct PatchCase: Sendable {
        let loaded: FFmpegSettings
        let draft: FFmpegSettings
        let patch: SystemSettingsPatch.FFmpegPatch
    }

    @Test(arguments: [
        PatchCase(
            loaded: FFmpegSettings(ffmpegPath: "/gone/ffmpeg", ffprobePath: "/usr/bin/ffprobe"),
            draft: FFmpegSettings(ffmpegPath: "/gone/ffmpeg", ffprobePath: "/opt/ffprobe"),
            patch: SystemSettingsPatch.FFmpegPatch(ffprobePath: "/opt/ffprobe")
        ),
        PatchCase(
            loaded: FFmpegSettings(ffmpegPath: Constants.ffmpegPath, ffprobePath: ""),
            draft: FFmpegSettings(ffmpegPath: "", ffprobePath: ""),
            patch: SystemSettingsPatch.FFmpegPatch(ffmpegPath: "")
        ),
    ])
    func onlyTheChangedPathIsSent(_ testCase: PatchCase) {
        var state = loadedState(testCase.loaded)
        state.draft = testCase.draft

        #expect(state.patch == testCase.patch)
    }
}

private enum Constants {
    static let ffmpegPath = "/usr/bin/ffmpeg"
}
