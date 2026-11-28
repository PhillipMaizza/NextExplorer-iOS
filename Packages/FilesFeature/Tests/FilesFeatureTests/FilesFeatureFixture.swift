import Foundation
import TestUtils

enum FilesFeatureFixture: String, FixtureFile {
    static let bundle = Bundle.module

    case legacyDragReference = "drop/legacy-reference"
    case googleDriveStub = "preview/google-drive-stub"
    case highlighterSample = "highlighter/sample"
    case prettyCompact = "pretty/compact"
    case prettyCompactLaidOut = "pretty/compact-laid-out"
    case prettyEscaped = "pretty/escaped"
    case prettyEscapedLaidOut = "pretty/escaped-laid-out"
    case prettyCramped = "pretty/cramped"
    case prettyIndented = "pretty/indented"
    case prettyTruncated = "pretty/truncated"

    var fileExtension: String {
        self == .prettyTruncated ? "txt" : "json"
    }
}
