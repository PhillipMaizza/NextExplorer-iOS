#if os(macOS)
    import AppKit
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI
    import UniformTypeIdentifiers

    private enum Metrics {
        static let logoSize: CGFloat = .size56
        static let iconRowHeight: CGFloat = 92
        static let nameFieldWidth: CGFloat = 280
    }

    /// The Server pane: the server's name and icon, edited in place and saved from the header.
    /// The address is fixed for the session.
    struct MacServerSettingsPane: View {
        @Bindable var store: StoreOf<ServerDetailsFeature>
        @State private var isChoosingIcon = false

        var body: some View {
            MacFormPage {
                MacFormGroup {
                    MacFormRow {
                        HStack(spacing: .space16) {
                            ServerLogoThumbnail(
                                branding: store.branding,
                                serverURL: store.serverURL,
                                size: Metrics.logoSize,
                                overrideImageData: store.pendingLogoData
                            )
                            Text(L10n.MacSettings.icon)
                        }
                    } control: {
                        Button(L10n.ServerDetails.changeLogo + "…") { isChoosingIcon = true }
                            .buttonStyle(.macDS(.secondary, size: .small))
                    }
                    .frame(minHeight: Metrics.iconRowHeight)
                    MacFormRow(L10n.ServerDetails.nameLabel) {
                        MacTextField(
                            L10n.ServerDetails.nameLabel,
                            text: $store.nameDraft.sending(\.nameChanged),
                            prompt: L10n.ServerDetails.namePlaceholder
                        )
                        .frame(width: Metrics.nameFieldWidth)
                        .onSubmit { store.send(.updateTapped) }
                    }
                    if store.nameError == .empty {
                        MacFormRow {
                            Text(L10n.ServerDetails.nameErrorEmpty).foregroundStyle(Color.negativeText)
                        } control: {
                            EmptyView()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: .space8) {
                    MacFormGroup {
                        MacFormRow(L10n.ServerDetails.urlLabel) {
                            Text(store.serverURL.absoluteString)
                                .type(.body2(.regular), style: .secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                    }
                    Text(L10n.ServerDetails.urlFootnote)
                        .type(.body3(.regular), style: .secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, .space4)
                }
                if let error = store.errorMessage {
                    MacNote(error, kind: .error)
                }
            }
            .disabled(store.isSaving)
            .fileImporter(isPresented: $isChoosingIcon, allowedContentTypes: [.image]) { result in
                guard case let .success(url) = result else { return }
                loadIcon(at: url)
            }
            .onAppear { store.send(.onAppear) }
        }

        private func loadIcon(at url: URL) {
            Task {
                let data = await Task.detached(priority: .userInitiated) { () -> Data? in
                    let scoped = url.startAccessingSecurityScopedResource()
                    defer {
                        if scoped {
                            url.stopAccessingSecurityScopedResource()
                        }
                    }
                    return NSImage(contentsOf: url).flatMap(ServerDetailsView.prepareLogo)
                }.value
                if let data {
                    store.send(.logoPicked(data))
                } else {
                    store.send(.logoPickFailed)
                }
            }
        }
    }

    #Preview("Server") {
        MacServerSettingsPane(store: Store(initialState: ServerDetailsFeature.State(
            serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
            branding: Branding(appName: "Rivendell Cloud", appLogoUrl: Branding.defaultLogoPath)
        )) { ServerDetailsFeature() } withDependencies: { $0.filesClient = .previewValue })
            .previewCanvas(.settingsWindow)
    }
#endif
