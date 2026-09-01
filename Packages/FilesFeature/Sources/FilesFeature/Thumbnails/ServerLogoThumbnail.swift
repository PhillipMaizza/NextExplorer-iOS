import CoreModels
import DesignSystem
import SwiftUI
import UIKit

/// The server's logo as a circle: the branding image once it loads, `IconKit.server`
/// until then / on failure / when no custom logo is set. Fetches `branding.appLogoUrl` with a
/// plain `URLSession` request — one small image, re-fetched when the URL changes.
struct ServerLogoThumbnail: View {
    let branding: Branding
    let serverURL: URL
    var size: CGFloat
    /// A picked-but-unsaved logo, shown in place of the fetched one.
    var overrideImageData: Data?

    @State private var fetched: UIImage?

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(Circle().fill(Color.backgroundPrimary))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.borderPrimary, lineWidth: .borderWidthHairline))
            .task(id: branding.appLogoUrl) { await fetch() }
    }

    @ViewBuilder
    private var content: some View {
        if let overrideImageData, let image = UIImage(data: overrideImageData) {
            Image(uiImage: image).resizable().scaledToFill()
        } else if let fetched {
            Image(uiImage: fetched).resizable().scaledToFill()
        } else {
            IconKit.server
                .resizable().scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .padding(size * 0.2)
        }
    }

    private func fetch() async {
        guard let url = branding.resolvedLogoURL(serverURL: serverURL) else {
            fetched = nil
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        fetched = UIImage(data: data)
    }
}
