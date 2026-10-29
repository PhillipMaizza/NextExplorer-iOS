#if os(macOS)
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
                    VStack(alignment: .leading) {
                        Text(license.name).lineLimit(1)
                        Text(license.licenseName).font(.callout).foregroundStyle(.secondary)
                    }
                    .tag(license.id)
                }
                .listStyle(.sidebar)
                .frame(width: Metrics.listWidth)
                Divider()
                ScrollView {
                    if let selected {
                        Text(selected.text)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(Metrics.padding)
                    }
                }
            }
            .navigationTitle(L10n.Licenses.navigationTitle)
        }
    }

    #Preview("Licenses") {
        MacLicensesView().frame(width: 640, height: 480)
    }
#endif
