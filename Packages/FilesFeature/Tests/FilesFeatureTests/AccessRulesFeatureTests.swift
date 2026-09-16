import ComposableArchitecture
import CoreModels
import FilesClient
@testable import FilesFeature
import Foundation
import Testing

@MainActor
struct AccessRulesFeatureTests {
    private let serverURL = URL(string: "https://files.example.com")!

    private func rule(_ id: String, _ path: String, _ permission: AccessRule.Permission = .readOnly) -> AccessRule {
        AccessRule(id: id, path: path, isRecursive: true, permission: permission)
    }

    @Test
    func onAppearSeedsDraftsFromTheServer() async {
        let rules = [rule("1", "Docs"), rule("2", "Private", .hidden)]
        let store = TestStore(initialState: AccessRulesFeature.State(serverURL: serverURL)) {
            AccessRulesFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in
                SystemSettings(thumbnails: ThumbnailSettings(), accessRules: rules)
            }
        }

        await store.send(.onAppear) { $0.phase = .loading }
        await store.receive(\.settingsResponse.success) {
            $0.phase = .loaded
            $0.loaded = rules
            $0.drafts = IdentifiedArray(uniqueElements: rules)
        }
        #expect(!store.state.isDirty)
    }

    @Test
    func addEditAndRemoveMutateTheDraftsAndDirtyState() async {
        var state = AccessRulesFeature.State(serverURL: serverURL)
        state.loaded = []
        let store = TestStore(initialState: state) {
            AccessRulesFeature()
        } withDependencies: {
            $0.uuid = .incrementing
        }

        await store.send(.addRuleTapped) {
            $0.drafts = [AccessRule(id: "00000000-0000-0000-0000-000000000000", path: "", isRecursive: true, permission: .readOnly)]
        }
        #expect(store.state.isDirty)

        let id = store.state.drafts[0].id
        await store.send(.pathChanged(id: id, "Reports")) { $0.drafts[id: id]?.path = "Reports" }
        await store.send(.recursiveToggled(id: id, false)) { $0.drafts[id: id]?.isRecursive = false }
        await store.send(.permissionChanged(id: id, .hidden)) { $0.drafts[id: id]?.permission = .hidden }
        await store.send(.removeRule(id: id)) { $0.drafts = [] }
    }

    @Test
    func saveTrimsEmptyPathRowsAndSendsTheRest() async {
        let sent = LockIsolated<[AccessRule]?>(nil)
        var state = AccessRulesFeature.State(serverURL: serverURL)
        state.loaded = []
        state.drafts = [
            AccessRule(id: "a", path: "  Reports  ", isRecursive: true, permission: .readOnly),
            AccessRule(id: "b", path: "   ", isRecursive: true, permission: .readWrite),
        ]
        let echoed = [AccessRule(id: "srv-a", path: "Reports", isRecursive: true, permission: .readOnly)]
        let store = TestStore(initialState: state) {
            AccessRulesFeature()
        } withDependencies: {
            $0.filesClient.updateAccessRules = { _, rules in
                sent.setValue(rules)
                return echoed
            }
        }
        store.exhaustivity = .off

        await store.send(.saveTapped) { $0.isSaving = true }
        await store.receive(\.saveResponse.success) {
            $0.isSaving = false
            $0.loaded = echoed
            $0.drafts = IdentifiedArray(uniqueElements: echoed)
        }
        await store.receive(\.delegate)
        #expect(sent.value?.map(\.path) == ["Reports"])
    }

    @Test
    func aSaveFailureSurfacesTheMessage() async {
        var state = AccessRulesFeature.State(serverURL: serverURL)
        state.loaded = []
        state.drafts = [rule("a", "Reports")]
        let store = TestStore(initialState: state) {
            AccessRulesFeature()
        } withDependencies: {
            $0.filesClient.updateAccessRules = { _, _ in
                throw FilesClientError.serverMessage(statusCode: 403, message: "Admin access required for system settings.")
            }
        }
        store.exhaustivity = .off

        await store.send(.saveTapped)
        await store.receive(\.saveResponse.failure) {
            $0.isSaving = false
            $0.errorMessage = "Admin access required for system settings."
        }
    }

    @Test
    func aNonAdminResponseMarksTheScreenUnavailable() async {
        let store = TestStore(initialState: AccessRulesFeature.State(serverURL: serverURL)) {
            AccessRulesFeature()
        } withDependencies: {
            $0.filesClient.fetchSystemSettings = { _ in SystemSettings() }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.settingsResponse.success) {
            $0.isUnavailable = true
        }
    }
}
