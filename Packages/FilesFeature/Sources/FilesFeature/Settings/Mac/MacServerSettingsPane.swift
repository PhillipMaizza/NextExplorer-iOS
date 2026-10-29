#if os(macOS)
    import AppKit
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI
    import UniformTypeIdentifiers

    private enum Metrics {
        static let logoSize: CGFloat = 64
        static let fieldWidth: CGFloat = 280
    }

    /// The Server pane: the server's name and icon, edited in place, with Update Server under
    /// the form. The address is fixed for the session.
    struct MacServerSettingsPane: View {
        @Bindable var store: StoreOf<ServerDetailsFeature>
        @State private var isChoosingIcon = false

        var body: some View {
            MacSettingsForm {
                MacSettingsRow(L10n.MacSettings.icon) {
                    HStack(spacing: .space12) {
                        ServerLogoThumbnail(
                            branding: store.branding,
                            serverURL: store.serverURL,
                            size: Metrics.logoSize,
                            overrideImageData: store.pendingLogoData
                        )
                        Button(L10n.ServerDetails.changeLogo + "…") { isChoosingIcon = true }
                    }
                }
                MacSettingsRow(L10n.ServerDetails.nameLabel) {
                    TextField(L10n.ServerDetails.nameLabel, text: $store.nameDraft.sending(\.nameChanged), prompt: Text(L10n.ServerDetails.namePlaceholder))
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: Metrics.fieldWidth)
                    if store.nameError == .empty {
                        Text(L10n.ServerDetails.nameErrorEmpty).foregroundStyle(Color.negativeText)
                    }
                }
                MacSettingsRow(L10n.ServerDetails.urlLabel) {
                    Text(store.serverURL.absoluteString).textSelection(.enabled)
                    MacSettingsNote(L10n.ServerDetails.urlFootnote)
                }
                if let error = store.errorMessage {
                    Text(error).foregroundStyle(Color.negativeText)
                }
            }
            .macSettingsSaveBar(
                L10n.ServerDetails.updateButton,
                isSaving: store.isSaving,
                isEnabled: store.isSaveEnabled
            ) { store.send(.updateTapped) }
            .fileImporter(isPresented: $isChoosingIcon, allowedContentTypes: [.image]) { result in
                guard case let .success(url) = result else { return }
                loadIcon(at: url)
            }
            .onAppear { store.send(.onAppear) }
        }

        private func loadIcon(at url: URL) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            if let image = NSImage(contentsOf: url), let data = ServerDetailsView.prepareLogo(image) {
                store.send(.logoPicked(data))
            } else {
                store.send(.logoPickFailed)
            }
        }
    }

    #Preview("Server") {
        MacServerSettingsPane(store: Store(initialState: ServerDetailsFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            branding: Branding(appName: "Rivendell Cloud", appLogoUrl: Branding.defaultLogoPath)
        )) { ServerDetailsFeature() } withDependencies: { $0.filesClient = .previewValue })
            .frame(width: 580, height: 420)
    }
#endif
