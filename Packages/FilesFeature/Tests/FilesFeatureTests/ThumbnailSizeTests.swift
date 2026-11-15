import CoreGraphics
import DesignSystem
@testable import FilesFeature
import Testing

struct ThumbnailSizeTests {
    struct Metrics: Sendable {
        let size: ThumbnailSize
        let iconSize: CGFloat
    }

    nonisolated static let metrics = [
        Metrics(size: .small, iconSize: 40),
        Metrics(size: .medium, iconSize: 56),
        Metrics(size: .large, iconSize: 72),
    ]

    @Test(arguments: metrics)
    func eachSizeHasItsIconSize(_ metrics: Metrics) {
        #expect(metrics.size.iconSize == metrics.iconSize)
    }

    @Test(arguments: metrics)
    func everyIconFitsTheOneTileWidth(_ metrics: Metrics) {
        #expect(metrics.size.iconSize + FileGridMetrics.cellPadding * 2 <= FileGridMetrics.adaptiveMinimum)
    }

    @Test
    func theStoredRawValuesAreStable() {
        #expect(ThumbnailSize.allCases.map(\.rawValue) == ["small", "medium", "large"])
        #expect(ThumbnailSize(rawValue: "huge") == nil)
    }
}
