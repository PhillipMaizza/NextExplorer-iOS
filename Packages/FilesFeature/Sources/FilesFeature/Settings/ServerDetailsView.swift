import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import PhotosUI
import SwiftUI
import UIKit

private enum Metrics {
    static let contentSpacing: CGFloat = .space16
    static let horizontalPadding: CGFloat = .space16
    static let sectionSpacing: CGFloat = .space32
    static let fieldSpacing: CGFloat = .space4
    static let logoSize: CGFloat = .size96
    static let logoBadgeSize: CGFloat = .size32
    static let logoBadgeIcon: CGFloat = .iconXSmall
    static let logoBadgeBorder: CGFloat = 2
    static let disabledFieldOpacity: Double = 0.55
    /// Longest edge the uploaded logo is downscaled to before encoding.
    static let logoMaxPixelSize: CGFloat = 512
    static let logoJPEGQuality: CGFloat = 0.85
}

/// Admin-only editor for the server's app name and logo, pushed from the Settings server row.
/// Mirrors the web client's `SettingsBranding.vue`. The server address is fixed and read only.
struct ServerDetailsView: View {
    @Bindable var store: StoreOf<ServerDetailsFeature>

    @State private var isCameraPresented = false
    @State private var isCameraDeniedAlertPresented = false
    @State private var isGalleryPickerPresented = false
    @State private var gallerySelection: PhotosPickerItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.contentSpacing) {
                detailsCard

                if let error = store.errorMessage {
                    DSErrorCard(error)
                }

                DSButton(L10n.ServerDetails.updateButton, style: .primary, isLoading: store.isSaving) {
                    store.send(.updateTapped)
                }
                .disabled(!store.isSaveEnabled)
                .padding(.top, .space4)
            }
            .padding(.horizontal, Metrics.horizontalPadding)
            .padding(.top, Metrics.logoSize / 2 + Metrics.contentSpacing)
            .padding(.bottom, Metrics.contentSpacing)
        }
        .backgroundGradient()
        .navigationTitle(L10n.ServerDetails.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        .fullScreenCover(isPresented: $isCameraPresented) {
            PhotoCapturePicker { image in
                isCameraPresented = false
                if let image {
                    handlePicked(image)
                }
            }
            .ignoresSafeArea()
        }
        .photosPicker(isPresented: $isGalleryPickerPresented, selection: $gallerySelection, matching: .images)
        .onChange(of: gallerySelection) { _, item in
            guard let item else { return }
            gallerySelection = nil
            Task { await loadGalleryImage(item) }
        }
        .sheet(isPresented: $isCameraDeniedAlertPresented) {
            DSAlertSheet(
                icon: IconKit.camera,
                title: L10n.ServerDetails.cameraDeniedTitle,
                message: L10n.ServerDetails.cameraDeniedMessage,
                confirmTitle: L10n.Common.openSettings,
                dismissTitle: L10n.Common.cancel,
                closeAccessibilityLabel: L10n.Common.close,
                onConfirm: {
                    isCameraDeniedAlertPresented = false
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                },
                onDismiss: { isCameraDeniedAlertPresented = false }
            )
        }
        .onAppear { store.send(.onAppear) }
    }

    // MARK: Card

    private var detailsCard: some View {
        Card {
            VStack(spacing: Metrics.sectionSpacing) {
                section(L10n.ServerDetails.nameLabel, error: nameErrorText) {
                    DSTextField(
                        L10n.ServerDetails.namePlaceholder,
                        text: $store.nameDraft.sending(\.nameChanged)
                    )
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                }

                section(L10n.ServerDetails.urlLabel) {
                    DSTextField(L10n.ServerDetails.urlLabel, text: .constant(store.serverURL.absoluteString))
                        .disabled(true)
                        .opacity(Metrics.disabledFieldOpacity)
                    Text(L10n.ServerDetails.urlFootnote)
                        .type(.body3(.regular), style: .tertiary)
                }
            }
            .padding(.top, Metrics.logoSize / 2)
            .padding(.vertical, .space8)
        }
        .overlay(alignment: .top) {
            logoPicker
                .alignmentGuide(.top) { dimension in dimension[VerticalAlignment.center] }
        }
    }

    @ViewBuilder
    private func section(
        _ title: String,
        error: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.fieldSpacing) {
            DSFieldLabel(title, uppercased: false)
            content()
            if let error {
                Text(error).type(.body3(.semibold), style: .error)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var nameErrorText: String? {
        switch store.nameError {
        case .empty: L10n.ServerDetails.nameErrorEmpty
        case nil: nil
        }
    }

    /// Tapping the logo opens the source menu directly — no separate button.
    private var logoPicker: some View {
        Menu {
            Button { requestCamera() } label: {
                Label(L10n.ServerDetails.takePhoto, systemImage: "camera")
            }
            Button { isGalleryPickerPresented = true } label: {
                Label(L10n.ServerDetails.chooseFromGallery, systemImage: "photo.on.rectangle")
            }
        } label: {
            ServerLogoThumbnail(
                branding: store.branding,
                serverURL: store.serverURL,
                size: Metrics.logoSize,
                overrideImageData: store.pendingLogoData
            )
            .overlay(alignment: .bottomTrailing) { logoBadge }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.ServerDetails.changeLogo)
    }

    private var logoBadge: some View {
        Image(systemName: "camera.fill")
            .resizable().scaledToFit()
            .frame(width: Metrics.logoBadgeIcon, height: Metrics.logoBadgeIcon)
            .foregroundStyle(Color.white)
            .frame(width: Metrics.logoBadgeSize, height: Metrics.logoBadgeSize)
            .background(Circle().fill(Color.accent))
            .overlay(Circle().strokeBorder(Color.backgroundSecondary, lineWidth: Metrics.logoBadgeBorder))
    }

    // MARK: Pickers

    private func requestCamera() {
        Task {
            if await CameraAccess.resolve() {
                isCameraPresented = true
            } else {
                isCameraDeniedAlertPresented = true
            }
        }
    }

    private func loadGalleryImage(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data)
        else {
            store.send(.logoPickFailed)
            return
        }
        handlePicked(image)
    }

    private func handlePicked(_ image: UIImage) {
        if let prepared = Self.prepareLogo(image) {
            store.send(.logoPicked(prepared))
        } else {
            store.send(.logoPickFailed)
        }
    }

    /// Square-crop-agnostic downscale + JPEG encode, rejecting anything still over the 2 MB
    /// the server (and `ServerDetailsFeature`) cap uploads at.
    static func prepareLogo(_ image: UIImage) -> Data? {
        let longestEdge = max(image.size.width, image.size.height)
        let scale = longestEdge > Metrics.logoMaxPixelSize ? Metrics.logoMaxPixelSize / longestEdge : 1
        let targetSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        guard let data = resized.jpegData(compressionQuality: Metrics.logoJPEGQuality),
              data.count <= ServerDetailsFeature.maxLogoBytes else { return nil }
        return data
    }
}

// MARK: - Previews

@MainActor
private func previewStore(
    branding: Branding = Branding(appName: "Rivendell Cloud", appLogoUrl: Branding.defaultLogoPath),
    _ mutate: @Sendable (inout ServerDetailsFeature.State) -> Void = { _ in }
) -> StoreOf<ServerDetailsFeature> {
    var state = ServerDetailsFeature.State(
        serverURL: URL(string: "https://cloud.rivendell.example.com")!,
        branding: branding
    )
    mutate(&state)
    return Store(initialState: state) {
        ServerDetailsFeature()
    } withDependencies: {
        $0.filesClient = .previewValue
        $0.filesClient.fetchBranding = { _ in branding }
    }
}

private let previewLogoData: Data = {
    let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
    return renderer.image { ctx in
        UIColor.systemIndigo.setFill()
        ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        UIColor.white.setFill()
        ctx.cgContext.fillEllipse(in: CGRect(x: 50, y: 50, width: 100, height: 100))
    }.jpegData(compressionQuality: 0.9) ?? Data()
}()

#Preview("Default logo") {
    NavigationStack { ServerDetailsView(store: previewStore()) }
}

#Preview("Photo picked — dirty") {
    NavigationStack {
        ServerDetailsView(store: previewStore {
            $0.nameDraft = "Rivendell Cloud"
            $0.pendingLogoData = previewLogoData
        })
    }
}

#Preview("Saving") {
    NavigationStack {
        ServerDetailsView(store: previewStore {
            $0.nameDraft = "Imladris"
            $0.isSaving = true
        })
    }
}

#Preview("Save error") {
    NavigationStack {
        ServerDetailsView(store: previewStore {
            $0.nameDraft = "Imladris"
            $0.errorMessage = "Couldn't reach the server. Check your connection and try again."
        })
    }
}

#Preview("Empty name") {
    NavigationStack {
        ServerDetailsView(store: previewStore { $0.nameDraft = "" })
    }
}
