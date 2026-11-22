#if os(macOS)
    import DesignSystem
    import SwiftUI

    struct MacSwitchRow<Label: View>: View {
        let title: String
        let isOn: Binding<Bool>
        @ViewBuilder let label: () -> Label

        var body: some View {
            MacFormRow(label: label) {
                Toggle(title, isOn: isOn).labelsHidden()
            }
        }
    }

    extension MacSwitchRow where Label == Text {
        init(_ title: String, isOn: Binding<Bool>) {
            self.init(title: title, isOn: isOn) { Text(title) }
        }
    }

    extension MacSwitchRow where Label == MacRowTitle {
        init(_ title: String, help: String, isOn: Binding<Bool>) {
            self.init(title: title, isOn: isOn) { MacRowTitle(title: title, subtitle: help) }
        }
    }

    struct MacStepperRow<Label: View>: View {
        let title: String
        let value: Int
        let range: ClosedRange<Int>
        var step = 1
        let onChange: (Int) -> Void
        @ViewBuilder let label: () -> Label

        var body: some View {
            MacFormRow(label: label) {
                MacStepper(label: title, value: value, range: range, step: step, onChange: onChange)
            }
        }
    }

    extension MacStepperRow where Label == Text {
        init(_ title: String, value: Int, range: ClosedRange<Int>, onChange: @escaping (Int) -> Void) {
            self.init(title: title, value: value, range: range, onChange: onChange) { Text(title) }
        }
    }

    extension MacStepperRow where Label == MacRowTitle {
        init(
            _ title: String,
            help: String,
            value: Int,
            range: ClosedRange<Int>,
            step: Int = 1,
            onChange: @escaping (Int) -> Void
        ) {
            self.init(title: title, value: value, range: range, step: step, onChange: onChange) {
                MacRowTitle(title: title, subtitle: help)
            }
        }
    }

    #Preview("Setting rows") {
        MacFormPage {
            MacFormGroup {
                MacSwitchRow("Show Hidden Files", isOn: .constant(true))
                MacSwitchRow("Enable Thumbnails", help: "Generates previews on the server.", isOn: .constant(false))
                MacStepperRow("Retention (days)", value: 30, range: 1 ... 3650) { _ in }
                MacStepperRow("Quality", help: "From 1 to 100.", value: 70, range: 1 ... 100, step: 5) { _ in }
                MacSwitchRow(title: "Send to Trash", isOn: .constant(true)) {
                    MacInfoLabel("Send to Trash", info: "Items expire after the retention.")
                }
            }
        }
        .previewCanvas(.settingsPane)
        .background(Color.macCard)
    }
#endif
