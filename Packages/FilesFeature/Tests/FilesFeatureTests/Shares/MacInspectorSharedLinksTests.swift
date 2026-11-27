#if os(macOS)
    import CoreModels
    @testable import FilesFeature
    import Foundation
    import Testing
    import TestUtils

    @MainActor
    struct MacInspectorSharedLinksTests {
        private func share(_ id: String, space: String, path: String) -> Share {
            Share(
                id: id, shareToken: id, ownerId: "u1", sourcePath: path, sourceSpace: space, isDirectory: true,
                accessMode: .readonly, sharingType: .anyone, hasPassword: false,
                createdAt: MockDate.date, updatedAt: MockDate.date
            )
        }

        @Test
        func aFolderInMyFilesShowsItsOwnLinksAndAVolumeFolderItsOwn() {
            let all = [
                share("mine", space: "personal", path: "QA mine"),
                share("volume", space: "volume", path: "/Files/QA mine/"),
            ]
            let personal = FileItem(
                name: "QA mine",
                path: "personal",
                dateModified: MockDate.date,
                size: 0,
                kind: "directory"
            )
            let onVolume = FileItem(
                name: "QA mine",
                path: "Files",
                dateModified: MockDate.date,
                size: 0,
                kind: "directory"
            )

            #expect(MacInspectorSharedLinks.links(all, for: personal)?.map(\.id) == ["mine"])
            #expect(MacInspectorSharedLinks.links(all, for: onVolume)?.map(\.id) == ["volume"])
        }
    }
#endif
