import SwiftUI

private enum FieldConstants {
    static let invalidBorderWidth: CGFloat = 2
    static let borderFadeDuration: Double = 0.2
}

/// Chrome shared by every labeled input field in the app: a label above a leading-icon,
/// `.radiusControl`-bordered box, with an optional shake-on-error and a red border while
/// `isInvalid` is set. The actual `TextField`/`SecureField` (focus, content type,
/// autocorrection, etc. all stay call-site concerns) is supplied via `content`.
public struct DSFieldContainer<Content: View>: View {
    private let label: String
    private let icon: Image
    private let shakeTrigger: CGFloat
    private let isInvalid: Bool
    private let content: Content

    public init(
        label: String,
        icon: Image,
        shakeTrigger: CGFloat = 0,
        isInvalid: Bool = false,
        @ViewBuilder content: () -> Content
    ) {
        self.label = label
        self.icon = icon
        self.shakeTrigger = shakeTrigger
        self.isInvalid = isInvalid
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: .space8) {
            Text(label)
                .type(.body2(.semibold), style: .primary(for: .label))

            HStack(spacing: .space8) {
                icon
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: .iconSmall)

                content
            }
            .padding(.horizontal, .space12)
            .frame(height: .size56)
            .background(
                RoundedRectangle(cornerRadius: .radiusControl)
                    .stroke(isInvalid ? Color.negative : Color.borderPrimary, lineWidth: isInvalid ? FieldConstants.invalidBorderWidth : .borderWidthHairline)
            )
            .animation(.easeInOut(duration: FieldConstants.borderFadeDuration), value: isInvalid)
            .shake(trigger: shakeTrigger)
        }
    }
}

/// The label above a form field — small, semibold, uppercase, `secondaryDS` — so every
/// labelled field across the app reads the same. `DSFieldContainer` on the login screen keeps
/// its own larger label by design.
public struct DSFieldLabel: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(text)
            .type(.body3(.semibold), style: .secondary)
            .textCase(.uppercase)
    }
}

/// The standard single line text field: `.body2` text in `primaryDS` inside the shared
/// `roundedFieldStyle()` box (border, `.radiusControl`, 48pt). Keyboard type,
/// autocapitalization, submit label, content type and the rest still propagate from the call
/// site through the environment; pass `focused:` for a focus binding, which has to reach the
/// field directly.
public struct DSTextField: View {
    private let title: String
    @Binding private var text: String
    private let prompt: Text?
    private let focus: FocusState<Bool>.Binding?

    public init(
        _ title: String,
        text: Binding<String>,
        prompt: Text? = nil,
        focused focus: FocusState<Bool>.Binding? = nil
    ) {
        self.title = title
        self._text = text
        self.prompt = prompt
        self.focus = focus
    }

    public var body: some View {
        field
            .type(.body2(.regular))
            .foregroundStyle(Color.primaryDS)
            .tint(Color.accent)
            .roundedFieldStyle()
    }

    @ViewBuilder
    private var field: some View {
        if let focus {
            TextField(title, text: $text, prompt: prompt).focused(focus)
        } else {
            TextField(title, text: $text, prompt: prompt)
        }
    }
}

/// `DSTextField` for secret entry — same box and text treatment over a `SecureField`.
public struct DSSecureField: View {
    private let title: String
    @Binding private var text: String
    private let prompt: Text?

    public init(_ title: String, text: Binding<String>, prompt: Text? = nil) {
        self.title = title
        self._text = text
        self.prompt = prompt
    }

    public var body: some View {
        SecureField(title, text: $text, prompt: prompt)
            .type(.body2(.regular))
            .foregroundStyle(Color.primaryDS)
            .tint(Color.accent)
            .roundedFieldStyle()
    }
}

#Preview("DSTextField / DSSecureField") {
    struct Demo: View {
        @State private var name = ""
        @State private var filled = "Marketing budget"
        @State private var secret = "hunter2"
        @FocusState private var isFocused: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: .space16) {
                VStack(alignment: .leading, spacing: .space4) {
                    DSFieldLabel("Folder name")
                    DSTextField("Folder name", text: $name)
                }
                VStack(alignment: .leading, spacing: .space4) {
                    DSFieldLabel("Label")
                    DSTextField("Label", text: $filled)
                }
                VStack(alignment: .leading, spacing: .space4) {
                    DSFieldLabel("Search")
                    DSTextField("Search", text: $name, focused: $isFocused)
                        .task { isFocused = true }
                }
                VStack(alignment: .leading, spacing: .space4) {
                    DSFieldLabel("Password")
                    DSSecureField("Password", text: $secret)
                }
            }
            .padding(.space24)
        }
    }
    return Demo()
}

/// A placeholder `Text` that's guaranteed to render in `Color.secondaryDS` regardless of its
/// content — `Text("literal")` resolves to the `LocalizedStringKey` initializer, which
/// auto-detects and linkifies email/URL-shaped literals (blue, underlined) no matter what
/// `.foregroundStyle` says. `Text(verbatim:)` skips that parsing entirely.
public struct DSPlaceholderText: View {
    private let text: String

    public init(_ text: String) {
        self.text = text
    }

    public var body: some View {
        Text(verbatim: text)
            .type(.body1(.regular))
            .foregroundStyle(Color.secondaryDS)
            .allowsHitTesting(false)
    }
}
