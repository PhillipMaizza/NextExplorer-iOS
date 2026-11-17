import TestUtils
#if os(macOS)
    import CoreModels
    import Dependencies
    import FilesClient
    @testable import FilesFeature
    import Foundation
    import Localization
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

        @Test
        func viewingATextVersionOpensItsContentInASheet() async throws {
            let model = withDependencies {
                $0.filesClient.fetchVersions = { _, path in Self.history(for: path) }
                $0.filesClient.versionText = { _, _, _ in
                    FileVersionText(name: TestFile.aText, size: 4, modifiedAt: MockDate.date, content: "body")
                }
            } operation: {
                MacVersionsModel()
            }
            await model.load(item: Self.file(TestFile.aText), serverURL: serverURL)
            let version = try #require(model.history?.versions.first)

            #expect(model.canViewText)
            await model.viewText(version)?.value

            #expect(model.textPreview?.content == "body")
            #expect(model.textPreview?.id == version.id)
            #expect(model.errorMessage == nil)
        }

        @Test
        func aFailedTextReadShowsTheServerMessageAndNoSheet() async throws {
            let model = withDependencies {
                $0.filesClient.fetchVersions = { _, path in Self.history(for: path) }
                $0.filesClient.versionText = { _, _, _ in
                    throw FilesClientError.serverMessage(statusCode: 400, message: "Too large to read as text.")
                }
            } operation: {
                MacVersionsModel()
            }
            await model.load(item: Self.file(TestFile.aText), serverURL: serverURL)
            let version = try #require(model.history?.versions.first)

            await model.viewText(version)?.value

            #expect(model.textPreview == nil)
            #expect(model.errorMessage == "Too large to read as text.")
        }

        @Test
        func onlyTextFilesOfferTheirVersionsAsText() async {
            let model = withDependencies {
                $0.filesClient.fetchVersions = { _, path in Self.history(for: path) }
            } operation: {
                MacVersionsModel()
            }
            await model.load(item: Self.file("photo.jpg"), serverURL: serverURL)
            #expect(!model.canViewText)
        }

        @Test
        func pickingAFileAsksBeforeReplacingAndThenWritesThroughTheClient() async throws {
            let replaced = LockIsolated<[String]>([])
            let didChangeFiles = LockIsolated(false)
            let model = withDependencies {
                $0.filesClient.fetchVersions = { _, path in Self.history(for: path) }
                $0.filesClient.replaceWithVersion = { _, path, versionID, target in
                    replaced.withValue { $0.append("\(path)|\(versionID)|\(target)") }
                }
            } operation: {
                MacVersionsModel()
            }
            model.onFilesChanged = { didChangeFiles.setValue(true) }
            let item = Self.file(TestFile.aText)
            await model.load(item: item, serverURL: serverURL)
            let version = try #require(model.history?.versions.first)

            model.beginReplace(version)
            #expect(model.replacePicker != nil)

            model.pickerFinished(.confirmed(destination: TestPath.docsNotes), version: version)
            #expect(model.replacePicker == nil)
            let replacement = try #require(model.replacement)
            #expect(replacement.targetPath == TestPath.docsNotes)
            #expect(replaced.value.isEmpty)

            await model.replaceConfirmed(replacement)?.value
            #expect(model.statusMessage == L10n.FileInfo.versionReplaced("notes.txt"))
            #expect(replaced.value == ["\(item.id)|\(version.id)|\(TestPath.docsNotes)"])
            #expect(model.replacement == nil)
            #expect(didChangeFiles.value)
        }

        @Test
        func cancellingTheFileChooserWritesNothing() async throws {
            let model = withDependencies {
                $0.filesClient.fetchVersions = { _, path in Self.history(for: path) }
            } operation: {
                MacVersionsModel()
            }
            await model.load(item: Self.file(TestFile.aText), serverURL: serverURL)
            let version = try #require(model.history?.versions.first)

            model.beginReplace(version)
            model.pickerFinished(.cancelled, version: version)

            #expect(model.replacePicker == nil)
            #expect(model.replacement == nil)
        }

        @Test
        func aFailedReplaceShowsTheServerMessage() async throws {
            let model = withDependencies {
                $0.filesClient.fetchVersions = { _, path in Self.history(for: path) }
                $0.filesClient.replaceWithVersion = { _, _, _, _ in
                    throw FilesClientError.serverMessage(
                        statusCode: 400,
                        message: "The file to replace must be an existing file."
                    )
                }
            } operation: {
                MacVersionsModel()
            }
            await model.load(item: Self.file(TestFile.aText), serverURL: serverURL)
            let version = try #require(model.history?.versions.first)

            await model.replaceConfirmed(VersionReplacement(
                version: version,
                targetPath: TestPath.docsNotes
            ))?.value

            #expect(model.errorMessage == "The file to replace must be an existing file.")
        }

        @Test
        func aLongTextVersionIsCutShortAndSaysSo() async throws {
            let long = String(repeating: "a", count: 200_001)
            let model = withDependencies {
                $0.filesClient.fetchVersions = { _, path in Self.history(for: path) }
                $0.filesClient.versionText = { _, _, _ in
                    FileVersionText(name: TestFile.aText, size: 200_001, modifiedAt: MockDate.date, content: long)
                }
            } operation: {
                MacVersionsModel()
            }
            await model.load(item: Self.file(TestFile.aText), serverURL: serverURL)
            let version = try #require(model.history?.versions.first)

            await model.viewText(version)?.value

            #expect(model.textPreview?.isTruncated == true)
            #expect(model.textPreview?.content.count == 200_000)
        }

        @Test
        func theNextChangeClearsTheStatusMessage() async throws {
            let model = withDependencies {
                $0.filesClient.fetchVersions = { _, path in Self.history(for: path) }
                $0.filesClient.replaceWithVersion = { _, _, _, _ in }
                $0.filesClient.versionText = { _, _, _ in
                    FileVersionText(name: TestFile.aText, size: 1, modifiedAt: MockDate.date, content: "x")
                }
                $0.filesClient.updateVersion = { _, _, _, _, _ in
                    FileVersion(id: "v", size: 1, modifiedAt: MockDate.date, capturedAt: MockDate.date)
                }
            } operation: {
                MacVersionsModel()
            }
            await model.load(item: Self.file(TestFile.aText), serverURL: serverURL)
            let version = try #require(model.history?.versions.first)
            await model.replaceConfirmed(VersionReplacement(
                version: version,
                targetPath: TestPath.docsNotes
            ))?.value
            #expect(model.statusMessage != nil)

            model.togglePin(version)
            #expect(model.statusMessage == nil)

            await model.replaceConfirmed(VersionReplacement(
                version: version,
                targetPath: TestPath.docsNotes
            ))?.value
            #expect(model.statusMessage != nil)
            model.viewText(version)
            #expect(model.statusMessage == nil)
        }
    }
#endif
