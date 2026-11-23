import DesignSystem
import SwiftUI

struct LoginErrorNote: View {
    let message: String

    var body: some View {
        #if os(macOS)
            MacNote(message, kind: .error)
                .transition(.opacity)
        #else
            Text(message)
                .type(.body2(.semibold), style: .error)
                .frame(maxWidth: .infinity, alignment: .leading)
                .transition(.opacity)
        #endif
    }
}

#Preview {
    LoginErrorNote(message: "The password is incorrect.")
        .padding(.space24)
}
