#if os(iOS)
    import AppStorageKeys
    import ComposableArchitecture
    import CoreModels
    import DesignSystem
    import Localization
    import SwiftUI

    private enum Constants {
        static let presetSpacing: CGFloat = .space8
        static let presetHeight: CGFloat = .size44
        static let chipHorizontalPadding: CGFloat = .space12
        static let chipVerticalPadding: CGFloat = .space8
        static let compactColumns = 2
    }

    /// Expiry as one choice: Never or a preset span, Custom for any other date. The calendar stays
    /// folded until Custom, a tap on the date, or an expired share asks for it.
    struct EditShareExpirySection: View {
        @Bindable var store: StoreOf<EditShareFeature>
        @Binding var isCalendarShown: Bool

        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue

        private static let timeStyle = Date.FormatStyle(date: .omitted, time: .shortened)

        private var dateFormat: DateDisplayFormat {
            DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
        }

        var body: some View {
            Section {
                presets.alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
                if store.isExpiryEnabled {
                    dateRow
                    if isCalendarShown {
                        DatePicker(
                            L10n.CreateShare.fieldExpires,
                            selection: $store.expiresAt.sending(\.expiresAtChanged),
                            in: store.openedAt...,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        .datePickerStyle(.graphical)
                        .labelsHidden()
                        .tint(Color.accent)
                    }
                }
            } header: {
                DSFieldLabel(L10n.CreateShare.summaryExpires)
            } footer: {
                footer
            }
        }

        /// Two by two on iPhone so every language has room; one row where the sheet is wide.
        private var presets: some View {
            presetGrid(columns: horizontalSizeClass == .regular
                ? EditShareFeature.ExpiryPreset.allCases.count
                : Constants.compactColumns)
        }

        private func presetGrid(columns: Int) -> some View {
            Grid(horizontalSpacing: Constants.presetSpacing, verticalSpacing: Constants.presetSpacing) {
                let all = EditShareFeature.ExpiryPreset.allCases
                let rows = stride(from: 0, to: all.count, by: columns).map { Array(all[$0 ..< min(
                    $0 + columns,
                    all.count
                )]) }
                ForEach(rows.indices, id: \.self) { index in
                    GridRow {
                        ForEach(rows[index], id: \.self) { preset($0) }
                    }
                }
            }
        }

        private func preset(_ preset: EditShareFeature.ExpiryPreset) -> some View {
            let isSelected = store.expiryPreset == preset
            return Button {
                store.send(.expiryPresetTapped(preset), animation: DSMotion.stateFade)
                if preset == .custom {
                    withAnimation(DSMotion.stateFade) { isCalendarShown = true }
                }
            } label: {
                Text(preset.title)
                    .type(.body2(.semibold), style: isSelected ? .custom(Color.primaryInverted) : .primaryOnSurface)
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, .space8)
                    .frame(maxWidth: .infinity, minHeight: Constants.presetHeight)
                    .background(
                        RoundedRectangle(cornerRadius: .radiusControl, style: .continuous)
                            .fill(isSelected ? Color.accent : Color.backgroundPrimary)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableButtonStyle())
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .hapticFeedback(.selection, trigger: isSelected)
        }

        private var dateRow: some View {
            Button {
                withAnimation(DSMotion.stateFade) { isCalendarShown.toggle() }
            } label: {
                HStack(spacing: .space8) {
                    Text(L10n.CreateShare.fieldExpires).type(.body2(.regular), style: .primaryOnSurface)
                    Spacer(minLength: .space8)
                    chip(dateFormat.string(from: store.expiresAt))
                    chip(store.expiresAt.formatted(Self.timeStyle))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(DSPressableButtonStyle())
            .accessibilityElement(children: .combine)
            .accessibilityHint(L10n.CreateShare.toggleSetExpiration)
        }

        private func chip(_ text: String) -> some View {
            Text(text)
                .type(.body2(.regular), style: isCalendarShown ? .custom(Color.primaryInverted) : .primaryOnSurface)
                .padding(.horizontal, Constants.chipHorizontalPadding)
                .padding(.vertical, Constants.chipVerticalPadding)
                .background(RoundedRectangle(cornerRadius: .radiusSmall, style: .continuous)
                    .fill(isCalendarShown ? Color.accent : Color.backgroundPrimary))
        }

        @ViewBuilder
        private var footer: some View {
            if let error = store.fieldError, error == .pastExpiration {
                Text(error.message).type(.body3(.regular), style: .error)
            } else if store.isExpired, let oldDate = store.share.expiresAt {
                Text(L10n.Shared.expiredFooter(dateFormat.string(from: oldDate)))
                    .type(.body3(.regular), style: .secondary)
            } else if store.isExpiryEnabled {
                Text(L10n.Shared.daysLeft(store.daysLeft)).type(.body3(.regular), style: .secondary)
            } else {
                Text(L10n.EditShare.neverFooter).type(.body3(.regular), style: .secondary)
            }
        }
    }

    private struct ExpiryPreview: View {
        let store: StoreOf<EditShareFeature>
        @State var isCalendarShown: Bool

        var body: some View {
            DSGroupedList {
                EditShareExpirySection(store: store, isCalendarShown: $isCalendarShown)
            }
            .sharedSheetList()
        }
    }

    @MainActor
    private func expiryPreview(
        expiresAt: Date?,
        isCalendarShown: Bool = false,
        mutate: (inout EditShareFeature.State) -> Void = { _ in }
    ) -> some View {
        ExpiryPreview(
            store: editSharePreviewStore(.previewCard(expiresAt: expiresAt), mutate: mutate),
            isCalendarShown: isCalendarShown
        )
    }

    #Preview("Never") {
        expiryPreview(expiresAt: nil)
    }

    #Preview("Custom, calendar open, dark") {
        expiryPreview(expiresAt: Date().addingTimeInterval(86_400 * 12), isCalendarShown: true)
            .preferredColorScheme(.dark)
    }

    #Preview("Expired") {
        expiryPreview(expiresAt: Date().addingTimeInterval(-86_400 * 9), isCalendarShown: true)
    }

    #Preview("Past date error") {
        expiryPreview(expiresAt: Date().addingTimeInterval(86_400 * 3)) {
            $0.fieldError = .pastExpiration
        }
    }

    #Preview("Large type") {
        expiryPreview(expiresAt: Date().addingTimeInterval(86_400 * 7))
            .dynamicTypeSize(.accessibility2)
    }
#endif
