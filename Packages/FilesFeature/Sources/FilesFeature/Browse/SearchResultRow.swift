import CoreModels
import DesignSystem
import SwiftUI

/// A search hit as a list row, for Browse and Favorites alike: its name, the matched line under it,
/// and what matched ("Contents, Line 12") when it is more than the name. A hit known from a listing
/// (`knownItem`, the folder on screen or one saved on the device) shows its size and date instead
/// when nothing matched inside it.
struct SearchResultRow: View {
    let result: SearchResultItem
    var knownItem: FileItem?
    var isFavorite = false
    var serverURL: URL?
    var showThumbnails = false
    var matchedSource: PreviewMatchedSource?
    var isOpening = false

    var body: some View {
        FileRowView(
            name: result.name,
            isDirectory: result.isDirectory,
            subtitle: searchResultSnippet(result),
            lineLabel: searchResultRowLabel(result),
            isFavorite: isFavorite,
            kind: result.displayKind,
            thumbnailFile: result.thumbnailFile,
            serverURL: serverURL,
            showThumbnails: showThumbnails,
            matchedSource: matchedSource,
            isOpening: isOpening,
            dateModified: knownItem.flatMap { $0.hasKnownDate ? $0.dateModified : nil },
            size: knownItem?.size
        )
    }
}

#Preview("Matches") {
    List {
        SearchResultRow(result: SearchResultItem(name: "budget.xlsx", path: "Documents", kind: "file", isNameMatch: true))
        SearchResultRow(result: SearchResultItem(
            name: "notes.md", path: "Documents", kind: "file",
            matchLine: "    budget for the trip", matchLineNumber: 12, isContentMatch: true
        ))
        SearchResultRow(result: SearchResultItem(
            name: "budget-plan.md", path: "Documents", kind: "file",
            matchLine: "budget", matchLineNumber: 1, isNameMatch: true, isContentMatch: true
        ))
        SearchResultRow(result: SearchResultItem(name: "Budgets", path: "", kind: "dir", isNameMatch: true), isFavorite: true)
    }
}

#Preview("Instant match") {
    List {
        SearchResultRow(result: SearchResultItem(name: "budget.xlsx", path: "Documents", kind: "file"))
    }
}

#Preview("Known from a saved listing") {
    List {
        SearchResultRow(
            result: SearchResultItem(name: "budget.xlsx", path: "Documents", kind: "file"),
            knownItem: FileItem(name: "budget.xlsx", path: "Documents", dateModified: .now, size: 48_000, kind: "xlsx")
        )
    }
}
