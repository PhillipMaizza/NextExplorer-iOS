import CoreGraphics
import DesignSystem
@testable import FilesFeature
import Testing

struct ThumbnailSizeTests {
    struct Metrics: Sendable {
        let size: ThumbnailSize
        let gridItemMinWidth: CGFloat
        let iconSize: CGFloat
    }

    nonisolated static let metrics = [
        Metrics(size: .small, gridItemMinWidth: 76, iconSize: 40),
        Metrics(size: .medium, gridItemMinWidth: 100, iconSize: 56),
        Metrics(size: .large, gridItemMinWidth: 140, iconSize: 72),
    ]

    @Test(arguments: metrics)
    func eachSizeHasItsGridColumnWidthAndIconSize(_ metrics: Metrics) {
        #expect(metrics.size.gridItemMinWidth == metrics.gridItemMinWidth)
        #expect(metrics.size.iconSize == metrics.iconSize)
    }

    @Test
    func theStoredRawValuesAreStable() {
        #expect(ThumbnailSize.allCases.map(\.rawValue) == ["small", "medium", "large"])
        #expect(ThumbnailSize(rawValue: "huge") == nil)
    }
}
