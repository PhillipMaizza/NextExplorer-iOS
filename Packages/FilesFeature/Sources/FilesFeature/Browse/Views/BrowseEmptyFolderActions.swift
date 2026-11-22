import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI
#if os(iOS)
    import GameController
#endif

struct BrowseEmptyFolderActions: View {
    let store: StoreOf<BrowseFeature>
    let title: String
    let shouldKeepClipboard: Bool
    @Binding var isFilesPickerPresented: Bool
    @Binding var isPhotosPickerPresented: Bool
    @Binding var isCameraPresented: Bool
    @Binding var isCameraDeniedAlertPresented: Bool

    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @State private var hasKeyboard = GCKeyboard.coalesced != nil
    #endif

    var body: some View {
        if hasAnyAction {
            VStack(spacing: .space4) {
                Text(title)
                    .type(.headline4)
                    .foregroundStyle(Color.primaryDS)
                Text(L10n.EmptyState.folderEmpty)
                    .type(.body3(.regular), style: .secondary)
                Group {
                    if isCompact {
                        compactActions
                    } else {
                        tiles
                    }
                }
                .padding(.top, .space16)
                if let dropHint {
                    Text(dropHint)
                        .type(.caption(.regular), style: .secondary)
                        .padding(.top, .space12)
                }
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: maxWidth)
            .padding(.horizontal, .space16)
            #if os(iOS)
                .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidConnect)) { _ in
                    hasKeyboard = true
                }
                .onReceive(NotificationCenter.default.publisher(for: .GCKeyboardDidDisconnect)) { _ in
                    hasKeyboard = GCKeyboard.coalesced != nil
                }
            #endif
        } else {
            EmptyStateView(icon: IconKit.folder, message: L10n.EmptyState.folderEmpty)
        }
    }

    private var canUpload: Bool {
        store.canUploadHere
    }

    private var canCreateFolder: Bool {
        store.createAvailability.canCreateFolder
    }

    private var canCreateFile: Bool {
        store.createAvailability.canCreateFile
    }

    private var showsPaste: Bool {
        canCreateFolder
    }

    private var hasAnyAction: Bool {
        !store.isSelecting && (canUpload || canCreateFolder || canCreateFile)
    }

    private var isCompact: Bool {
        #if os(iOS)
            horizontalSizeClass == .compact
        #else
            false
        #endif
    }

    private var showsShortcuts: Bool {
        #if os(iOS)
            hasKeyboard
        #else
            true
        #endif
    }

    private var maxWidth: CGFloat {
        #if os(iOS)
            isCompact ? Constants.compactMaxWidth : Constants.padMaxWidth
        #else
            Constants.macMaxWidth
        #endif
    }

    private var columnCount: Int {
        #if os(iOS)
            Constants.padColumns
        #else
            Constants.macColumns
        #endif
    }

    private var dropHint: String? {
        guard canUpload else { return nil }
        #if os(iOS)
            return isCompact ? nil : L10n.EmptyState.dropHintFiles
        #else
            return L10n.EmptyState.dropHintFinder
        #endif
    }

    private var pasteTitle: String {
        BrowsePasteMenu.actionTitle(store)
    }

    private func paste() {
        store.send(.pasteTapped(keepItemsAfterCopy: shouldKeepClipboard), animation: DSMotion.listDiff)
    }

    private func uploadMenu(@ViewBuilder label: @escaping () -> some View) -> some View {
        UploadSourceMenu(
            label: label,
            isFilesPickerPresented: $isFilesPickerPresented,
            isPhotosPickerPresented: $isPhotosPickerPresented,
            isCameraPresented: $isCameraPresented,
            isCameraDeniedAlertPresented: $isCameraDeniedAlertPresented
        )
        .accessibilityLabelWithTooltip(L10n.Uploads.menuTitle)
    }

    private var tiles: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: .space8), count: columnCount),
            spacing: .space8
        ) {
            if canUpload {
                uploadMenu {
                    EmptyFolderTile(title: L10n.Uploads.menuTitle, icon: IconKit.upload, shortcut: nil)
                }
            }
            ForEach(createActions) { action in
                Button(action: action.perform) {
                    EmptyFolderTile(
                        title: action.title,
                        icon: action.icon,
                        shortcut: showsShortcuts ? action.shortcut.glyphs : nil
                    )
                }
                .buttonStyle(DSPressableButtonStyle())
                .disabled(!action.isEnabled)
            }
        }
    }

    private var compactActions: some View {
        VStack(spacing: .space12) {
            if canUpload {
                uploadMenu { EmptyFolderUploadLabel() }
            }
            DSFlowLayout(horizontalSpacing: .space8, verticalSpacing: .space8, isRowCentered: true) {
                ForEach(createActions) { action in
                    Button(action: action.perform) {
                        EmptyFolderPill(title: action.title, icon: action.icon)
                    }
                    .buttonStyle(DSPressableButtonStyle())
                    .disabled(!action.isEnabled)
                }
            }
        }
    }

    private var createActions: [EmptyFolderAction] {
        var actions: [EmptyFolderAction] = []
        if canCreateFolder {
            actions.append(EmptyFolderAction(
                title: L10n.Browse.actionNewFolder,
                icon: IconKit.newFolder,
                shortcut: BrowseShortcut.newFolder,
                perform: { store.send(.newFolderTapped) }
            ))
        }
        if canCreateFile {
            actions.append(EmptyFolderAction(
                title: L10n.Browse.actionNewFile,
                icon: IconKit.newFile,
                shortcut: BrowseShortcut.newFile,
                perform: { store.send(.newFileTapped) }
            ))
        }
        if showsPaste {
            actions.append(EmptyFolderAction(
                title: pasteTitle,
                icon: IconKit.paste,
                shortcut: BrowseShortcut.paste,
                isEnabled: BrowsePasteMenu.canPaste(store),
                perform: paste
            ))
        }
        return actions
    }
}

private struct EmptyFolderAction: Identifiable {
    let title: String
    let icon: Image
    let shortcut: KeyboardShortcut
    var isEnabled = true
    let perform: () -> Void

    var id: String {
        title
    }
}

private struct EmptyFolderTile: View {
    let title: String
    let icon: Image
    let shortcut: String?

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        VStack(alignment: .leading, spacing: .space8) {
            HStack(spacing: .space4) {
                icon
                    .resizable()
                    .scaledToFit()
                    .frame(width: Constants.tileIconSize, height: Constants.tileIconSize)
                    .foregroundStyle(Color.accentText)
                Spacer(minLength: .space4)
                if let shortcut {
                    Text(shortcut)
                        .type(.caption(.regular), style: .secondary)
                        .monospacedDigit()
                }
            }
            Text(title)
                .type(.label4)
                .foregroundStyle(Color.primaryDS)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
        }
        .padding(.space12)
        .frame(maxWidth: .infinity, minHeight: Constants.tileMinHeight, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: .radiusControl).fill(Color.backgroundSecondary))
        .overlay(
            RoundedRectangle(cornerRadius: .radiusControl)
                .stroke(Color.borderPrimary, lineWidth: .borderWidthHairline)
        )
        .contentShape(RoundedRectangle(cornerRadius: .radiusControl))
        .opacity(isEnabled ? 1 : Constants.disabledOpacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(.isButton)
    }
}

private struct EmptyFolderUploadLabel: View {
    var body: some View {
        HStack(spacing: .space8) {
            IconKit.upload
            Text(L10n.Uploads.menuTitle)
        }
        .type(.label3)
        .foregroundStyle(Color.onAccent)
        .padding(.horizontal, .space24)
        .frame(minHeight: .size40)
        .background(RoundedRectangle(cornerRadius: .radiusControl).fill(Color.accent))
        .contentShape(RoundedRectangle(cornerRadius: .radiusControl))
    }
}

private struct EmptyFolderPill: View {
    let title: String
    let icon: Image

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        HStack(spacing: .space8) {
            icon
                .imageScale(.small)
                .foregroundStyle(Color.accentText)
            Text(title)
                .type(.label4)
                .foregroundStyle(Color.primaryDS)
                .lineLimit(1)
        }
        .padding(.horizontal, .space12)
        .frame(minHeight: Constants.pillMinHeight)
        .background(Capsule().fill(Color.backgroundSecondary))
        .contentShape(Capsule())
        .opacity(isEnabled ? 1 : Constants.disabledOpacity)
    }
}

private enum Constants {
    static let compactMaxWidth: CGFloat = 360
    static let padMaxWidth: CGFloat = 560
    static let macMaxWidth: CGFloat = 400
    static let padColumns = 4
    static let macColumns = 2
    static let tileMinHeight: CGFloat = 72
    static let tileIconSize: CGFloat = 20
    static let pillMinHeight: CGFloat = 36
    static let disabledOpacity: Double = 0.4
}

@MainActor
private func emptyFolderPreview(
    access: FileAccess = FileAccess(
        canRead: true, canWrite: true, canUpload: true, canDelete: true, canShare: true, canDownload: true
    ),
    clipboard: FileClipboard? = nil
) -> some View {
    let store = Store(initialState: BrowseFeature.State.preview(mutate: {
        $0.access = access
        $0.$clipboard.withLock { $0 = clipboard }
    })) {
        BrowseFeature()
    }
    return BrowseEmptyFolderActions(
        store: store,
        title: "Projects",
        shouldKeepClipboard: false,
        isFilesPickerPresented: .constant(false),
        isPhotosPickerPresented: .constant(false),
        isCameraPresented: .constant(false),
        isCameraDeniedAlertPresented: .constant(false)
    )
}

#Preview("Empty folder: clipboard empty") {
    emptyFolderPreview()
}

#Preview("Empty folder: three items to paste") {
    emptyFolderPreview(clipboard: FileClipboard(
        items: [
            FileItem(name: "a.pdf", path: "Documents", dateModified: Date(), size: 1_024, kind: "pdf"),
            FileItem(name: "b.pdf", path: "Documents", dateModified: Date(), size: 1_024, kind: "pdf"),
            FileItem(name: "c.pdf", path: "Documents", dateModified: Date(), size: 1_024, kind: "pdf"),
        ],
        operation: .copy
    ))
}

#Preview("Empty folder: read only") {
    emptyFolderPreview(access: FileAccess(
        canRead: true, canWrite: false, canUpload: false, canDelete: false, canShare: true, canDownload: true,
        canCreateFolder: false, canCreateFile: false
    ))
}
