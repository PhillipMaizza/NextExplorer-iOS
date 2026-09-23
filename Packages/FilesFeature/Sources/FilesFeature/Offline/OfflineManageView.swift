import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

private enum Constants {
    static let rowIconSize: CGFloat = .iconMedium

    @MainActor static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()
}

/// The "Manage Offline Files" screen: one row per pinned root with its size and a swipe-to-remove.
struct OfflineManageView: View {
    @Bindable var store: StoreOf<OfflineManageFeature>

    var body: some View {
        Group {
            if store.isEmpty {
                EmptyStateView(icon: IconKit.cloud, message: L10n.Offline.manageEmpty)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DSGroupedList {
                    Section {
                        ForEach(Array(store.usages.enumerated()), id: \.element.id) { index, usage in
                            OfflineManageRow(usage: usage, appearIndex: index) {
                                store.send(.removeTapped(path: usage.root.path), animation: .default)
                            }
                        }
                    } footer: {
                        Text(L10n.Offline.available(Constants.byteFormatter.string(fromByteCount: store.totalBytes)))
                            .type(.body3(.regular), style: .tertiary)
                    }
                    .listRowBackground(Color.backgroundSecondary)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .backgroundGradient()
        .navigationTitle(L10n.Offline.manageTitle)
        .navigationBarTitleDisplayMode(.inline)
        .task { store.send(.onAppear) }
    }
}

private struct OfflineManageRow: View {
    let usage: OfflinePinnedRootUsage
    var appearIndex: Int = 0
    let onRemove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    private static let appearStep: Double = 0.05
    private static let appearMaxDelay: Double = 0.4
    private static let appearDuration: Double = 0.3

    private var name: String {
        let last = (usage.root.path as NSString).lastPathComponent
        return last.isEmpty ? usage.root.path : last
    }

    private var content: some View {
        HStack(spacing: .space12) {
            (usage.root.isDirectory ? IconKit.folder : IconKit.document)
                .resizable()
                .scaledToFit()
                .foregroundStyle(usage.root.isDirectory ? Color.accent : Color.secondaryDS)
                .frame(width: Constants.rowIconSize, height: Constants.rowIconSize)
            VStack(alignment: .leading, spacing: .space2) {
                Text(name)
                    .type(.body2(.regular), style: .primaryOnSurface)
                    .lineLimit(1)
                if !usage.root.path.isEmpty {
                    Text(usage.root.path)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }
            Spacer()
            Text(Constants.byteFormatter.string(fromByteCount: usage.sizeBytes))
                .type(.body3(.regular), style: .tertiary)
                .monospacedDigit()
        }
        .swipeActions(edge: .trailing) {
            removeButton
        }
        #if os(macOS)
        .contextMenu { removeButton }
        #endif
    }

    private var removeButton: some View {
        Button(role: .destructive, action: onRemove) {
            Label(L10n.Common.remove, systemImage: "trash")
        }
    }

    var body: some View {
        content
            .opacity(hasAppeared || reduceMotion ? 1 : 0)
            .offset(y: hasAppeared || reduceMotion ? 0 : .space8)
            .onAppear {
                guard !reduceMotion else { hasAppeared = true; return }
                let delay = min(Double(appearIndex) * Self.appearStep, Self.appearMaxDelay)
                withAnimation(.easeOut(duration: Self.appearDuration).delay(delay)) {
                    hasAppeared = true
                }
            }
    }
}

#Preview("Manage") {
    NavigationStack {
        OfflineManageView(
            store: Store(
                initialState: {
                    var state = OfflineManageFeature.State()
                    state.usages = [
                        OfflinePinnedRootUsage(root: OfflinePinnedRoot(path: "Documents", isDirectory: true), sizeBytes: 45_000_000),
                        OfflinePinnedRootUsage(root: OfflinePinnedRoot(path: "Photos/trip.jpg", isDirectory: false), sizeBytes: 3_200_000),
                    ]
                    return state
                }()
            ) {
                OfflineManageFeature()
            }
        )
    }
}
