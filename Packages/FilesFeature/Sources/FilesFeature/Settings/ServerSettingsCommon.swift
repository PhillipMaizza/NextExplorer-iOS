import ComposableArchitecture
import CoreModels
import DesignSystem
import Foundation
import Localization
import SwiftUI

extension Character {
    /// A digit `Int` can read. `isNumber` also takes fractions and digits of other scripts.
    var isASCIIDigit: Bool {
        isASCII && isNumber
    }
}

enum ServerSettingsPreview {
    static let serverURL = URL(string: "https://files.example.com") ?? URL(fileURLWithPath: "/")
}

enum ServerSettingsMetrics {
    static let contentSpacing: CGFloat = .space32
    static let horizontalPadding: CGFloat = .space16
    static let rowSpacing: CGFloat = .space8
    static let disabledOpacity: Double = 0.5
    static let tagHorizontalPadding: CGFloat = .space8
    static let tagVerticalPadding: CGFloat = .space2
    static let tagFillOpacity: Double = 0.15

    /// Between the parts of a one line summary, such as a count and a size.
    static var detailSeparator: String {
        L10n.ServerSettings.detailSeparator
    }

    static func joined(_ parts: [String]) -> String {
        parts.joined(separator: detailSeparator)
    }

    /// Between the fields of a form card, and the extra gap between a card's toggle and its first field.
    static let fieldGroupSpacing: CGFloat = .space24
    static let fieldGroupInset: CGFloat = .space12
    static let indicatorSize: CGFloat = .iconSmall
    static let choiceRowVerticalPadding: CGFloat = .space16
    static let choiceRowSpacing: CGFloat = .space12
    static let selectionAnimationDuration: Double = 0.2
}

/// The scrolling page every admin settings screen shares: a subtitle, the page's own cards, an
/// optional error, and a spinner over a first load that has nothing to show yet.
struct ServerSettingsPage<Content: View>: View {
    let title: String
    let subtitle: String
    let unavailableMessage: String
    let isUnavailable: Bool
    /// A failure of the first load: with nothing loaded the form would only show defaults, so the
    /// page shows this and a retry instead of it.
    var failureMessage: String?
    /// A failure that leaves the loaded page usable, such as a save that was refused.
    let errorMessage: String?
    let isLoadingFirstTime: Bool
    /// A save is under way. The form is held still so what the admin typed is not overwritten by
    /// the server's answer.
    var isBusy = false
    let onAppear: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ServerSettingsMetrics.contentSpacing) {
                Text(subtitle)
                    .type(.body3(.regular), style: .secondary)

                if isUnavailable {
                    DSErrorCard(unavailableMessage)
                } else if let failureMessage {
                    DSErrorCard(failureMessage)
                    DSButton(L10n.Common.retry, icon: IconKit.retry, style: .secondary, action: onAppear)
                        .formActionAlignment()
                } else {
                    content
                        .disabled(isBusy)

                    if let errorMessage {
                        DSErrorCard(errorMessage)
                    }
                }
            }
            .padding(.horizontal, ServerSettingsMetrics.horizontalPadding)
            .padding(.vertical, ServerSettingsMetrics.contentSpacing)
        }
        .backgroundGradient()
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if isLoadingFirstTime {
                DSSpinner()
            }
        }
        .onAppear(perform: onAppear)
    }
}

/// The small red tag the shares list puts beside an expired link, for a line that was refused.
struct RefusedTag: View {
    var body: some View {
        Text(L10n.ActivityLog.refusedSuffix.uppercased())
            .type(.caption(.semibold), style: .error)
            .padding(.horizontal, ServerSettingsMetrics.tagHorizontalPadding)
            .padding(.vertical, ServerSettingsMetrics.tagVerticalPadding)
            .background(RoundedRectangle(cornerRadius: .radiusXSmall)
                .fill(Color.negative.opacity(ServerSettingsMetrics.tagFillOpacity)))
            .fixedSize()
            .accessibilityLabel(L10n.ActivityLog.refusedSuffix)
    }
}

/// How a choice row shows it is selected: a radio button when exactly one option applies (as in
/// the sort sheet), a circled check when several can.
enum ChoiceIndicator {
    case radio
    case check
}

/// A row with its title on the left and a selection indicator on the right, laid out like the sort
/// sheet's rows. The selected row's title is semibold.
struct ChoiceRow: View {
    let title: String
    var subtitle: String?
    var isMonospaced = false
    let isSelected: Bool
    var indicator: ChoiceIndicator = .radio
    var isDisabled = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: ServerSettingsMetrics.choiceRowSpacing) {
                VStack(alignment: .leading, spacing: .space2) {
                    // A monospaced face reads larger than the proportional one at the same size, so
                    // paths take the next size down to sit level with the rest of the screen.
                    Text(title)
                        .type(
                            isMonospaced
                                ? .body3(isSelected ? .semibold : .regular)
                                : .body2(isSelected ? .semibold : .regular),
                            style: .primaryOnSurface
                        )
                        .monospaced(isMonospaced)
                    if let subtitle {
                        Text(subtitle).type(.body3(.regular), style: .tertiary)
                    }
                }
                Spacer(minLength: ServerSettingsMetrics.choiceRowSpacing)
                indicatorView
            }
            .padding(.vertical, ServerSettingsMetrics.choiceRowVerticalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(DSHapticButtonStyle())
        .disabled(isDisabled)
        .opacity(isDisabled ? ServerSettingsMetrics.disabledOpacity : 1)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .animation(.easeInOut(duration: ServerSettingsMetrics.selectionAnimationDuration), value: isSelected)
        .hapticFeedback(.selection, trigger: isSelected)
    }

    @ViewBuilder
    private var indicatorView: some View {
        switch indicator {
        case .radio:
            ZStack {
                IconKit.radioUnselected
                    .resizable()
                    .foregroundStyle(Color.secondaryDS)
                    .opacity(isSelected ? 0 : 1)
                IconKit.radioSelected
                    .resizable()
                    .foregroundStyle(Color.accent)
                    .opacity(isSelected ? 1 : 0)
            }
            .frame(width: ServerSettingsMetrics.indicatorSize, height: ServerSettingsMetrics.indicatorSize)
        case .check:
            ZStack {
                IconKit.radioUnselected
                    .resizable()
                    .foregroundStyle(Color.secondaryDS)
                    .opacity(isSelected ? 0 : 1)
                IconKit.checkmarkCircleFill
                    .resizable()
                    .foregroundStyle(Color.accent)
                    .opacity(isSelected ? 1 : 0)
            }
            .frame(width: ServerSettingsMetrics.indicatorSize, height: ServerSettingsMetrics.indicatorSize)
        }
    }
}

/// Which ends of a row list sit at the edge of the card around it.
enum FlushEdges {
    case none
    case top
    case bottom
    case both

    var isTopFlush: Bool {
        self == .top || self == .both
    }

    var isBottomFlush: Bool {
        self == .bottom || self == .both
    }
}

/// Rows kept flush with the edges of the card they start or end. Each row carries its own vertical
/// padding, so without this the first or last would sit a row's padding deeper than every other
/// piece of content in the card. An end that touches other content is left alone, so the rows keep
/// their breathing room from it.
struct FlushRows<Content: View>: View {
    var edges: FlushEdges = .none
    @ViewBuilder let content: Content

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .padding(.top, edges.isTopFlush ? -ServerSettingsMetrics.choiceRowVerticalPadding : 0)
        .padding(.bottom, edges.isBottomFlush ? -ServerSettingsMetrics.choiceRowVerticalPadding : 0)
    }
}

/// A row that opens a menu of options, for a list too long to show as radio rows. Laid out like
/// `ChoiceRow`, with the current value on the left and an up down chevron on the right, and meant to
/// stand alone in its own card.
struct ChoiceMenuRow<Selection: Hashable, Options: View>: View {
    @Binding var selection: Selection
    let valueTitle: String
    @ViewBuilder let options: Options

    var body: some View {
        FlushRows(edges: .both) {
            Menu {
                Picker(selection: $selection) {
                    options
                } label: {
                    EmptyView()
                }
                .pickerStyle(.inline)
            } label: {
                HStack(spacing: ServerSettingsMetrics.choiceRowSpacing) {
                    Text(valueTitle).type(.body2(.regular), style: .primaryOnSurface)
                    Spacer(minLength: ServerSettingsMetrics.choiceRowSpacing)
                    IconKit.chevronUpDown
                        .foregroundStyle(Color.secondaryDS)
                }
                .padding(.vertical, ServerSettingsMetrics.choiceRowVerticalPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(DSHapticButtonStyle())
        }
    }
}

/// Choice rows with a divider between each: one option to pick, or several to tick.
struct ChoiceRowList<Item: Hashable>: View {
    let items: [Item]
    let title: (Item) -> String
    var subtitle: (Item) -> String? = { _ in nil }
    var isMonospaced = false
    let isSelected: (Item) -> Bool
    var indicator: ChoiceIndicator = .radio
    var isDisabled = false
    var edges: FlushEdges = .none
    let onSelect: (Item) -> Void

    var body: some View {
        FlushRows(edges: edges) {
            ForEach(Array(items.enumerated()), id: \.element) { index, item in
                if index > 0 {
                    Divider()
                }
                ChoiceRow(
                    title: title(item),
                    subtitle: subtitle(item),
                    isMonospaced: isMonospaced,
                    isSelected: isSelected(item),
                    indicator: indicator,
                    isDisabled: isDisabled,
                    action: { onSelect(item) }
                )
            }
        }
    }
}

/// The list of folders a background feature skips: the ones the server's environment fixed, the
/// ones an admin added (each a checked row, unchecked to remove it), and a field to add another. Shared by the search
/// index and
/// the folder size pages, as the web client shares one component for both.
struct ExcludedPathsEditor: View {
    let environmentTitle: String
    let additionalTitle: String
    let emptyTitle: String
    let placeholder: String
    let addTitle: String
    let environmentPaths: [String]
    let displayedPaths: [String]
    let checkedPaths: [String]
    @Binding var newPath: String
    let isEnabled: Bool
    let onAdd: () -> Void
    let onToggle: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: ServerSettingsMetrics.contentSpacing) {
            if !environmentPaths.isEmpty {
                Card(environmentTitle) {
                    ForEach(environmentPaths, id: \.self) { path in
                        pathLabel(path)
                    }
                }
            }

            Card(additionalTitle) {
                if displayedPaths.isEmpty {
                    Text(emptyTitle)
                        .type(.body3(.regular), style: .tertiary)
                }
                ChoiceRowList(
                    items: displayedPaths,
                    title: { $0 },
                    isMonospaced: true,
                    isSelected: { checkedPaths.contains($0) },
                    indicator: .check,
                    edges: .top,
                    onSelect: onToggle
                )
                VStack(spacing: ServerSettingsMetrics.rowSpacing) {
                    DSTextField(placeholder, text: $newPath)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(onAdd)
                    DSButton(addTitle, style: .secondary, action: onAdd)
                        .disabled(newPath.trimmingCharacters(in: .whitespaces).isEmpty)
                        .formActionAlignment()
                }
            }
        }
        .opacity(isEnabled ? 1 : ServerSettingsMetrics.disabledOpacity)
        .disabled(!isEnabled)
    }

    private func pathLabel(_ path: String) -> some View {
        Text(path)
            .type(.body3(.regular), style: .primaryOnSurface)
            .monospaced()
    }
}

/// A labelled number field with its help line, for the admin forms that take a count or a size.
struct SettingsNumberField: View {
    let title: String
    var help: String?
    var placeholder: String?
    @Binding var text: String
    var keyboard: UIKeyboardType = .numberPad

    var body: some View {
        VStack(alignment: .leading, spacing: ServerSettingsMetrics.rowSpacing) {
            DSFieldLabel(title)
            DSTextField(title, text: $text, prompt: placeholder.map { Text($0) })
                .keyboardType(keyboard)
                .autocorrectionDisabled()
            if let help {
                Text(help).type(.body3(.regular), style: .tertiary)
            }
        }
    }
}
