import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

/// What one program row says under its name: the version it printed, or what an admin needs to
/// install it. Shared by the iOS page and the Mac pane.
extension ServerCapability {
    enum Status: Comparable {
        case missing, installed, notUsed
    }

    var status: Status {
        if isAvailable {
            .installed
        } else if isUsed {
            .missing
        } else {
            .notUsed
        }
    }

    var statusTitle: String {
        switch status {
        case .installed: L10n.ServerTools.installed
        case .missing: L10n.ServerTools.missing
        case .notUsed: L10n.ServerTools.notUsed
        }
    }

    var detail: String? {
        var parts: [String] = []
        if isAvailable, let version {
            parts.append(version)
        } else if status == .missing, let installPackage {
            parts.append(L10n.ServerTools.package(installPackage))
        }
        if !missingFormats.isEmpty {
            parts.append(L10n.ServerTools.missingFormats(missingFormats.joined(separator: ", ")))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// Admin page listing the programs the server found, pushed from the Settings admin section.
struct ServerToolsView: View {
    let store: StoreOf<ServerToolsFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ServerSettingsMetrics.contentSpacing) {
                Text(L10n.ServerTools.subtitle)
                    .type(.body3(.regular), style: .secondary)
                if let message = store.phase.errorMessage {
                    DSErrorCard(message)
                    DSButton(L10n.Common.retry, icon: IconKit.retry, style: .secondary) { store.send(.onAppear) }
                        .formActionAlignment()
                } else if store.phase == .loading {
                    DSSpinner()
                } else {
                    Card {
                        VStack(alignment: .leading, spacing: .space16) {
                            ForEach(store.tools) { tool in
                                ServerToolRow(tool: tool)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, ServerSettingsMetrics.horizontalPadding)
            .padding(.vertical, ServerSettingsMetrics.contentSpacing)
        }
        .backgroundGradient()
        .navigationTitle(L10n.ServerTools.navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { store.send(.onAppear) }
    }
}

private struct ServerToolRow: View {
    let tool: ServerCapability

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: .space12) {
            VStack(alignment: .leading, spacing: .space4) {
                Text(tool.name).type(.body2(.semibold), style: .primaryOnSurface)
                if let detail = tool.detail {
                    Text(detail).type(.body3(.regular), style: .secondary)
                }
            }
            Spacer(minLength: .space8)
            Text(tool.statusTitle)
                .type(.body3(.semibold), style: tool.status == .missing ? .error : .secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

#Preview("Mixed") {
    NavigationStack {
        ServerToolsView(store: Store(initialState: {
            var state = ServerToolsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.tools = [
                ServerCapability(name: "ffmpeg", isAvailable: true, version: "7.1", installPackage: "ffmpeg"),
                ServerCapability(name: "ripgrep", isAvailable: false, installPackage: "ripgrep"),
                ServerCapability(name: "rsync", isAvailable: false, isUsed: false, installPackage: "rsync"),
                ServerCapability(
                    name: "7-Zip", isAvailable: true, version: "24.08", installPackage: "7zip", missingFormats: ["rar"]
                ),
            ]
            state.phase = .loaded
            return state
        }()) { ServerToolsFeature() })
    }
}

#Preview("Failed") {
    NavigationStack {
        ServerToolsView(store: Store(initialState: {
            var state = ServerToolsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.phase = .failed("Couldn't reach the server.")
            return state
        }()) { ServerToolsFeature() })
    }
}

#Preview("Loading") {
    NavigationStack {
        ServerToolsView(store: Store(initialState: {
            var state = ServerToolsFeature.State(serverURL: ServerSettingsPreview.serverURL)
            state.phase = .loading
            return state
        }()) { ServerToolsFeature() })
    }
}
