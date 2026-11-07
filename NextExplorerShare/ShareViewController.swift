import ComposableArchitecture
import DesignSystem
import Foundation
import ShareExtensionFeature
import SwiftUI

#if os(iOS)
    import UIKit

    typealias PlatformViewController = UIViewController
    typealias PlatformHostingController = UIHostingController
#else
    import AppKit

    typealias PlatformViewController = NSViewController
    typealias PlatformHostingController = NSHostingController
#endif

#if os(macOS)
    private enum Metrics {
        /// The share sheet's fixed size (a zero size showed nothing at all). The form fills it:
        /// header at the top, buttons at the bottom.
        static let initialSize = NSSize(width: 460, height: 320)
    }
#endif

/// The Share Extension's entry point: reads what the other app shared, then hosts
/// `ShareUploadView`, which hands the files to the background uploader.
final class ShareViewController: PlatformViewController {
    private var store: StoreOf<ShareUploadFeature>?

    #if os(macOS)
        override func loadView() {
            view = NSView(frame: NSRect(origin: .zero, size: Metrics.initialSize))
            preferredContentSize = Metrics.initialSize
        }
    #endif

    override func viewDidLoad() {
        super.viewDidLoad()
        DesignSystemFonts.registerAll()
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        let store = Store(initialState: ShareUploadFeature.State()) {
            ShareUploadFeature()
                .onClose { [weak self] completed in self?.close(completed: completed) }
        } withDependencies: {
            $0.sharedItems = .live(providers: providers)
        }
        self.store = store
        let host = PlatformHostingController(rootView: ShareUploadView(store: store))
        addChild(host)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func close(completed: Bool) {
        if completed {
            extensionContext?.completeRequest(returningItems: nil)
        } else {
            extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        }
    }
}

private extension Reducer where State == ShareUploadFeature.State, Action == ShareUploadFeature.Action {
    /// Runs `perform` on the main actor when the feature asks to close.
    func onClose(_ perform: @escaping @MainActor (Bool) -> Void) -> some ReducerOf<ShareUploadFeature> {
        CombineReducers {
            self
            Reduce { _, action in
                guard case let .delegate(.close(completed)) = action else { return .none }
                return .run { @MainActor _ in perform(completed) }
            }
        }
    }
}
