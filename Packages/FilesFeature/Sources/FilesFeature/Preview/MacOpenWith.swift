#if os(macOS)
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let rawTextSheetWidth: CGFloat = 760
        static let rawTextSheetHeight: CGFloat = 560
        static let buttonSpacing: CGFloat = .space12
        static let buttonMaxWidth: CGFloat = 320
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
                        Label { Text(L10n.OpenWith.viewAsText) } icon: { IconKit.document }
                    }
                }
                if model.printKind != nil {
                    Button { model.print() } label: {
                        Label { Text(L10n.OpenWith.print) } icon: { IconKit.print }
                    }
                }
            } label: {
                if model.isWorking {
                    DSSpinner()
                } else {
                    IconKit.openInApp
                }
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .accessibilityLabelWithTooltip(L10n.OpenWith.openWith)
            .focusedSceneValue(\.printPreview, model.printKind == nil ? nil : PrintPreviewAction { model.print() })
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

        var body: some View {
            let apps = MacOpenWithApp.apps(forFileNamed: item.name)
            if let preferred = apps.preferred {
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
                    Label { Text(L10n.OpenWith.openWith) } icon: { IconKit.openInApp }
                }
                .tint(.primaryDS)
            }
        }

        /// A fresh model per click; its task keeps it alive until the open finishes.
        private func model() -> MacOpenWithModel {
            MacOpenWithModel(source: .remote(item, serverURL: serverURL), onFailure: onFailure)
        }
    }

    /// The same actions as prominent buttons, for the "can't preview this file" screen where
    /// opening elsewhere is the main thing to do.
    struct MacOpenWithButtons: View {
        @State private var model: MacOpenWithModel

        init(source: SystemShareSource) {
            _model = State(initialValue: MacOpenWithModel(source: source))
        }

        var body: some View {
            let apps = model.apps
            VStack(spacing: Metrics.buttonSpacing) {
                if let preferred = apps?.preferred {
                    Button { model.open(with: nil) } label: {
                        Label { Text(L10n.OpenWith.openIn(preferred.name)) } icon: { preferred.icon }
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(model.isWorking)
                }
                if let all = apps?.all, all.count > 1 {
                    Menu(L10n.OpenWith.openWith) {
                        ForEach(all) { app in
                            Button { model.open(with: app) } label: {
                                Label { Text(app.name) } icon: { app.icon }
                            }
                        }
                    }
                    .menuStyle(.button)
                    .controlSize(.large)
                }
                if model.canViewAsText {
                    Button(L10n.OpenWith.viewAsText) { model.viewAsText() }
                        .buttonStyle(.link)
                }
            }
            .frame(maxWidth: Metrics.buttonMaxWidth)
            .overlay(alignment: .trailing) {
                if model.isWorking {
                    MacSpinner().offset(x: Metrics.workingIndicatorOffset)
                }
            }
            .modifier(MacOpenWithPresentation(model: model))
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
                CodeEditorView(kind: "txt", text: .constant(document.text), isEditable: false)
            }
            .frame(width: Metrics.rawTextSheetWidth, height: Metrics.rawTextSheetHeight)
        }
    }

    #Preview("Menu") {
        MacOpenWithMenu(source: .local(URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist")))
            .padding(.space24)
    }

    #Preview("Buttons") {
        MacOpenWithButtons(source: .local(URL(fileURLWithPath: "/System/Library/CoreServices/SystemVersion.plist")))
            .padding(.space24)
    }

    #Preview("Unavailable") {
        MacOpenWithButtons(source: .unavailable)
            .padding(.space24)
    }

    #Preview("Raw text") {
        RawTextSheet(document: RawTextDocument(name: "README", text: "NextExplorer\nA native client."))
    }
#endif
