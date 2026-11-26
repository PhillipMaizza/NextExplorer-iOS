#if os(macOS)
    import Localization
    import SwiftUI

    private enum Constants {
        static let swatchSize: CGFloat = .size48
        static let ringSize: CGFloat = .size24
        static let sectionWidth: CGFloat = 520
        static let sampleProgress: Double = 0.62
        static let sampleSlider: Double = 0.4
        static let sampleStepper = 8
    }

    struct MacGalleryView: View {
        var body: some View {
            HStack(alignment: .top, spacing: .space24) {
                VStack(alignment: .leading, spacing: .space24) {
                    MacGallerySection(title: "Colours") { MacGallerySwatches() }
                    MacGallerySection(title: "Type") { MacGalleryTypeScale() }
                    MacGallerySection(title: "Buttons") { MacGalleryButtons() }
                }
                VStack(alignment: .leading, spacing: .space24) {
                    MacGallerySection(title: "Fields") { MacGalleryFields() }
                    MacGallerySection(title: "Native controls") { MacGalleryNativeControls() }
                    MacGallerySection(title: "Form group") { MacGalleryFormGroup() }
                    MacGallerySection(title: "Status") { MacGalleryStatus() }
                    MacGallerySample()
                }
                VStack(alignment: .leading, spacing: .space24) {
                    MacGallerySection(title: "Inspector") { MacGalleryInspector() }
                    MacGallerySection(title: "List") { MacGalleryList() }
                    MacGallerySection(title: "Empty guide") {
                        MacEmptyGuideBullet(icon: IconKit.macRestore, text: "Restore puts an item back.")
                        MacEmptyGuideTile(icon: IconKit.macTrash, size: .size56)
                    }
                    MacGallerySection(title: "Feedback") { MacGalleryFeedback() }
                    MacGallerySection(title: "Alert") {
                        MacAlertSheet(
                            title: "Revoke Token?",
                            message: "This can't be undone.",
                            confirmTitle: "Revoke",
                            onConfirm: {},
                            onCancel: {}
                        )
                    }
                }
            }
            .padding(.space32)
            .macChromeBackground()
        }
    }

    private struct MacGallerySection<Content: View>: View {
        let title: String
        @ViewBuilder let content: () -> Content

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                Text(verbatim: title).type(.label3, style: .secondary)
                content()
            }
            .padding(.space24)
            .frame(width: Constants.sectionWidth, alignment: .leading)
            .macCard()
        }
    }

    private struct MacGallerySwatches: View {
        private let swatches: [Color] = [
            .macChrome, .macCard, .macRow, .macLine, .macSegment, .macField,
            .macChromeText, .macChromeSecondary, .macChromeTertiary, .accent, .accentText, .negative, .positive,
        ]

        var body: some View {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(Constants.swatchSize)), count: 6), spacing: .space8) {
                ForEach(swatches.indices, id: \.self) { index in
                    RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                        .fill(swatches[index])
                        .overlay(
                            RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                                .strokeBorder(Color.macLine, lineWidth: .borderWidthHairline)
                        )
                        .frame(width: Constants.swatchSize, height: Constants.swatchSize)
                }
            }
        }
    }

    private struct MacGalleryTypeScale: View {
        private let types: [Typography.TextType] = [
            .headline2, .headline3, .headline4, .label3, .body2(.regular), .body3(.regular), .caption(.regular),
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: .space8) {
                ForEach(types.indices, id: \.self) { index in
                    Text(verbatim: "NextExplorer 0123456789").type(types[index])
                }
            }
        }
    }

    private struct MacGalleryButtons: View {
        var body: some View {
            VStack(alignment: .leading, spacing: .space12) {
                ForEach(DSButtonSize.allCases, id: \.self) { size in
                    HStack(spacing: .space8) {
                        Button(L10n.Common.save) {}.buttonStyle(.macDS(.primary, size: size))
                        Button(L10n.Common.cancel) {}.buttonStyle(.macDS(.secondary, size: size))
                        Button(L10n.Common.delete, role: .destructive) {}.buttonStyle(.macDS(.secondary, size: size))
                        Button(L10n.Common.remove) {}.buttonStyle(.macDS(.failure, size: size))
                    }
                }
                HStack(spacing: .space8) {
                    Button(L10n.Common.save) {}.buttonStyle(.macDS(.primary)).disabled(true)
                    Button(L10n.Common.edit) {}.buttonStyle(.macDS(.outline))
                    Button {} label: { Label { Text(L10n.Common.more) } icon: { IconKit.moreOptions } }
                        .buttonStyle(.macToolbar)
                    Button {} label: { Label { Text(L10n.Common.download) } icon: { IconKit.upload } }
                        .buttonStyle(.macToolbarAccent)
                }
            }
        }
    }

    private struct MacGalleryFields: View {
        @State private var name = ""
        @State private var secret = "hunter2"
        @State private var short = "abc"
        @State private var choice = 0

        var body: some View {
            Form {
                MacTextField(L10n.Common.search, text: $name, prompt: L10n.Common.search)
                MacPopup(
                    L10n.Common.sort,
                    valueLabel: choice == 0 ? L10n.Common.on : L10n.Common.off,
                    selection: $choice
                ) {
                    Text(L10n.Common.on).tag(0)
                    Text(L10n.Common.off).tag(1)
                }
                LabeledContent(L10n.Common.password) {
                    MacSecureField(L10n.Common.password, text: $secret)
                }
                LabeledContent(L10n.Uploads.reviewSectionPath) {
                    MacPathField(path: nil, placeholder: L10n.Uploads.reviewChooseFolder) {}
                }
                LabeledContent(L10n.Common.password) {
                    VStack(alignment: .leading, spacing: .space4) {
                        MacSecureField(L10n.Common.password, text: $short)
                        MacFieldError(message: "Use at least 8 characters.")
                    }
                }
            }
            .formStyle(.columns)
            .type(.body2(.regular))
        }
    }

    private struct MacGalleryNativeControls: View {
        @State private var isOn = true
        @State private var isChecked = true
        @State private var choice = 0
        @State private var level = Constants.sampleSlider
        @State private var count = Constants.sampleStepper

        var body: some View {
            Form {
                Toggle(L10n.Common.on, isOn: $isOn).toggleStyle(.macSwitch)
                Toggle(L10n.Common.select, isOn: $isChecked).toggleStyle(.checkbox)
                Picker(L10n.Common.sort, selection: $choice) {
                    Text(L10n.Common.on).tag(0)
                    Text(L10n.Common.off).tag(1)
                }
                .pickerStyle(.segmented)
                Slider(value: $level)
                Stepper(value: $count) { Text(count.formatted()) }
            }
            .formStyle(.columns)
            .type(.body2(.regular))
        }
    }

    private struct MacGalleryFormGroup: View {
        @State private var isOn = true

        var body: some View {
            MacFormGroup {
                MacFormRow(L10n.Common.on) {
                    Toggle(L10n.Common.on, isOn: $isOn).labelsHidden()
                }
                MacFormRow(L10n.Common.password) {
                    MacChip(text: L10n.Common.never, tone: .gray)
                }
            }
            .toggleStyle(.macSwitch)
            .type(.body2(.regular))
        }
    }

    private struct MacGalleryStatus: View {
        var body: some View {
            VStack(alignment: .leading, spacing: .space12) {
                HStack(spacing: .space8) {
                    MacProgressRing(progress: Constants.sampleProgress)
                        .frame(width: Constants.ringSize, height: Constants.ringSize)
                    MacSpinner()
                    MacChip(text: "\u{2318} 1")
                    MacChip(text: L10n.Common.on, tint: .positive, style: .success, kind: .pill)
                    MacChip(text: L10n.Common.never, tint: .accent, style: .link, kind: .pill)
                    MacChip(text: L10n.Common.off, kind: .pill)
                }
                HStack(spacing: .space8) {
                    MacChip(text: L10n.Common.on, tone: .green)
                    MacChip(text: L10n.Common.never, tone: .red)
                    MacChip(text: L10n.Common.off, tone: .gray)
                }
                DSUsageBar(fraction: Constants.sampleProgress)
            }
        }
    }

    private struct MacGallerySample: View {
        @State private var name = ""

        var body: some View {
            MacFormSheet(
                title: "New Folder",
                message: "Documents",
                confirmTitle: L10n.Common.save,
                errorMessage: "A folder with this name already exists.",
                onCancel: {},
                onConfirm: {}
            ) {
                MacFormSheetRow(L10n.Common.search) {
                    MacTextField(L10n.Common.search, text: $name, prompt: L10n.Common.search)
                }
            }
            .macCard()
        }
    }

    private struct MacGalleryInspector: View {
        var body: some View {
            MacInspectorSectionHeader(title: "Details", count: 3)
            MacInspectorGroup {
                MacInspectorRow("Kind", "PDF")
                MacInspectorRow("Size", "2.4 MB")
            }
            MacInspectorQuickActions(actions: [
                MacInspectorQuickAction(icon: IconKit.link, title: "Share") {},
                MacInspectorQuickAction(icon: IconKit.star, title: "Favorite", isOn: true) {},
            ])
        }
    }

    private struct MacGalleryList: View {
        @State private var selection = "projects"

        var body: some View {
            VStack(spacing: .zero) {
                ForEach(["archive", "projects", "media"], id: \.self) { name in
                    Text(verbatim: name)
                        .type(.body2(.regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Color.macChromeText)
                        .macListRow(isSelected: name == selection)
                        .macSelectable(isSelected: name == selection) { selection = name }
                }
            }
            .macListBox()
        }
    }

    private struct MacGalleryFeedback: View {
        @State private var quality = 70
        @State private var dimension = 400

        var body: some View {
            MacToastCard(message: .success("Saved to Documents"), onAction: {}, onClose: {})
            MacTransferStatus(fileName: "brief-v2.pdf", timeLeft: "12s left", fraction: Constants.sampleProgress)
            MacSlider(label: "Quality", value: quality, range: 1 ... 100, step: 5) { quality = $0 }
            MacStepper(label: "Max Dimension", value: dimension, range: 64 ... 2048, step: 8) { dimension = $0 }
        }
    }

    #Preview("Mac gallery, light") {
        MacGalleryView()
            .environment(\.colorScheme, .light)
    }

    #Preview("Mac gallery, dark") {
        MacGalleryView()
            .environment(\.colorScheme, .dark)
    }

    #Preview("Mac gallery, largest text") {
        MacGalleryView()
            .macTextScale(MacTextScale.range.upperBound)
    }
#endif
