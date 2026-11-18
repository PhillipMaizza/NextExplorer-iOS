import ComposableArchitecture
@testable import FilesFeature
import FolderPickerFeature
import Foundation
import ShareUploads
import Testing
import TestUtils

@Suite(.isolatedDependencies)
@MainActor
struct UploadDefaultsFeatureTests {
    private typealias Store = TestStoreOf<UploadDefaultsFeature>

    private enum Constants {
        static let accountID = "https://files.example.com|alice"
        static let otherAccountID = "https://files.example.com|bob"
        static let uploadFolder = "Inbox/Shared"
    }

    private struct Saved: Equatable {
        let accountID: String
        let defaults: UploadDefaults
    }

    private let saves = LockIsolated<[Saved]>([])

    private func store(stored: [String: UploadDefaults] = [:], defaults: UploadDefaults = UploadDefaults()) -> Store {
        let saves = saves
        var state = UploadDefaultsFeature.State(serverURL: TestHost.serverURL, accountID: Constants.accountID)
        state.defaults = defaults
        return TestStore(initialState: state) {
            UploadDefaultsFeature()
        } withDependencies: {
            $0.uploadDefaults.load = { stored[$0] ?? UploadDefaults() }
            $0.uploadDefaults.save = { accountID, defaults in
                saves.withValue { $0.append(Saved(accountID: accountID, defaults: defaults)) }
            }
        }
    }

    private func pickerState(startingAt path: String) -> DestinationPickerFeature.State {
        DestinationPickerFeature.State(serverURL: TestHost.serverURL, uploadStartingAt: path)
    }

    @Test
    func appearingLoadsOnlyTheSignedInAccountsDefaults() async {
        let mine = UploadDefaults(folderPath: Constants.uploadFolder, shouldUploadWithoutAsking: true)
        let store = store(stored: [
            Constants.accountID: mine,
            Constants.otherAccountID: UploadDefaults(folderPath: TestFolder.photos),
        ])

        await store.send(.onAppear) { $0.defaults = mine }

        #expect(saves.value.isEmpty)
    }

    @Test
    func choosingAFolderOpensThePickerAtTheSavedFolder() async {
        let store = store(defaults: UploadDefaults(folderPath: Constants.uploadFolder))

        await store.send(.chooseFolderTapped) { $0.folderPicker = pickerState(startingAt: Constants.uploadFolder) }
    }

    @Test
    func choosingAFolderWithNoneSavedStartsThePickerAtTheRoot() async {
        let store = store()

        await store.send(.chooseFolderTapped) { $0.folderPicker = pickerState(startingAt: "") }
    }

    @Test
    func confirmingAFolderClosesThePickerAndSavesItKeepingTheUploadWithoutAskingChoice() async {
        let store = store(defaults: UploadDefaults(folderPath: TestFolder.photos, shouldUploadWithoutAsking: true))
        await store.send(.chooseFolderTapped) { $0.folderPicker = pickerState(startingAt: TestFolder.photos) }

        await store.send(.folderPicker(.presented(.delegate(.confirmed(destination: Constants.uploadFolder))))) {
            $0.folderPicker = nil
            $0.defaults.folderPath = Constants.uploadFolder
        }

        #expect(saves.value == [Saved(
            accountID: Constants.accountID,
            defaults: UploadDefaults(folderPath: Constants.uploadFolder, shouldUploadWithoutAsking: true)
        )])
    }

    @Test
    func cancellingThePickerClosesItAndSavesNothing() async {
        let store = store(defaults: UploadDefaults(folderPath: TestFolder.photos))
        await store.send(.chooseFolderTapped) { $0.folderPicker = pickerState(startingAt: TestFolder.photos) }

        await store.send(.folderPicker(.presented(.delegate(.cancelled)))) { $0.folderPicker = nil }

        #expect(saves.value.isEmpty)
    }

    @Test
    func askEachTimeForgetsTheFolderAndTheUploadWithoutAskingChoice() async {
        let store = store(defaults: UploadDefaults(folderPath: Constants.uploadFolder, shouldUploadWithoutAsking: true))

        await store.send(.askEachTimeTapped) { $0.defaults = UploadDefaults() }

        #expect(saves.value == [Saved(accountID: Constants.accountID, defaults: UploadDefaults())])
    }

    @Test
    func uploadWithoutAskingCanBeTurnedOnOnceAFolderIsChosen() async {
        let store = store(defaults: UploadDefaults(folderPath: Constants.uploadFolder))

        await store.send(.shouldUploadWithoutAskingChanged(true)) { $0.defaults.shouldUploadWithoutAsking = true }

        #expect(saves.value == [Saved(
            accountID: Constants.accountID,
            defaults: UploadDefaults(folderPath: Constants.uploadFolder, shouldUploadWithoutAsking: true)
        )])
    }

    @Test(arguments: [nil, ""] as [String?])
    func uploadWithoutAskingCannotBeTurnedOnWithoutAFolder(_ folderPath: String?) async {
        let store = store(defaults: UploadDefaults(folderPath: folderPath))

        await store.send(.shouldUploadWithoutAskingChanged(true))

        #expect(saves.value.isEmpty)
    }

    @Test
    func uploadWithoutAskingCanBeTurnedOffEvenWhenNoFolderIsLeft() async {
        let store = store(defaults: UploadDefaults(folderPath: nil, shouldUploadWithoutAsking: true))

        await store.send(.shouldUploadWithoutAskingChanged(false)) { $0.defaults.shouldUploadWithoutAsking = false }

        #expect(saves.value == [Saved(accountID: Constants.accountID, defaults: UploadDefaults())])
    }
}
