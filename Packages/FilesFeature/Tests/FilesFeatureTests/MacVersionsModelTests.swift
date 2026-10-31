#if os(macOS)
    import CoreModels
    import Dependencies
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Testing

    @MainActor
    struct MacVersionsModelTests {
        private let serverURL = URL(string: "https://example.com")!

        /// One version whose id is the file's path, so a history says which file it belongs to.
        private nonisolated static func history(for path: String) -> FileVersionHistory {
            FileVersionHistory(
                isEnabled: true,
                versions: [FileVersion(id: path, size: 1, modifiedAt: Date(), capturedAt: Date())],
                totalBytes: 1,
                rights: .init(canSee: true, canDownload: true, canRestore: true, canRemove: true)
            )
        }

        private static func file(_ name: String) -> FileItem {
            FileItem(name: name, path: "Docs", dateModified: Date(), size: 1, kind: "txt")
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
            let first = Self.file("a.txt")
            let second = Self.file("b.txt")

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
            let item = Self.file("a.txt")

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
