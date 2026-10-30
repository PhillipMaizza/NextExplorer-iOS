import SwiftUI

/// Canvas sizes for `#Preview`s, so every preview of the same kind of screen uses one named size
/// instead of picking its own numbers.
public enum PreviewCanvas {
    /// A main or Browse window.
    case window
    /// The Mac Settings window, sidebar included.
    case settingsWindow
    /// One pane of the Mac Settings window.
    case settingsPane
    /// A file table on its own.
    case table
    /// The Get Info inspector column.
    case inspector
    /// A sheet or a window hosting one.
    case sheet
    /// A small dialog, popover or preview surface.
    case dialog
    /// A single control or row.
    case control

    public var size: CGSize {
        switch self {
        case .window: CGSize(width: 900, height: 500)
        case .settingsWindow: CGSize(width: 920, height: 560)
        case .settingsPane: CGSize(width: 640, height: 440)
        case .table: CGSize(width: 900, height: 300)
        case .inspector: CGSize(width: 320, height: 320)
        case .sheet: CGSize(width: 600, height: 600)
        case .dialog: CGSize(width: 480, height: 320)
        case .control: CGSize(width: 320, height: 160)
        }
    }
}

public extension View {
    /// Sizes a preview to a named canvas.
    func previewCanvas(_ canvas: PreviewCanvas) -> some View {
        frame(width: canvas.size.width, height: canvas.size.height)
    }

    /// Gives a preview a named canvas's width and lets it size its own height.
    func previewCanvasWidth(_ canvas: PreviewCanvas) -> some View {
        frame(width: canvas.size.width)
    }
}
