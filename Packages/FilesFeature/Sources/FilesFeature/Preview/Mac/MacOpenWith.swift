#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let rawTextSheetWidth: CGFloat = 760
        static let rawTextSheetHeight: CGFloat = 560
        static let buttonSpacing: CGFloat = .space12
        /// The spinner sits just outside the buttons while the file downloads.
        static let workingIndicatorOffset: CGFloat = .space32
    }

    /// An installed app Launch Services says can open a file type.
    /// Toolbar menu on every Mac preview: open in the default app, pick another app, or read the
    /// raw text.
    struct MacOpenWithMenu: View {
        @State private var model: MacOpenWithModel

        init(source: SystemShareSource) {
            _model = State(initialValue: MacOpenWithModel(source: source))
        }

        var body: some View {
            let apps = model.apps
            Menu {
                if let preferred = apps?.preferred {
                    Button { model.open(with: nil) } label: {
                        Label { Text(L10n.OpenWith.openIn(preferred.name)) } icon: { preferred.icon }
                    }
                }
                if let all = apps?.all, !all.isEmpty {
                    Menu(L10n.OpenWith.openWith) {
                        ForEach(all) { app in
                            Button { model.open(with: app) } label: {
                                Label { Text(app.name) } icon: { app.icon }
                            }
                        }
                    }
                }
                Divider()
                if model.canViewAsText {
                    Button { model.viewAsText() } label: {
                        Label { Text(L10n.OpenWith.viewAsText) } icon: { MenuIcon.viewAsText.image }
                    }
                }
                if model.printKind != nil {
                    Button { model.print() } label: {
                        Label { Text(L10n.OpenWith.print) } icon: { MenuIcon.print.image }
                    }
                }
            } label: {
                MacIconGlyph(MenuIcon.openWith.image)
                    .macWorking(model.isWorking)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabelWithTooltip(L10n.OpenWith.openWith)
            .focusedSceneValue(\.printPreview, model.printKind == nil ? nil : FocusedMenuAction { model.print() })
            .modifier(MacOpenWithPresentation(model: model))
        }
    }

    /// Open in the default app and Open With, for a file's right click menu in the Mac table.
    /// The model downloads the file first; a failure goes to `onFailure` since a closed menu has
    /// nowhere to show it.
    struct MacOpenWithMenuItems: View {
        let item: FileItem
        let serverURL: URL
        let onFailure: (String) -> Void
        var includesDefaultApp = true

        var body: some View {
            let apps = MacOpenWithApp.apps(forFileNamed: item.name)
            if includesDefaultApp, let preferred = apps.preferred {
                Button { model().open(with: nil) } label: {
                    Label { Text(L10n.OpenWith.openIn(preferred.name)) } icon: { preferred.icon }
                }
                .tint(.primaryDS)
            }
            if !apps.all.isEmpty {
                Menu {
                    ForEach(apps.all) { app in
                        Button { model().open(with: app) } label: {
                            Label { Text(app.name) } icon: { app.icon }
                        }
                    }
                } label: {
                    Label { Text(L10n.OpenWith.openWith) } icon: { MenuIcon.openWith.image }
                }
                .tint(.primaryDS)
            }
        }

        /// A fresh model per click; its task keeps it alive until the open finishes.
        private func model() -> MacOpenWithModel {
            MacOpenWithModel(source: .remote(item, serverURL: serverURL), onFailure: onFailure)
        }
    }

    struct MacOpenWithSplitButton: View {
        @State private var model: MacOpenWithModel
        @Environment(\.macPreviewDownload) private var download

        init(source: SystemShareSource) {
            _model = State(initialValue: MacOpenWithModel(source: source))
        }

        var body: some View {
            let apps = model.apps
            let others = apps.map { lookup in lookup.all.filter { $0.id != lookup.preferred?.id } } ?? []
            VStack(spacing: Metrics.buttonSpacing) {
                if let preferred = apps?.preferred {
                    if others.isEmpty {
                        Button { model.open(with: nil) } label: { openLabel(preferred) }
                            .buttonStyle(.macDS(.primary))
                    } else {
                        MacSplitButton(menuLabel: L10n.OpenWith.openWith) {
                            model.open(with: nil)
                        } label: {
                            openLabel(preferred)
                        } items: {
                            appItems(others)
                        }
                    }
                } else if !others.isEmpty {
                    MacPopupMenu(L10n.OpenWith.openWith, valueLabel: L10n.OpenWith.openWith) {
                        appItems(others)
                    }
                } else if apps != nil, !model.canViewAsText, let download {
                    Button(L10n.Common.download, action: download.perform)
                        .buttonStyle(.macDS(.primary))
                }
                if model.canViewAsText {
                    Button(L10n.OpenWith.viewAsText) { model.viewAsText() }
                        .buttonStyle(.macDS(.tertiary))
                }
            }
            .disabled(model.isWorking)
            .overlay(alignment: .trailing) {
                if model.isWorking {
                    MacSpinner().offset(x: Metrics.workingIndicatorOffset)
                }
            }
            .modifier(MacOpenWithPresentation(model: model))
        }

        private func openLabel(_ app: MacOpenWithApp) -> some View {
            Label { Text(L10n.OpenWith.openIn(app.name)) } icon: { app.icon }
        }

        private func appItems(_ apps: [MacOpenWithApp]) -> some View {
            ForEach(apps) { app in
                Button { model.open(with: app) } label: {
                    Label { Text(app.name) } icon: { app.icon }
                }
            }
        }
    }

    private struct MacOpenWithPresentation: ViewModifier {
        @Bindable var model: MacOpenWithModel

        func body(content: Content) -> some View {
            content
                .sheet(item: $model.rawText) { document in
                    RawTextSheet(document: document)
                }
                .featureToast(error: model.errorMessage)
        }
    }

    private struct RawTextSheet: View {
        let document: RawTextDocument
        @Environment(\.dismiss) private var dismiss

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text(document.name)
                        .type(.body1(.semibold), style: .primaryOnSurface)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button(L10n.Common.done) { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                .padding(.space16)
                Divider()
                CodeEditorView(kind: "txt", text: .constant(document.text), isEditable: false) { dismiss() }
            }
            .frame(width: Metrics.rawTextSheetWidth, height: Metrics.rawTextSheetHeight)
        }
    }

    #Preview("Menu") {
        MacOpenWithMenu(source: .local(URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist")))
            .padding(.space24)
    }

    #Preview("Buttons") {
        MacOpenWithSplitButton(source: .local(URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist")))
            .padding(.space24)
    }

    #Preview("No apps, Download") {
        MacOpenWithSplitButton(source: .local(URL(fileURLWithPath: "/tmp/database.sqlite")))
            .environment(\.macPreviewDownload, MacPreviewDownload {})
            .padding(.space24)
    }

    #Preview("Unavailable") {
        MacOpenWithSplitButton(source: .unavailable)
            .padding(.space24)
    }

    #Preview("Raw text") {
        RawTextSheet(document: RawTextDocument(name: "README", text: "NextExplorer\nA native client."))
    }
#endif
