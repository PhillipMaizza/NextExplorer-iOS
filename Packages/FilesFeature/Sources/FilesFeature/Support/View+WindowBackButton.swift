import SwiftUI

extension View {
    func hidesSystemBackOnMac() -> some View {
        #if os(macOS)
            navigationBarBackButtonHidden()
        #else
            self
        #endif
    }
}
