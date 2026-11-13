import CoreModels
import DesignSystem
import SwiftUI

/// A search hit as a list row, for Browse and Favorites alike: its name, the matched line under it,
/// and what matched ("Contents, Line 12") when it is more than the name. When nothing matched inside
/// it, the line under the name says where it lives, as the web client does; a hit in the folder on
/// screen (`currentFolder`) known from its listing shows its size and date there instead.
struct SearchResultRow: View {
    let result: SearchResultItem
    var knownItem: FileItem?
    var currentFolder: String?
    var isFavorite = false
    var serverURL: URL?
    var showThumbnails = false
    var matchedSource: PreviewMatchedSource?
    var isOpening = false

    /// A hit in the folder on screen, whose size and date are known: where it lives goes unsaid.
    private var shownItem: FileItem? {
        guard let knownItem, result.path == currentFolder else { return nil }
        return knownItem
    }

    var body: some View {
        FileRowView(
            name: result.name,
            isDirectory: result.isDirectory,
            subtitle: searchResultSnippet(result) ?? (shownItem == nil ? searchResultLocation(result) : nil),
            lineLabel: searchResultRowLabel(result),
            isFavorite: isFavorite,
            kind: result.displayKind,
            thumbnailFile: result.thumbnailFile,
            serverURL: serverURL,
            showThumbnails: showThumbnails,
            matchedSource: matchedSource,
            isOpening: isOpening,
            dateModified: shownItem.flatMap { $0.hasKnownDate ? $0.dateModified : nil },
            size: shownItem?.size
        )
    }
}

#Preview("Matches") {
    List {
        SearchResultRow(result: SearchResultItem(
            name: "budget.xlsx",
            path: "Documents",
            kind: "file",
            isNameMatch: true
        ))
        SearchResultRow(result: SearchResultItem(
            name: "notes.md", path: "Documents", kind: "file",
            matchLine: "    budget for the trip", matchLineNumber: 12, isContentMatch: true
        ))
        SearchResultRow(result: SearchResultItem(
            name: "budget-plan.md", path: "Documents", kind: "file",
            matchLine: "budget", matchLineNumber: 1, isNameMatch: true, isContentMatch: true
        ))
        SearchResultRow(
            result: SearchResultItem(name: "Budgets", path: "", kind: "dir", isNameMatch: true),
            isFavorite: true
        )
    }
}

#Preview("Instant match") {
    List {
        SearchResultRow(result: SearchResultItem(name: "budget.xlsx", path: "Documents", kind: "file"))
    }
}

#Preview("In the folder on screen") {
    List {
        SearchResultRow(
            result: SearchResultItem(name: "budget.xlsx", path: "Documents", kind: "file"),
            knownItem: FileItem(name: "budget.xlsx", path: "Documents", dateModified: .now, size: 48_000, kind: "xlsx"),
            currentFolder: "Documents"
        )
    }
}
