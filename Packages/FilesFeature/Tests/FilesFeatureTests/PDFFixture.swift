import CoreGraphics
import Foundation

/// Writes a one page, solid color PDF with CoreGraphics, so the PDF thumbnail tests run on both
/// iOS and macOS.
enum PDFFixture {
    static func write(to url: URL, pageSize: CGSize, red: CGFloat, green: CGFloat, blue: CGFloat) {
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(url as CFURL, mediaBox: &mediaBox, nil) else { return }
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: red, green: green, blue: blue, alpha: 1))
        context.fill(mediaBox)
        context.endPDFPage()
        context.closePDF()
    }
}
