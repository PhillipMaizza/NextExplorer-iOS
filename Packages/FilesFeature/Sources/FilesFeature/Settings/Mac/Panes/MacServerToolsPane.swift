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
                        MacServerToolRow(tool: tool)
                    }
                }
            }
        }
    }

    private struct MacServerToolRow: View {
        let tool: ServerCapability

        var body: some View {
            HStack(spacing: .space12) {
                tool.status.icon
                    .imageScale(.medium)
                    .foregroundStyle(tool.status.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: .space2) {
                    Text(tool.name)
                        .type(.body2(.regular))
                        .monospaced()
                    if let detail = tool.detail {
                        Text(detail).type(.body3(.regular), style: .secondary)
                    }
                }
                Spacer(minLength: .space8)
                MacChip(text: tool.statusTitle, tint: tool.status.tint, style: tool.status.textStyle, kind: .pill)
            }
            .padding(.vertical, .space4)
            .accessibilityElement(children: .combine)
        }
    }

    private extension ServerCapability.Status {
        var icon: Image {
            switch self {
            case .installed: IconKit.checkmarkCircleFill
            case .missing: IconKit.closeCircle
            case .notUsed: IconKit.removeCircle
            }
        }

        var tint: Color {
            switch self {
            case .installed: .positive
            case .missing: .negative
            case .notUsed: .tertiaryDS
            }
        }

        var textStyle: Typography.TextStyle {
            switch self {
            case .installed: .success
            case .missing: .error
            case .notUsed: .tertiary
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
            .previewCanvas(.settingsPane)
    }

    #Preview("Server tools, loading") {
        MacServerToolsPane(store: Store(initialState: {
            var state = ServerToolsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.phase = .loading
            return state
        }()) { ServerToolsFeature() })
            .previewCanvas(.settingsPane)
    }

    #Preview("Server tools, failed") {
        MacServerToolsPane(store: Store(initialState: {
            var state = ServerToolsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.phase = .failed(ServerSettingsPreview.errorMessage)
            return state
        }()) { ServerToolsFeature() })
            .previewCanvas(.settingsPane)
    }
#endif
