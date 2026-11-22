#if os(macOS)
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Metrics {
        static let listWidth: CGFloat = 220
        static let cardShape = RoundedRectangle(cornerRadius: .radiusMedium, style: .continuous)
        static let rowShape = RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
        static let sheetWidth: CGFloat = 920
        static let sheetHeight: CGFloat = 580
    }

    struct MacLicensesView: View {
        @State private var selection: OpenSourceLicense.ID? = OpenSourceLicense.all.first?.id

        private var selected: OpenSourceLicense? {
            OpenSourceLicense.all.first { $0.id == selection }
        }

        var body: some View {
            HStack(alignment: .top, spacing: .space16) {
                libraries
                if let selected {
                    detail(selected)
                }
            }
        }

        private var libraries: some View {
            ScrollView {
                LazyVStack(spacing: .zero) {
                    ForEach(OpenSourceLicense.all) { license in
                        libraryRow(license)
                    }
                }
                .padding(.space4)
            }
            .frame(width: Metrics.listWidth)
            .background(Metrics.cardShape.fill(Color.macRow))
            .clipShape(Metrics.cardShape)
        }

        private func libraryRow(_ license: OpenSourceLicense) -> some View {
            let isSelected = license.id == selection
            return Button { selection = license.id } label: {
                VStack(alignment: .leading, spacing: .space2) {
                    Text(license.name)
                        .type(.body2(.semibold))
                        .foregroundStyle(Color.macChromeText)
                        .lineLimit(1)
                    Text(license.licenseName)
                        .type(.body3(.regular))
                        .foregroundStyle(Color.macChromeSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, .space4)
                .macListRow(isSelected: isSelected)
                .clipShape(Metrics.rowShape)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private func detail(_ license: OpenSourceLicense) -> some View {
            VStack(alignment: .leading, spacing: .space12) {
                HStack(spacing: .space8) {
                    Text(license.name).type(.headline4)
                    MacChip(text: license.licenseName, tone: .gray)
                }
                ScrollView([.vertical, .horizontal]) {
                    Text(license.text)
                        .type(.body3(.regular))
                        .monospaced()
                        .foregroundStyle(Color.macChromeSecondary)
                        .textSelection(.enabled)
                        .fixedSize()
                        .padding(.space16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Metrics.cardShape.fill(Color.macRow))
                .clipShape(Metrics.cardShape)
            }
        }
    }

    private struct MacLicensesSheet: View {
        let onClose: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                Text(L10n.Licenses.navigationTitle).type(.headline4)
                MacLicensesView()
                HStack {
                    Spacer(minLength: .zero)
                    Button(L10n.Common.close, action: onClose)
                        .buttonStyle(.macDS(.primary))
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.space24)
            .background(Color.macCard)
            .onExitCommand(perform: onClose)
        }
    }

    extension View {
        func macLicensesSheet(isPresented: Binding<Bool>) -> some View {
            sheet(isPresented: isPresented) {
                MacLicensesSheet { isPresented.wrappedValue = false }
                    .frame(width: Metrics.sheetWidth, height: Metrics.sheetHeight)
            }
        }
    }

    #Preview("Licenses sheet") {
        MacLicensesSheet(onClose: {})
            .frame(width: Metrics.sheetWidth, height: Metrics.sheetHeight)
    }

    #Preview("Licenses") {
        MacLicensesView()
            .padding(.space24)
            .previewCanvas(.window)
            .background(Color.macCard)
    }
#endif
