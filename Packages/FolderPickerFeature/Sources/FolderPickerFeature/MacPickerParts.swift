#if os(macOS)
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    public struct MacPickerItemTile: Sendable {
        let make: @MainActor @Sendable (FileItem, CGFloat) -> AnyView

        public init(_ make: @escaping @MainActor @Sendable (FileItem, CGFloat) -> AnyView) {
            self.make = make
        }
    }

    public extension EnvironmentValues {
        @Entry var macPickerItemTile: MacPickerItemTile?
    }

    enum MacPickerMetrics {
        static let width: CGFloat = 720
        static let bodyHeight: CGFloat = 330
        static let sidebarWidth: CGFloat = 190
        static let searchWidth: CGFloat = 200
        static let barHeight: CGFloat = .size40
        static let rowHeight: CGFloat = .size32
        static let tileSize: CGFloat = 22
        static let stackTile: CGFloat = .size32
        static let stackStep: CGFloat = .size16
        static let stackHeight: CGFloat = .size44
        static let stackTilt: Double = 8
        static let stackRing: CGFloat = .size2
    }

    private typealias Metrics = MacPickerMetrics

    struct MacPickerItemStack: View {
        let items: [FileItem]
        @Environment(\.macPickerItemTile) private var tile

        private var shown: [FileItem] {
            Array(items.prefix(3))
        }

        var body: some View {
            ZStack(alignment: .leading) {
                ForEach(Array(shown.enumerated()), id: \.element.id) { index, item in
                    let shape = RoundedRectangle(cornerRadius: Metrics.stackTile * .tileCornerRatio, style: .continuous)
                    tileView(item)
                        .frame(width: Metrics.stackTile, height: Metrics.stackTile)
                        .background(Color.macCard, in: shape)
                        .clipShape(shape)
                        .overlay(shape.strokeBorder(Color.macCard, lineWidth: Metrics.stackRing))
                        .rotationEffect(.degrees(tilt(index)))
                        .offset(x: CGFloat(index) * Metrics.stackStep)
                }
            }
            .frame(
                width: Metrics.stackTile + CGFloat(max(shown.count - 1, 0)) * Metrics.stackStep,
                height: Metrics.stackHeight,
                alignment: .leading
            )
            .environment(\.backgroundProminence, .increased)
            .accessibilityHidden(true)
        }

        @ViewBuilder
        private func tileView(_ item: FileItem) -> some View {
            if let tile {
                tile.make(item, Metrics.stackTile)
            } else {
                MacFolderTile(
                    size: Metrics.stackTile,
                    glyph: item.isDirectory ? IconKit.folderFill : IconKit.document,
                    tint: item.isDirectory ? .accent : .secondaryDS
                )
            }
        }

        private func tilt(_ index: Int) -> Double {
            guard shown.count > 1 else { return .zero }
            return -Metrics.stackTilt + 2 * Metrics.stackTilt * Double(index) / Double(shown.count - 1)
        }
    }

    struct MacPickerSidebar: View {
        let recents: [String]
        let locations: [FileItem]
        let activeLocation: String?
        let directoryPath: String
        let onRecent: (String) -> Void
        let onLocation: (String) -> Void

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: .space2) {
                    if !recents.isEmpty {
                        heading(L10n.Browse.destinationPickerRecent)
                        ForEach(recents, id: \.self) { path in
                            row(
                                PersonalSpace.folderTitle(path),
                                glyph: path == PersonalSpace.rootPath ? IconKit.person : IconKit.folderFill,
                                isActive: path == directoryPath
                            ) { onRecent(path) }
                        }
                    }
                    if !locations.isEmpty {
                        heading(L10n.Browse.destinationPickerLocations)
                            .padding(.top, recents.isEmpty ? .zero : .space8)
                        ForEach(locations) { location in
                            row(
                                PersonalSpace.displayName(forSegment: location.name, isFirstSegment: true),
                                glyph: location.id == PersonalSpace.rootPath ? IconKit.person : IconKit.drive,
                                isActive: location.id == activeLocation
                            ) { onLocation(location.id) }
                        }
                    }
                }
                .padding(.space8)
            }
            .frame(width: Metrics.sidebarWidth)
            .background(Color.macRow)
        }

        private func heading(_ title: String) -> some View {
            Text(title)
                .type(.caption(.semibold), style: .secondary)
                .padding(.horizontal, .space8)
                .padding(.top, .space4)
                .padding(.bottom, .space2)
                .accessibilityAddTraits(.isHeader)
        }

        private func row(_ title: String, glyph: Image, isActive: Bool, action: @escaping () -> Void) -> some View {
            Button(action: action) {
                HStack(spacing: .space8) {
                    MacFolderTile(size: Metrics.tileSize, glyph: glyph)
                        .environment(\.backgroundProminence, isActive ? .increased : .standard)
                    Text(title)
                        .type(.body2(.regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: .zero)
                }
                .foregroundStyle(Color.macChromeText)
                .padding(.horizontal, .space8)
                .frame(height: Metrics.rowHeight)
                .background(
                    RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                        .fill(isActive ? Color.macSelection : .clear)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isActive ? .isSelected : [])
        }
    }

    struct MacPickerPathBar: View {
        let crumbs: [PathCrumb]
        let isRefining: Bool
        let onBack: () -> Void
        let onCrumb: (String) -> Void

        var body: some View {
            HStack(spacing: .space4) {
                MacIconButton(IconKit.back, label: L10n.Common.back, isFilled: false, size: .compact, action: onBack)
                    .disabled(crumbs.isEmpty)
                if crumbs.isEmpty {
                    Text(L10n.Browse.navigationTitle).type(.body3(.semibold))
                }
                ForEach(Array(crumbs.enumerated()), id: \.element.path) { index, crumb in
                    if index > 0 {
                        IconKit.chevronRight
                            .imageScale(.small)
                            .foregroundStyle(Color.macChromeSecondary)
                            .accessibilityHidden(true)
                    }
                    if index == crumbs.count - 1 {
                        Text(crumb.title)
                            .type(.body3(.semibold))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .layoutPriority(1)
                    } else {
                        Button(crumb.title) { onCrumb(crumb.path) }
                            .buttonStyle(.plain)
                            .type(.body3(.semibold), style: .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: .zero)
                if isRefining {
                    DSSpinner(size: .small)
                        .macDialogReveal()
                }
            }
            .foregroundStyle(Color.macChromeText)
            .padding(.horizontal, .space8)
            .frame(height: Metrics.barHeight)
        }
    }

    struct MacPickerNewFolderSheet: View {
        let store: StoreOf<DestinationPickerFeature>
        @FocusState private var isFocused: Bool

        private var draft: DestinationPickerFeature.NewFolderDraft {
            store.newFolder ?? .init()
        }

        var body: some View {
            MacFormSheet(
                title: L10n.Browse.newFolderTitle,
                confirmTitle: L10n.Browse.newFolderConfirm,
                isConfirmEnabled: draft.canCreate,
                isWorking: draft.phase == .loading,
                errorMessage: draft.phase.errorMessage,
                onCancel: { store.send(.newFolderCancelled) },
                onConfirm: { store.send(.newFolderConfirmed) }
            ) {
                MacFormSheetRow(L10n.Browse.renameNamePlaceholder) {
                    MacTextField(
                        L10n.Browse.newFolderPlaceholder,
                        text: Binding(get: { draft.name }, set: { store.send(.newFolderNameChanged($0)) }),
                        prompt: L10n.Browse.newFolderPlaceholder,
                        isInvalid: draft.problem != nil
                    )
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    .onSubmit { store.send(.newFolderConfirmed) }
                    if let problem = draft.problem {
                        Text(problem)
                            .type(.body3(.regular), style: .error)
                            .macDialogReveal()
                    }
                }
            }
            .task { isFocused = true }
        }
    }

    struct MacPickerRow: View {
        let name: String
        let detail: String?
        let isDirectory: Bool
        let showsChevron: Bool
        var isSelected = false
        var glyph = IconKit.folderFill

        var body: some View {
            HStack(spacing: .space8) {
                if isDirectory {
                    MacFolderTile(size: Metrics.tileSize, glyph: glyph)
                        .environment(\.backgroundProminence, isSelected ? .increased : .standard)
                } else {
                    IconKit.document
                        .foregroundStyle(Color.macChromeSecondary)
                        .frame(width: Metrics.tileSize)
                        .accessibilityHidden(true)
                }
                Text(name)
                    .type(.body2(.regular))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: .space8)
                if let detail {
                    Text(detail)
                        .type(.body3(.regular), style: .secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
                if showsChevron {
                    IconKit.chevronRight
                        .imageScale(.small)
                        .foregroundStyle(Color.macChromeSecondary)
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(Color.macChromeText)
            .frame(minHeight: Metrics.rowHeight)
            .accessibilityElement(children: .combine)
        }
    }

    #Preview("Item stack and path bar") {
        VStack(alignment: .leading, spacing: .space16) {
            MacPickerItemStack(items: [
                FileItem(name: "Q3 Report.pdf", path: "Projects", dateModified: .distantPast, size: 0, kind: "pdf"),
                FileItem(name: "Budget.xlsx", path: "Projects", dateModified: .distantPast, size: 0, kind: "xlsx"),
                FileItem(
                    name: "Photos",
                    path: "Projects",
                    dateModified: .distantPast,
                    size: 0,
                    kind: FileItem.directoryKind
                ),
            ])
            MacPickerPathBar(
                crumbs: PathCrumb.trail(for: "personal/Projects"),
                isRefining: false,
                onBack: {},
                onCrumb: { _ in }
            )
        }
        .padding()
        .frame(width: 420)
        .background(Color.macCard)
    }
#endif
