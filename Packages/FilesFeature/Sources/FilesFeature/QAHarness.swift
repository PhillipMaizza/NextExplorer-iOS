import ComposableArchitecture
import CoreModels
import Foundation
import SwiftUI

/// THROWAWAY App Store screenshot harness (delete after use). Renders the real `MainTabView`
/// iPad split shell from a seeded preview store so each section can be screenshotted without a
/// backend. `QA_SCREEN` picks which section is shown. `NextExplorerApp` points its body here
/// whenever `QA_SCREEN` is set.
public struct QAHarness: View {
    public init() {}

    public var body: some View {
        MainTabView(store: Self.store())
    }

    private static func store() -> StoreOf<MainTabFeature> {
        Store(initialState: seededState()) {
            MainTabFeature()
        } withDependencies: {
            $0.filesClient = .previewValue
        }
    }

    private static func seededState() -> MainTabFeature.State {
        let serverURL = URL(string: "https://demo.nextexplorer.app") ?? URL(fileURLWithPath: "/")
        var state = MainTabFeature.State(
            serverURL: serverURL,
            user: User(id: "demo", username: "demo_user", email: "demo@demo.com", displayName: "Demo User", roles: [])
        )

        let screen = ProcessInfo.processInfo.environment["QA_SCREEN"]
        switch screen {
        case "favorites": state.selectedTab = .favorites
        case "shared": state.selectedTab = .shared
        case "downloads": state.selectedTab = .downloads
        case "settings": state.selectedTab = .settings
        default: state.selectedTab = .browse
        }

        if screen == "search" {
            state.browse.root.searchQuery = "waterfall"
            state.browse.root.searchScope = .everywhere
            state.browse.root.isSearchingRemotely = false
            state.browse.root.searchResults = IdentifiedArray(uniqueElements: [
                result("release-notes.md", "Projects", "md", "Added the waterfall layout to the gallery grid.", 12),
                result("app-server.swift", "Projects/Server", "swift", "let waterfall = LayoutEngine(columns: 3)", 47),
                result("design-spec.txt", "Documents", "txt", "The waterfall view reflows on scroll.", 8),
                result("waterfall.png", "Photos", "png", nil, nil)
            ])
        }

        // Pre-seed the Browse root loaded so the hero shot has a rich tree with no skeleton flash.
        state.browse.root.phase = .loaded
        state.browse.root.access = FileAccess(canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true)
        state.browse.root.items = IdentifiedArray(uniqueElements: [
            dir("Documents", "2026-09-12"),
            dir("Photos", "2026-09-14"),
            dir("Projects", "2026-09-10"),
            dir("Music", "2026-09-08"),
            dir("Videos", "2026-09-13"),
            file("Q3 Presentation.pptx", "pptx", 2_480_000, "2026-09-11", thumb: false),
            file("Budget 2026.xlsx", "xlsx", 512_000, "2026-09-09", thumb: false),
            file("Proposal.docx", "docx", 340_000, "2026-09-07", thumb: false),
            file("Archive.zip", "zip", 6_700_000, "2026-09-06", thumb: false),
            file("README.md", "md", 8_400, "2026-09-05", thumb: false)
        ])

        state.favorites.phase = .loaded
        state.favorites.favorites = IdentifiedArray(uniqueElements: [
            fav("1", "Photos", "Photos", 0),
            fav("2", "Projects", "Projects", 1),
            fav("3", "Documents/Quarterly Report", "Quarterly Report", 2),
            fav("4", "Music", "Music", 3),
            fav("5", "Projects/Design", "Design", 4)
        ])

        return state
    }

    private static func result(_ name: String, _ path: String, _ kind: String, _ line: String?, _ lineNo: Int?) -> SearchResultItem {
        SearchResultItem(name: name, path: path, kind: kind, matchLine: line, matchLineNumber: lineNo)
    }

    private static func fav(_ id: String, _ path: String, _ label: String, _ position: Int) -> Favorite {
        Favorite(id: id, path: path, label: label, icon: "folder", color: nil, position: position, createdAt: date("2026-09-01"), updatedAt: date("2026-09-01"))
    }

    private static func dir(_ name: String, _ ymd: String) -> FileItem {
        FileItem(name: name, path: "", dateModified: date(ymd), size: 0, kind: "directory")
    }

    private static func file(_ name: String, _ kind: String, _ size: Int64, _ ymd: String, thumb: Bool) -> FileItem {
        FileItem(name: name, path: "", dateModified: date(ymd), size: size, kind: kind, supportsThumbnail: thumb)
    }

    private static func date(_ ymd: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: ymd) ?? Date()
    }
}
