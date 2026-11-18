import DesignSystem
import SwiftUI

private enum Constants {
    /// A white page, portrait like paper, lifted off its surface by a soft shadow.
    static let aspectRatio: CGFloat = 0.77
    static let cornerRadius: CGFloat = .size4
    static let shadowOpacity: Double = 0.28
    static let shadowRadius: CGFloat = .size2
    static let shadowY: CGFloat = 1
    static let textOpacity: Double = 0.78
    /// The text is drawn at this share of the page's width, so a row icon and a grid tile read the same.
    static let fontShareOfWidth: CGFloat = 0.13
    static let insetShareOfWidth: CGFloat = 0.13
}

/// A text or code file drawn as a small white page of its own first lines, like a document's first
/// page, in list rows and grid tiles alike.
struct TextThumbnailView: View {
    let snippet: String

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            RoundedRectangle(cornerRadius: Constants.cornerRadius)
                .fill(Color.white)
                .shadow(
                    color: .black.opacity(Constants.shadowOpacity),
                    radius: Constants.shadowRadius,
                    y: Constants.shadowY
                )
                .overlay(alignment: .topLeading) {
                    Text(snippet)
                        // The text is a picture of the file: the file's name says what it is.
                        .font(.system(size: width * Constants.fontShareOfWidth, design: .monospaced))
                        .foregroundStyle(Color.black.opacity(Constants.textOpacity))
                        .lineLimit(nil)
                        // Long lines wrap inside the page; whatever runs past its foot is clipped.
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(width * Constants.insetShareOfWidth)
                        .frame(width: width, height: proxy.size.height, alignment: .topLeading)
                        .clipShape(RoundedRectangle(cornerRadius: Constants.cornerRadius))
                }
        }
        .aspectRatio(Constants.aspectRatio, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview("Row size") {
    TextThumbnailView(snippet: "# Notes\n\n- one\n- two\n- three")
        .frame(width: 44, height: 44)
        .padding()
        .background(Color.backgroundSecondary)
}

#Preview("Grid size, dark") {
    TextThumbnailView(
        snippet: "import SwiftUI\n\nstruct Hello: View {\n  var body: some View {\n    Text(\"Hi\")\n  }\n}"
    )
    .frame(width: 46, height: 60)
    .padding()
    .background(Color.backgroundSecondary)
    .preferredColorScheme(.dark)
}
