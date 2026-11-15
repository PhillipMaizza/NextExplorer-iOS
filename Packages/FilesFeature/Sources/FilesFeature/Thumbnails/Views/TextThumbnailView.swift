import DesignSystem
import SwiftUI

private enum Constants {
    /// The text is drawn at this share of the icon's width, so a row icon and a grid tile read the same.
    static let fontShareOfWidth: CGFloat = 0.115
    static let insetShareOfWidth: CGFloat = 0.12
    static let topInsetShareOfHeight: CGFloat = 0.2
    static let textOpacity: Double = 0.85
    static let pageStrokeWidth: CGFloat = 1
}

/// A text or code file drawn as a small page of its own first lines, the way Finder shows one.
struct TextThumbnailView: View {
    let snippet: String

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            FilePageShape()
                .fill(Color.backgroundSecondary)
                .overlay(FilePageShape().stroke(Color.tertiaryDS, lineWidth: Constants.pageStrokeWidth))
                .overlay(alignment: .topLeading) {
                    Text(snippet)
                        // The text is a picture of the file: the file's name says what it is.
                        .font(.system(size: width * Constants.fontShareOfWidth, design: .monospaced))
                        .foregroundStyle(Color.primaryDS.opacity(Constants.textOpacity))
                        .lineLimit(nil)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, width * Constants.insetShareOfWidth)
                        .padding(.top, proxy.size.height * Constants.topInsetShareOfHeight)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .clipShape(FilePageShape())
                }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

#Preview("Code") {
    TextThumbnailView(
        snippet: "import SwiftUI\n\nstruct Hello: View {\n  var body: some View {\n    Text(\"Hi\")\n  }\n}"
    )
    .frame(width: 96, height: 96)
    .padding()
}

#Preview("Row size") {
    TextThumbnailView(snippet: "# Notes\n\n- one\n- two\n- three")
        .frame(width: 44, height: 44)
        .padding()
}
