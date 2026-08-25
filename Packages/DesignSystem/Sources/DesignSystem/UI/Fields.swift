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
                    .stroke(isInvalid ? Color.negative : Color.borderPrimary, lineWidth: isInvalid ? FieldConstants.invalidBorderWidth : 1)
            )
            .animation(.easeInOut(duration: FieldConstants.borderFadeDuration), value: isInvalid)
            .shake(trigger: shakeTrigger)
        }
    }
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
