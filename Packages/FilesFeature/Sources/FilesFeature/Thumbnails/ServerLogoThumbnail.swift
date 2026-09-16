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
    @State private var overrideImage: UIImage?

    private var maxPixelDimension: CGFloat {
        size * UIScreen.main.scale
    }

    var body: some View {
        content
            .frame(width: size, height: size)
            .background(Circle().fill(Color.backgroundPrimary))
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Color.borderPrimary, lineWidth: .borderWidthHairline))
            .task(id: branding.appLogoUrl) { await fetch() }
            .task(id: overrideImageData) { await decodeOverride() }
    }

    @ViewBuilder
    private var content: some View {
        if let overrideImage {
            Image(uiImage: overrideImage).resizable().scaledToFill()
        } else if let fetched {
            Image(uiImage: fetched).resizable().scaledToFill()
        } else {
            IconKit.server
                .resizable().scaledToFit()
                .foregroundStyle(Color.secondaryDS)
                .padding(size * 0.2)
        }
    }

    private func decodeOverride() async {
        guard let overrideImageData else {
            overrideImage = nil
            return
        }
        let target = maxPixelDimension
        let image = await Task.detached(priority: .utility) {
            ImageDownsampling.image(from: overrideImageData, maxPixelDimension: target)
        }.value
        if !Task.isCancelled {
            overrideImage = image
        }
    }

    private func fetch() async {
        guard let url = branding.resolvedLogoURL(serverURL: serverURL) else {
            fetched = nil
            return
        }
        guard let (data, _) = try? await URLSession.shared.data(from: url) else { return }
        let target = maxPixelDimension
        let image = await Task.detached(priority: .utility) {
            ImageDownsampling.image(from: data, maxPixelDimension: target)
        }.value
        if !Task.isCancelled {
            fetched = image
        }
    }
}
