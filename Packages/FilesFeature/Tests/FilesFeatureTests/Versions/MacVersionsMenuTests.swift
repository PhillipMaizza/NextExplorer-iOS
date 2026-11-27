import TestUtils
#if os(macOS)
    import CoreModels
    import Dependencies
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Testing

    @MainActor
    struct MacVersionsMenuTests {
        private let serverURL = URL(string: TestHost.exampleURLString)!

        private nonisolated static func history(for path: String, canSee: Bool = true) -> FileVersionHistory {
            FileVersionHistory(
                isEnabled: true,
                versions: [FileVersion(id: path, size: 1, modifiedAt: MockDate.date, capturedAt: MockDate.date)],
                totalBytes: 1,
                rights: .init(canSee: canSee, canDownload: true, canRestore: true, canRemove: true)
            )
        }

        private static func file(_ name: String) -> FileItem {
            FileItem(name: name, path: TestFolder.docs, dateModified: MockDate.date, size: 1, kind: TestKind.text)
        }

        private func model(versionsEnabled: Bool = true, canSee: Bool = true) -> MacVersionsModel {
            withDependencies {
                $0.filesClient.serverFeatures = { _ in ServerFeatures(isVersionsEnabled: versionsEnabled) }
                $0.filesClient.fetchVersions = { _, path in Self.history(for: path, canSee: canSee) }
                $0.filesClient.restoreVersion = { _, _, _ in }
            } operation: {
                MacVersionsModel()
            }
        }

        @Test("The submenu lists the loaded history; a file nobody loaded offers only Show All Versions")
        func theSubmenuLoadsThenLists() async {
            let model = model()
            let item = Self.file(TestFile.aText)
            let other = Self.file(TestFile.bText)

            await model.load(item: item, serverURL: serverURL, account: Constants.account)

            #expect(model.menuPhase(for: item) == .loaded(Self.history(for: item.id)))
            #expect(model.menuPhase(for: other) == .unloaded)
        }

        @Test("No submenu when the server keeps no versions, for folders, or when a share hides them")
        func theSubmenuHidesWhereTheWebHidesIt() async {
            let item = Self.file(TestFile.aText)
            let folder = FileItem(
                name: TestFolder.docs,
                path: "",
                dateModified: MockDate.date,
                size: 0,
                kind: FileItem.directoryKind
            )
            let off = model(versionsEnabled: false)
            let hidden = model(canSee: false)

            await off.load(item: item, serverURL: serverURL, account: Constants.account)
            await hidden.load(item: item, serverURL: serverURL, account: Constants.account)

            #expect(off.menuPhase(for: item) == .hidden)
            #expect(off.menuPhase(for: folder) == .hidden)
            #expect(hidden.menuPhase(for: item) == .hidden)
        }

        @Test("A restore from the menu for another row refreshes that row's history and leaves the selection's")
        func aMenuRestoreOnAnotherRowKeepsTheSelection() async throws {
            let model = model()
            let other = Self.file(TestFile.bText)
            let selected = Self.file(TestFile.aText)
            await model.load(item: other, serverURL: serverURL, account: Constants.account)
            await model.load(item: selected, serverURL: serverURL, account: Constants.account)
            let version = try #require(model.history(for: other)?.versions.first)

            model.beginRestore(version, of: other)
            await model.restoreConfirmed(version)?.value

            #expect(model.restoreTarget == nil)
            #expect(model.history?.versions.first?.id == selected.id)
            #expect(model.history(for: other)?.versions.first?.id == other.id)
        }

        @Test("A failed change from the menu is reported to the window, not under the inspector")
        func aMenuFailureGoesToTheWindow() async throws {
            let reported = LockIsolated<String?>(nil)
            let model = withDependencies {
                $0.filesClient.serverFeatures = { _ in ServerFeatures(isVersionsEnabled: true) }
                $0.filesClient.fetchVersions = { _, path in Self.history(for: path) }
                $0.filesClient.copyVersion = { _, _, _, _ in
                    throw FilesClientError.serverMessage(statusCode: 403, message: Constants.refusal)
                }
            } operation: {
                MacVersionsModel()
            }
            model.onMenuFailure = { reported.setValue($0) }
            let item = Self.file(TestFile.aText)
            await model.load(item: item, serverURL: serverURL, account: Constants.account)
            let version = try #require(model.history?.versions.first)

            await model.saveCopy(version, of: item)?.value

            #expect(reported.value == Constants.refusal)
            #expect(model.errorMessage == nil)
        }

        @Test("Another account on the same server starts with no remembered histories")
        func switchingAccountForgetsHistories() async {
            let model = model()
            let item = Self.file(TestFile.aText)
            await model.load(item: item, serverURL: serverURL, account: Constants.account)

            await model.load(item: Self.file(TestFile.bText), serverURL: serverURL, account: Constants.otherAccount)

            #expect(model.history(for: item) == nil)
        }

        @Test("Another server starts with no remembered histories")
        func switchingServerForgetsHistories() async {
            let model = model()
            let item = Self.file(TestFile.aText)
            await model.load(item: item, serverURL: serverURL, account: Constants.account)

            await model.load(
                item: Self.file(TestFile.bText),
                serverURL: Constants.otherServer,
                account: Constants.account
            )

            #expect(model.history(for: item) == nil)
        }
    }

    private enum Constants {
        static let refusal = "Downloading versions is not allowed."
        static let otherServer = URL(string: "https://other.example.com")!
        static let account = "demo"
        static let otherAccount = "demo_user"
    }
#endif
