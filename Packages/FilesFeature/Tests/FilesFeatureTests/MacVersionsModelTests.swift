import TestUtils
#if os(macOS)
    import CoreModels
    import Dependencies
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Testing

    @MainActor
    struct MacVersionsModelTests {
        private let serverURL = URL(string: TestHost.exampleURLString)!

        /// One version whose id is the file's path, so a history says which file it belongs to.
        private nonisolated static func history(for path: String) -> FileVersionHistory {
            FileVersionHistory(
                isEnabled: true,
                versions: [FileVersion(id: path, size: 1, modifiedAt: MockDate.date, capturedAt: MockDate.date)],
                totalBytes: 1,
                rights: .init(canSee: true, canDownload: true, canRestore: true, canRemove: true)
            )
        }

        private static func file(_ name: String) -> FileItem {
            FileItem(name: name, path: TestFolder.docs, dateModified: MockDate.date, size: 1, kind: TestKind.text)
        }

        @Test
        func aRestoreThatFinishesAfterTheSelectionMovedKeepsTheNewFilesHistory() async throws {
            let (gate, release) = AsyncStream<Void>.makeStream()
            let model = withDependencies {
                $0.filesClient.fetchVersions = { _, path in Self.history(for: path) }
                $0.filesClient.restoreVersion = { _, _, _ in
                    for await _ in gate {
                        return
                    }
                }
            } operation: {
                MacVersionsModel()
            }
            let first = Self.file(TestFile.aText)
            let second = Self.file(TestFile.bText)

            await model.load(item: first, serverURL: serverURL)
            let version = try #require(model.history?.versions.first)
            let restore = model.restoreConfirmed(version)
            await model.load(item: second, serverURL: serverURL)
            release.yield()
            await restore?.value

            #expect(model.history?.versions.first?.id == second.id)
            #expect(model.errorMessage == nil)
        }

        @Test
        func aRestoreRefreshesTheHistoryAndTellsTheListing() async throws {
            let didChangeFiles = LockIsolated(false)
            let model = withDependencies {
                $0.filesClient.fetchVersions = { _, path in Self.history(for: path) }
                $0.filesClient.restoreVersion = { _, _, _ in }
            } operation: {
                MacVersionsModel()
            }
            model.onFilesChanged = { didChangeFiles.setValue(true) }
            let item = Self.file(TestFile.aText)

            await model.load(item: item, serverURL: serverURL)
            let version = try #require(model.history?.versions.first)
            model.versionToRestore = version
            await model.restoreConfirmed(version)?.value

            #expect(model.versionToRestore == nil)
            #expect(model.history?.versions.first?.id == item.id)
            #expect(didChangeFiles.value)
        }
    }
#endif
