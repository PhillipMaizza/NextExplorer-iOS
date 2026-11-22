#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let listWidth: CGFloat = 220
        static let padding: CGFloat = .space16
    }

    /// The open source licenses on the Mac: the libraries in a list, the selected license's
    /// full text beside it.
    struct MacLicensesView: View {
        @State private var selection: OpenSourceLicense.ID? = OpenSourceLicense.all.first?.id

        private var selected: OpenSourceLicense? {
            OpenSourceLicense.all.first { $0.id == selection }
        }

        var body: some View {
            HStack(spacing: 0) {
                List(OpenSourceLicense.all, selection: $selection) { license in
                    VStack(alignment: .leading, spacing: .space2) {
                        Text(license.name)
                            .type(.body2(.semibold))
                            .lineLimit(1)
                        Text(license.licenseName)
                            .type(.caption(.regular), style: .secondary)
                    }
                    .padding(.vertical, .space4)
                    .tag(license.id)
                }
                .listStyle(.sidebar)
                .frame(width: Metrics.listWidth)
                Divider()
                ScrollView([.vertical, .horizontal]) {
                    if let selected {
                        VStack(alignment: .leading, spacing: .space12) {
                            HStack(spacing: .space8) {
                                Text(selected.name)
                                    .type(.headline4)
                                MacChip(text: selected.licenseName, kind: .pill)
                            }
                            Text(selected.text)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(Color.secondaryText)
                                .textSelection(.enabled)
                                .fixedSize()
                        }
                        .padding(Metrics.padding)
                    }
                }
            }
            .navigationTitle(L10n.Licenses.navigationTitle)
        }
    }

    #Preview("Licenses") {
        MacLicensesView().previewCanvas(.settingsPane)
    }
#endif
