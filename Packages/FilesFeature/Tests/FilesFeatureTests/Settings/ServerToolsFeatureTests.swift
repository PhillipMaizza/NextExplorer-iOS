import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct ServerToolsFeatureTests {
    private let tools = [
        ServerCapability(name: "ffmpeg", isAvailable: true, version: "7.1", installPackage: "ffmpeg"),
        ServerCapability(name: "rsync", isAvailable: false, isUsed: false),
    ]
    private let ripgrep = ServerCapability(name: "ripgrep", isAvailable: false, installPackage: "ripgrep")
    private let archive = ServerCapability(
        name: "7-Zip", isAvailable: true, version: "24.08", missingFormats: ["rar", "7z"]
    )

    @Test
    func theToolsLoadOnceAndStayOnTheNextAppearance() async {
        let tools = tools
        let calls = LockIsolated(0)
        let store = TestStore(initialState: ServerToolsFeature.State(serverURL: SettingsTestSupport.serverURL)) {
            ServerToolsFeature()
        } withDependencies: {
            $0.filesClient.fetchCapabilities = { _ in
                calls.withValue { $0 += 1 }
                return tools
            }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse) {
            $0.tools = tools
            $0.phase = .loaded
        }
        await store.send(.onAppear)

        #expect(calls.value == 1)
    }

    @Test
    func aFailedLoadShowsTheErrorAndReloadsOnTheNextAppearance() async {
        let tools = tools
        let attempts = LockIsolated(0)
        let store = TestStore(initialState: ServerToolsFeature.State(serverURL: SettingsTestSupport.serverURL)) {
            ServerToolsFeature()
        } withDependencies: {
            $0.filesClient.fetchCapabilities = { _ in
                let attempt = attempts.withValue { value -> Int in
                    value += 1
                    return value
                }
                if attempt == 1 {
                    throw FilesClientError.forbidden(message: nil)
                }
                return tools
            }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse) { $0.phase = .failed(FilesClientError.forbidden(message: nil).userMessage) }
        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse) {
            $0.tools = tools
            $0.phase = .loaded
        }
    }

    @Test
    func theToolsListMissingFirstThenInstalledThenNotUsedEachByName() async {
        let unsorted = [tools[1], tools[0], ripgrep, archive]
        let store = TestStore(initialState: ServerToolsFeature.State(serverURL: SettingsTestSupport.serverURL)) {
            ServerToolsFeature()
        } withDependencies: {
            $0.filesClient.fetchCapabilities = { _ in unsorted }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.loadResponse) {
            $0.tools = [ripgrep, archive, tools[0], tools[1]]
            $0.phase = .loaded
        }
    }

    @Test
    func theRowsSayInstalledMissingOrNotUsedAndWhatToInstall() {
        #expect(tools[0].status == .installed && tools[0].detail == "7.1")
        #expect(ripgrep.status == .missing && ripgrep.detail?.contains("ripgrep") == true)
        #expect(tools[1].status == .notUsed && tools[1].detail == nil)
        #expect(archive.detail?.contains("rar, 7z") == true)
    }
}
