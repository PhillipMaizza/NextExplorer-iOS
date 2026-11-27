#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    struct MacSearchLane: Identifiable {
        let title: String
        let sections: SearchResultSections
        var phase: DataPhase = .loaded
        var onShowMore: (() -> Void)?
        var onRetry: (() -> Void)?

        var id: String {
            title
        }

        var rows: [SearchResultItem] {
            sections.onDevice + sections.remote
        }

        var isShown: Bool {
            !rows.isEmpty || phase != .loaded
        }
    }

    struct MacSearchLaneHeader: View {
        let lane: MacSearchLane

        var body: some View {
            HStack(spacing: .space8) {
                Text(lane.title)
                    .type(.body3(.bold), style: .primaryOnSurface)
                    .accessibilityAddTraits(.isHeader)
                if !lane.rows.isEmpty {
                    Text(lane.rows.count.formatted())
                        .type(.body3(.semibold), style: .secondary)
                }
                Spacer(minLength: .space8)
                if let failure = lane.phase.errorMessage {
                    Text(failure)
                        .type(.caption(.regular), style: .error)
                        .lineLimit(1)
                    if let onRetry = lane.onRetry {
                        Button(L10n.Common.retry, action: onRetry)
                            .buttonStyle(.macDS(.secondary, size: .small))
                    }
                } else if lane.phase == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel(L10n.Common.loading)
                } else if let onShowMore = lane.onShowMore {
                    Button(L10n.Browse.searchShowMore, action: onShowMore)
                        .buttonStyle(.macDS(.secondary, size: .small))
                }
            }
            .padding(.top, .space12)
            .padding(.bottom, .space4)
        }
    }

    #Preview("Lanes") {
        MacSearchResultsTable(
            sections: SearchResultSections([], onDeviceIDs: []),
            lanes: [
                MacSearchLane(
                    title: "My Files",
                    sections: SearchResultSections(
                        [SearchResultItem(name: "Trip plan.txt", path: "personal", kind: "file", isNameMatch: true)],
                        onDeviceIDs: []
                    )
                ),
                MacSearchLane(
                    title: "Volumes",
                    sections: SearchResultSections([
                        SearchResultItem(
                            name: "Project plan.pdf",
                            path: "Files/04 Documents",
                            kind: "file",
                            isNameMatch: true
                        ),
                        SearchResultItem(name: "Floor plans", path: "Files/01 Photos", kind: "dir", isNameMatch: true),
                    ], onDeviceIDs: []),
                    onShowMore: {}
                ),
            ],
            favoritePaths: [],
            onOpen: { _ in },
            fileActions: { _ in EmptyView() }
        )
        .previewCanvas(.table)
    }
#endif
