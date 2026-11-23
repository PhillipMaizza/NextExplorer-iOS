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

extension View {
    func instantPushOnMac(depth: Int) -> some View {
        #if os(macOS)
            transaction(value: depth) { $0.disablesAnimations = true }
        #else
            self
        #endif
    }
}
