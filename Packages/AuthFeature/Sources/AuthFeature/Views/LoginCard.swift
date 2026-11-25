import DesignSystem
import SwiftUI

enum LoginCard {
    static let width: CGFloat = 440
    static let maxHeight: CGFloat = 620
    static let outerPadding: CGFloat = .space24
    static let gradientTop = Color(red: 1.0, green: 194.0 / 255.0, blue: 40.0 / 255.0)
    static let gradientBottom = Color(red: 1.0, green: 157.0 / 255.0, blue: 0.0)
}

struct LoginCardBackground: View {
    var body: some View {
        LinearGradient(
            colors: [LoginCard.gradientTop, LoginCard.gradientBottom],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}

extension View {
    func loginCard() -> some View {
        frame(maxWidth: LoginCard.width, maxHeight: LoginCard.maxHeight)
            .clipShape(RoundedRectangle(cornerRadius: .radiusCard, style: .continuous))
            .elevation(.level16)
            .frame(maxWidth: .infinity)
            .padding(LoginCard.outerPadding)
    }
}

#Preview("Card") {
    ZStack {
        LoginCardBackground()
        DSSheetSurface()
            .frame(height: .size96)
            .loginCard()
    }
}
