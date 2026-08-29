import SwiftUI

/// The app mark: four amber facets, ported from `logo.svg` (viewBox 0 0 96 96). Vector
/// geometry rather than the raster asset so the splash can spin it and split its two wings.
private enum LogoGeometry {
    static let canvas: CGFloat = 96

    struct Facet {
        let points: [CGPoint]
        let top: Color
        let bottom: Color
    }

    /// Warm palette, the mark's own — not theme tokens.
    private static let light = Color(red: 0xFE / 255, green: 0xCB / 255, blue: 0x50 / 255)
    private static let lightLow = Color(red: 0xF9 / 255, green: 0xB5 / 255, blue: 0x4B / 255)
    private static let deep = Color(red: 0xF8 / 255, green: 0xBA / 255, blue: 0x37 / 255)
    private static let deepLow = Color(red: 0xF9 / 255, green: 0xA2 / 255, blue: 0x2F / 255)

    /// Facets 0–1 form the left wing, 2–3 the right.
    static let leftWing: [Facet] = [
        Facet(points: [CGPoint(x: 43.57, y: 66.49), CGPoint(x: 16.15, y: 76.66), CGPoint(x: 16.15, y: 19.34)],
              top: light, bottom: lightLow),
        Facet(points: [CGPoint(x: 45.77, y: 30.96), CGPoint(x: 45.77, y: 65.68), CGPoint(x: 43.57, y: 66.49), CGPoint(x: 16.15, y: 19.34)],
              top: deep, bottom: deepLow),
    ]
    static let rightWing: [Facet] = [
        Facet(points: [CGPoint(x: 79.85, y: 76.66), CGPoint(x: 50.23, y: 65.68), CGPoint(x: 50.23, y: 30.96), CGPoint(x: 53.02, y: 29.87)],
              top: deep, bottom: deepLow),
        Facet(points: [CGPoint(x: 79.85, y: 19.34), CGPoint(x: 79.85, y: 76.66), CGPoint(x: 53.02, y: 29.87)],
              top: light, bottom: lightLow),
    ]

    static func path(_ points: [CGPoint], in rect: CGRect) -> Path {
        let scale = min(rect.width, rect.height) / canvas
        let offsetX = rect.minX + (rect.width - canvas * scale) / 2
        let offsetY = rect.minY + (rect.height - canvas * scale) / 2
        var path = Path()
        for (index, point) in points.enumerated() {
            let scaled = CGPoint(x: offsetX + point.x * scale, y: offsetY + point.y * scale)
            if index == 0 { path.move(to: scaled) } else { path.addLine(to: scaled) }
        }
        path.closeSubpath()
        return path
    }
}

private struct FacetShape: Shape {
    let points: [CGPoint]
    func path(in rect: CGRect) -> Path { LogoGeometry.path(points, in: rect) }
}

private struct Wing: View {
    let facets: [LogoGeometry.Facet]
    var body: some View {
        ForEach(Array(facets.enumerated()), id: \.offset) { _, facet in
            FacetShape(points: facet.points)
                .fill(LinearGradient(colors: [facet.top, facet.bottom], startPoint: .top, endPoint: .bottom))
        }
    }
}

/// The app mark. Three flourish inputs, all `0` at rest so `DSLogoMark()` is the plain static
/// logo:
/// * `spin` (0…1) — one full 3D turn about the vertical axis.
/// * `flap` (−1…1) — the two wings pivot on the centre spine, like a butterfly.
/// * `part` (0…1) — the wings slide apart and fade, opening onto whatever is behind.
public struct DSLogoMark: View {
    private let spin: Double
    private let flap: Double
    private let part: Double
    private let size: CGFloat

    /// Wing pivot at `flap == ±1`, degrees.
    private static let flapAngle: Double = 55
    /// How far each wing travels at `part == 1`, in `size` multiples.
    private static let partTravel: CGFloat = 1.6

    public init(spin: Double = 0, flap: Double = 0, part: Double = 0, size: CGFloat = 96) {
        self.spin = spin
        self.flap = flap
        self.part = part
        self.size = size
    }

    public var body: some View {
        ZStack {
            wing(LogoGeometry.leftWing, direction: -1)
            wing(LogoGeometry.rightWing, direction: 1)
        }
        .frame(width: size, height: size)
        .rotation3DEffect(.degrees(spin * 360), axis: (x: 0, y: 1, z: 0), perspective: 0.55)
        .accessibilityHidden(true)
    }

    private func wing(_ facets: [LogoGeometry.Facet], direction: CGFloat) -> some View {
        Wing(facets: facets)
            .rotation3DEffect(
                .degrees(Self.flapAngle * flap * Double(direction)),
                axis: (x: 0, y: 1, z: 0),
                anchor: .center,
                perspective: 0.5
            )
            .offset(x: direction * Self.partTravel * size * part)
            .opacity(1 - part)
    }
}

#Preview("Rest / flap / part") {
    VStack(spacing: .space32) {
        DSLogoMark(size: 110)
        DSLogoMark(flap: 1, size: 110)
        DSLogoMark(part: 0.5, size: 110)
    }
    .padding()
    .background(Color.backgroundPrimary)
}
