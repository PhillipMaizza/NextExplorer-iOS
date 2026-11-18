#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    /// The Server tools pane: the optional programs the server found, read only.
    struct MacServerToolsPane: View {
        let store: StoreOf<ServerToolsFeature>

        var body: some View {
            MacAdminPane(
                isUnavailable: false,
                unavailableMessage: "",
                failureMessage: store.phase.errorMessage,
                isLoadingFirstTime: store.phase == .loading,
                onAppear: { store.send(.onAppear) }
            ) {
                Section {
                    ForEach(store.tools) { tool in
                        LabeledContent {
                            Text(tool.statusTitle)
                                .foregroundStyle(tool.status == .missing ? Color.negativeText : Color.secondaryDS)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(tool.name)
                                if let detail = tool.detail {
                                    Text(detail).font(.callout).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                } footer: {
                    MacSectionFooter(L10n.ServerTools.subtitle)
                }
            }
        }
    }
#endif

#if os(macOS)
    #Preview("Server tools") {
        MacServerToolsPane(store: Store(initialState: {
            var state = ServerToolsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.tools = [
                ServerCapability(name: "ffmpeg", isAvailable: true, version: "7.1"),
                ServerCapability(name: "ripgrep", isAvailable: false, installPackage: "ripgrep"),
                ServerCapability(name: "rsync", isAvailable: false, isUsed: false),
            ]
            state.phase = .loaded
            return state
        }()) { ServerToolsFeature() })
            .frame(width: 520, height: 360)
    }
#endif
