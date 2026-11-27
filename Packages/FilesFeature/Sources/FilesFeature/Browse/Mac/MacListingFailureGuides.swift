#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let buttonIconSize: CGFloat = .size16
    }

    struct MacFolderMissingGuide: View {
        @Environment(\.showMacPreviousFolder) private var previousFolder
        @Environment(\.showMacEnclosingFolder) private var enclosingFolder

        var body: some View {
            EmptyGuide(title: L10n.EmptyGuide.folderMissingTitle) {
                EmptyGuideTile(icon: IconKit.macFolder)
            } detail: {
                Text(L10n.EmptyGuide.folderMissingBody)
                    .type(.body1(.regular), style: .secondary)
                HStack(spacing: .space8) {
                    if let previousFolder {
                        MacGuideButton(title: L10n.EmptyGuide.goBack, icon: IconKit.macToolbarBack) { previousFolder() }
                            .buttonStyle(.macDS(.primary))
                    }
                    if let enclosingFolder {
                        MacGuideButton(title: L10n.Menu.enclosingFolder, icon: IconKit.macToolbarUp) {
                            enclosingFolder()
                        }
                        .buttonStyle(.macDS(.secondary))
                    }
                }
                .padding(.top, .space8)
            }
        }
    }

    struct MacServerProblemGuide: View {
        let statusCode: Int
        @Environment(\.retryMacFolder) private var retry
        @Environment(\.showMacPreviousFolder) private var previousFolder

        var body: some View {
            EmptyGuide(title: L10n.EmptyGuide.serverProblemTitle) {
                EmptyGuideTile(icon: IconKit.macWarning)
            } detail: {
                Text(L10n.EmptyGuide.serverProblemBody)
                    .type(.body1(.regular), style: .secondary)
                HStack(spacing: .space8) {
                    if let retry {
                        MacGuideButton(title: L10n.Common.retry, icon: IconKit.macToolbarRefresh) { retry() }
                            .buttonStyle(.macDS(.primary))
                    }
                    if let previousFolder {
                        MacGuideButton(title: L10n.EmptyGuide.goBack, icon: IconKit.macToolbarBack) { previousFolder() }
                            .buttonStyle(.macDS(.secondary))
                    }
                }
                .padding(.top, .space8)
                Text(L10n.EmptyGuide.errorCode(statusCode))
                    .type(.body3(.regular), style: .secondary)
            }
        }
    }

    private struct MacGuideButton: View {
        let title: String
        let icon: Image
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Label {
                    Text(title)
                } icon: {
                    icon
                        .resizable()
                        .scaledToFit()
                        .frame(width: Metrics.buttonIconSize, height: Metrics.buttonIconSize)
                }
            }
        }
    }

    #Preview("Folder missing") {
        MacFolderMissingGuide()
            .environment(\.showMacPreviousFolder, MacSectionOpener {})
            .environment(\.showMacEnclosingFolder, MacSectionOpener {})
            .frame(width: 900, height: 600)
    }

    #Preview("Server problem, dark") {
        MacServerProblemGuide(statusCode: 500)
            .environment(\.retryMacFolder, MacSectionOpener {})
            .environment(\.showMacPreviousFolder, MacSectionOpener {})
            .frame(width: 900, height: 600)
            .preferredColorScheme(.dark)
    }
#endif
