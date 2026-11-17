import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct AccessRulesFeatureTests {
    private typealias Store = TestStoreOf<AccessRulesFeature>

    private let serverURL = SettingsTestSupport.serverURL
    private let adminOnly = FilesClientError.serverMessage(
        statusCode: 403,
        message: "Admin access required for system settings."
    )

    private func rule(_ id: String, _ path: String, _ permission: AccessRule.Permission = .readOnly) -> AccessRule {
        AccessRule(id: id, path: path, isRecursive: true, permission: permission)
    }

    private func loadedState(_ rules: [AccessRule] = [], drafts: [AccessRule]? = nil) -> AccessRulesFeature.State {
        var state = AccessRulesFeature.State(serverURL: serverURL)
        state.phase = .loaded
        state.loaded = rules
        state.drafts = IdentifiedArray(uniqueElements: drafts ?? rules)
        return state
    }

    private func makeStore(
        _ state: AccessRulesFeature.State,
        fetch: @escaping @Sendable () async throws -> SystemSettings = { throw FilesClientError.offline },
        update: @escaping @Sendable ([AccessRule]) async throws -> [AccessRule] = { _ in
            throw FilesClientError.offline
        }
    ) -> Store {
        TestStore(initialState: state) {
            AccessRulesFeature()
        } withDependencies: {
            $0.uuid = .incrementing
            $0.filesClient.fetchSystemSettings = { _ in try await fetch() }
            $0.filesClient.updateAccessRules = { _, rules in try await update(rules) }
        }
    }

    @Test
    func onAppearSeedsDraftsFromTheServer() async {
        let rules = [rule("1", TestFolder.docs), rule("2", "Private", .hidden)]
        let store = makeStore(
            AccessRulesFeature.State(serverURL: serverURL),
            fetch: { SystemSettings(thumbnails: ThumbnailSettings(), accessRules: rules) }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.success) {
            $0.phase = .loaded
            $0.loaded = rules
            $0.drafts = IdentifiedArray(uniqueElements: rules)
        }
        #expect(!store.state.isDirty)
    }

    @Test
    func aLoadFailureShowsTheServerMessage() async {
        let failure = adminOnly
        let store = makeStore(AccessRulesFeature.State(serverURL: serverURL), fetch: { throw failure })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.failure) {
            $0.phase = .failed("Admin access required for system settings.")
        }
    }

    @Test
    func aServerAnswerWithDuplicateIdsKeepsTheFirstOfEach() async {
        let first = rule("1", TestFolder.docs)
        let duplicate = rule("1", "Other", .hidden)
        let store = makeStore(
            AccessRulesFeature.State(serverURL: serverURL),
            fetch: { SystemSettings(thumbnails: ThumbnailSettings(), accessRules: [first, duplicate]) }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.success) {
            $0.phase = .loaded
            $0.loaded = [first, duplicate]
            $0.drafts = [first]
        }
    }

    @Test
    func aReloadWhileEditingUpdatesTheBaselineButKeepsTheDrafts() async {
        let original = rule("1", TestFolder.docs)
        var edited = original
        edited.path = "Docs/Edited"
        let refreshed = rule("1", "Docs/Server")
        let store = makeStore(
            loadedState([original], drafts: [edited]),
            fetch: { SystemSettings(thumbnails: ThumbnailSettings(), accessRules: [refreshed]) }
        )

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.success) {
            $0.phase = .loaded
            $0.loaded = [refreshed]
        }
        #expect(store.state.drafts == [edited])
    }

    @Test
    func addEditAndRemoveMutateTheDraftsAndDirtyState() async {
        let store = makeStore(loadedState())
        let id = "00000000-0000-0000-0000-000000000000"

        await store.send(.addRuleTapped) {
            $0.drafts = [AccessRule(id: id, path: "", isRecursive: true, permission: .readOnly)]
        }
        #expect(store.state.isDirty)
        await store.send(.pathChanged(id: id, "Reports")) { $0.drafts[id: id]?.path = "Reports" }
        await store.send(.recursiveToggled(id: id, false)) { $0.drafts[id: id]?.isRecursive = false }
        await store.send(.permissionChanged(id: id, .hidden)) { $0.drafts[id: id]?.permission = .hidden }
        await store.send(.removeRule(id: id)) { $0.drafts = [] }
        #expect(!store.state.isDirty)
    }

    @Test
    func editingClearsAShownSaveError() async {
        var state = loadedState([rule("1", TestFolder.docs)])
        state.errorMessage = TestValue.outdated
        let store = makeStore(state)

        await store.send(.pathChanged(id: "1", "Docs2")) {
            $0.drafts[id: "1"]?.path = "Docs2"
            $0.errorMessage = nil
        }
    }

    @Test
    func saveTrimsEmptyPathRowsAndSendsTheRest() async {
        let sent = LockIsolated<[[AccessRule]]>([])
        let echoed = [rule("srv-a", "Reports")]
        let store = makeStore(
            loadedState(drafts: [
                AccessRule(id: "a", path: "  Reports  ", isRecursive: true, permission: .readOnly),
                AccessRule(id: "b", path: TestValue.blank, isRecursive: true, permission: .readWrite),
            ]),
            update: { rules in
                sent.withValue { $0.append(rules) }
                return echoed
            }
        )

        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) {
            $0.isSaving = false
            $0.loaded = echoed
            $0.drafts = IdentifiedArray(uniqueElements: echoed)
        }
        await store.receive(.delegate(.saved))
        #expect(sent.value == [[AccessRule(id: "a", path: "Reports", isRecursive: true, permission: .readOnly)]])
    }

    @Test
    func aSaveFailureSurfacesTheMessageAndKeepsTheDrafts() async {
        let failure = adminOnly
        let store = makeStore(loadedState(drafts: [rule("a", "Reports")]), update: { _ in throw failure })

        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.failure) {
            $0.isSaving = false
            $0.errorMessage = "Admin access required for system settings."
        }
        #expect(store.state.drafts == [rule("a", "Reports")])
    }

    @Test
    func savingWithoutChangesDoesNothing() async {
        let calls = LockIsolated(0)
        let store = makeStore(loadedState([rule("1", TestFolder.docs)]), update: { rules in
            calls.withValue { $0 += 1 }
            return rules
        })

        await store.send(.saveTapped)
        #expect(calls.value == 0)
    }

    @Test
    func aNonAdminResponseMarksTheScreenUnavailable() async {
        let store = makeStore(AccessRulesFeature.State(serverURL: serverURL), fetch: { SystemSettings() })

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.success) {
            $0.phase = .loaded
            $0.isUnavailable = true
        }
    }
}
