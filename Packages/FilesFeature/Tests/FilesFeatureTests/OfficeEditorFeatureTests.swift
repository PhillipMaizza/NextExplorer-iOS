import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation
import Localization
import Testing

@testable import FilesFeature

@MainActor
@Suite
struct OfficeEditorFeatureTests {
    private let serverURL = URL(string: "https://files.example.com")!
    private let doc = FileItem(name: "Q3.docx", path: "Docs", dateModified: Date(), size: 10, kind: "docx")

    @Test
    func onlyOfficeLoadsAConfigAndBecomesReady() async {
        let launch = OnlyOfficeLaunch(
            documentServerURL: URL(string: "https://office.example.com")!,
            configJSON: Data(#"{"token":"x"}"#.utf8)
        )
        let store = TestStore(
            initialState: OfficeEditorFeature.State(serverURL: serverURL, item: doc, editor: .onlyOffice, mode: .edit)
        ) {
            OfficeEditorFeature()
        } withDependencies: {
            $0.filesClient.fetchOnlyOfficeConfig = { url, path, mode in
                #expect(path == "Docs/Q3.docx")
                #expect(mode == .edit)
                #expect(url == self.serverURL)
                return launch
            }
        }

        await store.send(.onAppear)
        await store.receive(\.configResponse.success) {
            $0.phase = .onlyOffice(
                documentServerURL: URL(string: "https://office.example.com")!,
                configJSON: Data(#"{"token":"x"}"#.utf8)
            )
        }
    }

    @Test
    func collaboraLoadsAnIframeURL() async {
        let url = URL(string: "https://collabora.example.com/browser/x/cool.html?WOPISrc=y&access_token=z")!
        let store = TestStore(
            initialState: OfficeEditorFeature.State(serverURL: serverURL, item: doc, editor: .collabora, mode: .edit)
        ) {
            OfficeEditorFeature()
        } withDependencies: {
            $0.filesClient.fetchCollaboraConfig = { _, _, _ in CollaboraLaunch(url: url) }
        }

        await store.send(.onAppear)
        await store.receive(\.configResponse.success) {
            $0.phase = .collabora(url: url)
        }
    }

    @Test
    func aConfigFailureShowsAMessageWithRetry() async {
        let store = TestStore(
            initialState: OfficeEditorFeature.State(serverURL: serverURL, item: doc, editor: .onlyOffice, mode: .edit)
        ) {
            OfficeEditorFeature()
        } withDependencies: {
            $0.filesClient.fetchOnlyOfficeConfig = { _, _, _ in
                throw FilesClientError.serverMessage(statusCode: 400, message: "PUBLIC_URL is required.")
            }
        }

        await store.send(.onAppear)
        await store.receive(\.configResponse.failure) {
            $0.phase = .failed("PUBLIC_URL is required.")
        }
    }

    @Test
    func retryReloads() async {
        let calls = LockIsolated(0)
        let store = TestStore(
            initialState: OfficeEditorFeature.State(serverURL: serverURL, item: doc, editor: .collabora, mode: .view)
        ) {
            OfficeEditorFeature()
        } withDependencies: {
            $0.filesClient.fetchCollaboraConfig = { _, _, _ in
                calls.withValue { $0 += 1 }
                throw FilesClientError.network("offline")
            }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)
        await store.receive(\.configResponse.failure)
        await store.send(.retryTapped)
        await store.receive(\.configResponse.failure)
        #expect(calls.value == 2)
    }

    @Test
    func doneInEditModeTellsTheParentToRefetch() async {
        let store = TestStore(
            initialState: OfficeEditorFeature.State(serverURL: serverURL, item: doc, editor: .onlyOffice, mode: .edit)
        ) {
            OfficeEditorFeature()
        }
        store.exhaustivity = .off

        await store.send(.doneTapped)
        await store.receive(.delegate(.closed(didEdit: true)))
    }

    @Test
    func doneInViewModeDoesNotAskForARefetch() async {
        let store = TestStore(
            initialState: OfficeEditorFeature.State(serverURL: serverURL, item: doc, editor: .collabora, mode: .view)
        ) {
            OfficeEditorFeature()
        }
        store.exhaustivity = .off

        await store.send(.doneTapped)
        await store.receive(.delegate(.closed(didEdit: false)))
    }
}
