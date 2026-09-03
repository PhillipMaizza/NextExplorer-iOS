import CoreModels
import Foundation
import Localization

/// The snippet shown as a search hit's subtitle: the matched line with its own indentation
/// trimmed off (code lines are indented, which would otherwise push the text far right under a
/// big blank gap). `nil` for a filename only hit or an all whitespace line.
func searchResultSnippet(_ result: SearchResultItem) -> String? {
    guard let line = result.matchLine?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { return nil }
    return line
}

/// The small "Line N" label shown under a content match's snippet. `nil` when the hit is a
/// filename match or the server reported no line number.
func searchResultLineLabel(_ result: SearchResultItem) -> String? {
    guard result.matchLine != nil, let lineNumber = result.matchLineNumber else { return nil }
    return L10n.Browse.searchMatchLineLabel(lineNumber)
}
