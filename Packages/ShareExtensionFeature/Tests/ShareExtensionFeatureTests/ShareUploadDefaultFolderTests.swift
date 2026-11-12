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

/// Checking and recovering from a stale default folder. Nested in `ShareUploadFeatureTests` so it inherits `.serialized` with every other share upload suite.
extension ShareUploadFeatureTests {
    @MainActor
    @Suite(.isolatedDependencies)
    struct ShareUploadDefaultFolderTests: ShareUploadHarness {
        private func folderGone(_ store: Store) async {
            await store.receive(\.defaultFolderChecked) {
                $0.phase = .ready
                $0.destination = ""
                $0.shouldUploadWithoutAsking = false
                $0.notice = .defaultFolderUnavailable
                $0.folderPicker = .init(serverURL: credentials.serverBaseURL, uploadStartingAt: "")
            }
        }

        @Test
        func aMissingDefaultFolderFallsBackToTheFolderPickerWithAMessage() async {
            let calls = Calls()
            let announcements = LockIsolated<[String]>([])
            let store = store(
                defaults: UploadDefaults(folderPath: Constants.missingFolder, shouldUploadWithoutAsking: true),
                calls: calls,
                browse: { _, _ in throw FilesClientError.server(statusCode: 404) },
                announcements: announcements
            )
            await startAutomatic(store, folder: Constants.missingFolder)
            await folderGone(store)
            await store.finish()
            #expect(calls.all.isEmpty, "nothing is uploaded to a folder that is gone")
            #expect(!store.state.canUpload)
            #expect(announcements.value == [L10n.ShareUpload.defaultFolderUnavailable])
        }

        @Test(arguments: [
            FilesClientError.forbidden(message: nil),
            FilesClientError.forbidden(message: "No access to this folder."),
            FilesClientError.server(statusCode: 404),
            FilesClientError.serverMessage(statusCode: 404, message: "Folder not found."),
        ])
        func aFolderTheServerDeniesOrCannotFindIsGone(error: FilesClientError) async {
            let calls = Calls()
            let store = store(
                defaults: UploadDefaults(folderPath: Constants.missingFolder, shouldUploadWithoutAsking: true),
                calls: calls,
                browse: { _, _ in throw error }
            )
            await startAutomatic(store, folder: Constants.missingFolder)
            await folderGone(store)
            await store.finish()
            #expect(calls.all.isEmpty, "\(error) must not start an upload that would fail file by file")
        }

        @Test(arguments: [
            FilesClientError.offline,
            FilesClientError.network("down"),
            FilesClientError.timedOut,
            FilesClientError.changedOnServer,
            FilesClientError.decoding("bad"),
            FilesClientError.server(statusCode: 500),
            FilesClientError.serverMessage(statusCode: 500, message: "Oops."),
            FilesClientError.rateLimited,
            FilesClientError.clientCertificateRequired,
            FilesClientError.clientCertificateRejected,
        ])
        func anErrorThatSaysNothingAboutTheFolderStillUploads(error: FilesClientError) async {
            let calls = Calls()
            let store = store(
                defaults: UploadDefaults(folderPath: TestFolder.photos, shouldUploadWithoutAsking: true),
                calls: calls,
                browse: { _, _ in throw error }
            )
            await startAutomatic(store)
            await store.receive(.defaultFolderChecked(accountID: credentials.accountID, .usable)) { $0.phase = .ready }
            await store.receive(\.uploadTapped) {
                $0.phase = .preparing
                $0.preparingTotal = 3
            }
            await store.receive(\.preparationFinished) {
                $0.stagedCount = 3
                $0.phase = .handingOff
            }
            await store.receive(\.uploadResponse.success) { $0.phase = .started }
            await store.send(.viewDisappeared)
            #expect(calls.all == ["prepare", "start"])
        }

        @Test
        func aDefaultFolderTheAccountCanNoLongerUploadToIsTreatedAsGone() async {
            let store = store(
                defaults: UploadDefaults(folderPath: Constants.readOnlyFolder, shouldUploadWithoutAsking: true),
                browse: { _, _ in Self.listing(canUpload: false) }
            )
            await startAutomatic(store, folder: Constants.readOnlyFolder)
            await folderGone(store)
            #expect(store.state.notice == .defaultFolderUnavailable)
            #expect(store.state.folderPicker != nil)
        }

        @Test
        func choosingAnotherFolderClearsTheMessageAndAllowsTheUpload() async {
            let store = store(
                defaults: UploadDefaults(folderPath: Constants.missingFolder, shouldUploadWithoutAsking: true),
                browse: { _, _ in throw FilesClientError.server(statusCode: 404) }
            )
            await startAutomatic(store, folder: Constants.missingFolder)
            await folderGone(store)

            await store.send(.folderPicker(.presented(.delegate(.confirmed(destination: TestFolder.docs))))) {
                $0.destination = TestFolder.docs
                $0.folderPicker = nil
                $0.notice = nil
            }
            #expect(store.state.canUpload)
        }

        @Test
        func theDefaultFolderIsCheckedOnceBeforeTheAutomaticUpload() async {
            let browsed = LockIsolated<[String]>([])
            let store = store(
                defaults: UploadDefaults(folderPath: TestPath.photos2026, shouldUploadWithoutAsking: true),
                browse: { _, path in
                    browsed.withValue { $0.append(path) }
                    return Self.listing()
                }
            )
            await startAutomatic(store, folder: TestPath.photos2026)
            await store.receive(\.defaultFolderChecked) { $0.phase = .ready }
            await store.receive(\.uploadTapped) {
                $0.phase = .preparing
                $0.preparingTotal = 3
            }
            await store.receive(\.preparationFinished) {
                $0.stagedCount = 3
                $0.phase = .handingOff
            }
            await store.receive(\.uploadResponse.success) { $0.phase = .started }
            await store.send(.viewDisappeared)
            #expect(browsed.value == [TestPath.photos2026])
        }

        @Test
        func anExpiredSessionFoundWhileCheckingTheDefaultFolderShowsSignedOut() async {
            let calls = Calls()
            let store = store(
                defaults: UploadDefaults(folderPath: TestFolder.photos, shouldUploadWithoutAsking: true),
                calls: calls,
                browse: { _, _ in throw FilesClientError.sessionExpired }
            )
            await startAutomatic(store)
            await store.receive(\.defaultFolderChecked) { $0.phase = .signedOut }
            #expect(calls.all.isEmpty)
        }

        @Test
        func aFolderPathIsNotCheckedWhenTheUploadWaitsForATap() async {
            let browsed = LockIsolated(0)
            let store = store(
                defaults: UploadDefaults(folderPath: TestFolder.photos),
                browse: { _, _ in
                    browsed.withValue { $0 += 1 }
                    return Self.listing()
                }
            )
            await becomeReady(store, folder: TestFolder.photos)
            await store.finish()
            #expect(browsed.value == 0)
        }
    }
}

private enum Constants {
    static let readOnlyFolder = "ReadOnly"
    static let missingFolder = "Gone"
}
