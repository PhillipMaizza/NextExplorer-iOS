import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    static let statusSpacing: CGFloat = .space16
    static let statusPadding: CGFloat = .space24
}

/// Full-screen host for `OfficeEditorFeature` — a loading state, an error state with retry,
/// and the editor web view itself once a launch payload arrives.
struct OfficeEditorView: View {
    @Bindable var store: StoreOf<OfficeEditorFeature>

    var body: some View {
        NavigationStack {
            content
                .background(Color.backgroundPrimary.ignoresSafeArea())
                .navigationTitle(store.item.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { store.send(.doneTapped) } label: {
                            IconKit.close.foregroundStyle(Color.primaryDS)
                        }
                        .accessibilityLabel(L10n.Common.done)
                    }
                }
        }
        .task { store.send(.onAppear) }
    }

    @ViewBuilder
    private var content: some View {
        switch store.phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .failed(message):
            VStack(spacing: Constants.statusSpacing) {
                DSErrorCard(message)
                DSButton(L10n.Common.retry, style: .secondary) { store.send(.retryTapped) }
            }
            .padding(Constants.statusPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case let .onlyOffice(documentServerURL, configJSON):
            OfficeWebView(load: .onlyOfficeShim(documentServerURL: documentServerURL, configJSON: configJSON))
                .ignoresSafeArea(edges: .bottom)

        case let .collabora(url):
            OfficeWebView(load: .url(url))
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

#Preview("Loading") {
    OfficeEditorView(
        store: Store(
            initialState: OfficeEditorFeature.State(
                serverURL: URL(string: "https://files.example.com")!,
                item: FileItem(name: "Q3 Report.docx", path: "Docs", dateModified: Date(), size: 12_000, kind: "docx"),
                editor: .onlyOffice,
                mode: .edit
            )
        ) { OfficeEditorFeature() } withDependencies: {
            $0.filesClient.fetchOnlyOfficeConfig = { _, _, _ in
                try await Task.never()
            }
        }
    )
}

#Preview("Error") {
    OfficeEditorView(
        store: Store(
            initialState: OfficeEditorFeature.State(
                serverURL: URL(string: "https://files.example.com")!,
                item: FileItem(name: "Budget.xlsx", path: "Docs", dateModified: Date(), size: 8_000, kind: "xlsx"),
                editor: .collabora,
                mode: .edit
            )
        ) { OfficeEditorFeature() } withDependencies: {
            $0.filesClient.fetchCollaboraConfig = { _, _, _ in
                throw FilesClientError.serverMessage(statusCode: 400, message: L10n.OfficeEditor.loadFailed)
            }
        }
    )
}
