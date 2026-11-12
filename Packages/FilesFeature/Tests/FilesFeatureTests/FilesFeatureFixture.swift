import Foundation
import TestUtils

enum FilesFeatureFixture: String, FixtureFile {
    static let bundle = Bundle.module

    case legacyDragReference = "drop/legacy-reference"
    case googleDriveStub = "preview/google-drive-stub"
    case highlighterSample = "highlighter/sample"
}
