import ComposableArchitecture
import CoreModels
@testable import FolderPickerFeature
import Foundation
import TestUtils

/// Fixtures shared by the picker suites.
@MainActor
protocol DestinationPickerTestHelpers {}

extension DestinationPickerTestHelpers {
    var serverURL: URL {
        URL(string: TestHost.exampleURLString)!
    }

    nonisolated func folder(_ name: String, path: String = "") -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: 0, kind: FileItem.directoryKind)
    }

    nonisolated func file(_ name: String, path: String = "") -> FileItem {
        FileItem(name: name, path: path, dateModified: MockDate.date, size: 0, kind: TestKind.text)
    }

    nonisolated var shortSearchTerm: String {
        "p"
    }

    nonisolated func access() -> FileAccess {
        FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: false, canDownload: true)
    }

    func finishLoad(_ state: inout DestinationPickerFeature.State, folders: [FileItem]) {
        state.phase = .loaded
        state.currentAccess = access()
        state.folders = IdentifiedArray(uniqueElements: folders)
    }
}
