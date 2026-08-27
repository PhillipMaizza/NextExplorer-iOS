import ComposableArchitecture
import CoreModels
import DesignSystem
import SwiftUI
import UIKit

private enum Constants {
    static let headerIconSize: CGFloat = .iconMedium
    static let closeIconSize: CGFloat = .iconXSmall
    static let closeButtonPadding: CGFloat = .space8
    static let contentSpacing: CGFloat = .space16
    static let sectionSpacing: CGFloat = .space8
    static let horizontalPadding: CGFloat = .space16
    static let verticalPadding: CGFloat = .space16
    static let cardCornerRadius: CGFloat = .radiusMedium
    static let cardPadding: CGFloat = .space12
    static let fieldHeight: CGFloat = .size48
    static let fieldHorizontalPadding: CGFloat = .space12
    static let copyButtonWidth: CGFloat = .size48
    static let copyIconSize: CGFloat = .iconSmall
    static let summaryColumnSpacing: CGFloat = .space16
    static let copyFeedbackSeconds: Double = 2
}

/// The "Create Share Link" sheet — mirrors the web client's `ShareDialog.vue`, in the app's
/// design-system idiom. Two phases: the form, then (`store.createdShare != nil`) the
/// created-link confirmation.
struct CreateShareLinkSheet: View {
    @Bindable var store: StoreOf<CreateShareLinkFeature>
    @Environment(\.dismiss) private var dismiss
    @State private var copiedField: CopiedField?

    private enum CopiedField: Equatable { case shareLink, directLink }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                Group {
                    if store.createdShare != nil {
                        createdContent
                    } else {
                        formContent
                    }
                }
                .padding(.horizontal, Constants.horizontalPadding)
                .padding(.vertical, Constants.verticalPadding)
            }
        }
        .background(Color.backgroundPrimary)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            HStack(spacing: .space8) {
                IconKit.shareLink
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accent)
                    .frame(width: Constants.headerIconSize, height: Constants.headerIconSize)
                Text(store.createdShare != nil ? "Share Created" : "Create Share Link")
                    .type(.headline3, style: .primary(for: .label))
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                IconKit.close
                    .resizable()
                    .foregroundStyle(Color.primaryDS)
                    .frame(width: Constants.closeIconSize, height: Constants.closeIconSize)
                    .padding(Constants.closeButtonPadding)
                    .background(Circle().fill(Color.backgroundSecondary))
            }
            .buttonStyle(DSHapticButtonStyle())
        }
        .padding(.horizontal, Constants.horizontalPadding)
        .padding(.vertical, .space16)
    }

    // MARK: Form

    private var formContent: some View {
        VStack(alignment: .leading, spacing: Constants.contentSpacing) {
            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .type(.body3(.regular), style: .error)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Constants.cardPadding)
                    .background(RoundedRectangle(cornerRadius: Constants.cardCornerRadius).fill(Color.negative.opacity(0.12)))
            }

            sourceCard

            section("Label") {
                fieldBox {
                    TextField("Label", text: $store.label.sending(\.labelChanged), prompt: Text(verbatim: store.itemName))
                        .type(.body2(.regular))
                        .foregroundStyle(Color.primaryDS)
                        .autocorrectionDisabled()
                }
            }

            section("Access Mode") {
                DSSegmentedControl(
                    options: ShareAccessMode.allCases,
                    selection: $store.accessMode.sending(\.accessModeChanged),
                    label: { $0.title }
                )
            }

            section("Who can access") {
                DSSegmentedControl(
                    options: ShareTarget.allCases,
                    selection: $store.target.sending(\.targetChanged),
                    label: { $0.title }
                )
                if !store.isTargetSupported {
                    Text("Sharing with specific people isn't available in the app yet.")
                        .type(.body3(.regular), style: .secondary)
                }
            }

            DSToggleRow(
                title: "Password protect",
                icon: IconKit.lock,
                isOn: $store.isPasswordEnabled.sending(\.passwordEnabledChanged)
            )
            if store.isPasswordEnabled {
                fieldBox {
                    SecureField("Password", text: $store.password.sending(\.passwordChanged), prompt: Text(verbatim: "Password"))
                        .type(.body2(.regular))
                        .foregroundStyle(Color.primaryDS)
                }
            }

            DSToggleRow(
                title: "Set expiration date",
                icon: IconKit.calendar,
                isOn: $store.isExpiryEnabled.sending(\.expiryEnabledChanged)
            )
            if store.isExpiryEnabled {
                DatePicker(
                    "Expires",
                    selection: $store.expiresAt.sending(\.expiresAtChanged),
                    in: Date()...,
                    displayedComponents: [.date, .hourAndMinute]
                )
                .datePickerStyle(.compact)
                .tint(Color.accent)
            }

            HStack(spacing: .space12) {
                DSButton("Cancel", style: .secondary) { dismiss() }
                DSButton("Create Share Link", style: .primary, isLoading: store.isCreating) {
                    store.send(.createTapped)
                }
                .disabled(!store.isCreateEnabled)
            }
            .padding(.top, .space4)
        }
    }

    private var sourceCard: some View {
        VStack(alignment: .leading, spacing: .space2) {
            Text("Sharing:").type(.body3(.regular), style: .secondary)
            Text(store.itemName).type(.body2(.bold), style: .primary(for: .label)).lineLimit(1)
            Text(store.sourcePath).type(.caption(.regular), style: .tertiary).lineLimit(1).truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Constants.cardPadding)
        .background(RoundedRectangle(cornerRadius: Constants.cardCornerRadius).fill(Color.backgroundSecondary))
    }

    // MARK: Created

    @ViewBuilder
    private var createdContent: some View {
        if let created = store.createdShare {
            VStack(alignment: .leading, spacing: Constants.contentSpacing) {
                HStack(spacing: .space8) {
                    IconKit.checkmark
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Color.positive)
                        .frame(width: Constants.copyIconSize, height: Constants.copyIconSize)
                    Text("Share link created successfully!").type(.body2(.semibold), style: .success)
                    Spacer(minLength: 0)
                }
                .padding(Constants.cardPadding)
                .background(RoundedRectangle(cornerRadius: Constants.cardCornerRadius).fill(Color.positive.opacity(0.12)))

                section("Share Link") {
                    copyRow(value: created.shareUrl.absoluteString, field: .shareLink) {
                        copy(created.shareUrl.absoluteString, as: .shareLink)
                    }
                }

                section(created.share.isDirectory ? "Direct folder ZIP link" : "Direct file link") {
                    Picker("Direct link mode", selection: $store.directLinkMode.sending(\.directLinkModeChanged)) {
                        ForEach(DirectLinkMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Color.secondaryDS)
                    copyRow(value: (store.directLink ?? created.directFileUrl).absoluteString, field: .directLink) {
                        copy((store.directLink ?? created.directFileUrl).absoluteString, as: .directLink)
                    }
                }

                summaryGrid(for: created)

                DSButton("Done", style: .primary) { dismiss() }
                    .padding(.top, .space4)
            }
        }
    }

    private func summaryGrid(for created: CreatedShare) -> some View {
        VStack(alignment: .leading, spacing: .space8) {
            HStack(spacing: Constants.summaryColumnSpacing) {
                summaryItem("Access Mode", created.share.accessMode.title)
                summaryItem("Target", created.share.sharingType.title)
            }
            if created.share.hasPassword {
                summaryItem("Password", "Protected")
            }
            if let expiresAt = created.share.expiresAt {
                summaryItem("Expires", Self.summaryDateFormatter.string(from: expiresAt))
            }
        }
    }

    private func summaryItem(_ label: String, _ value: String) -> some View {
        HStack(spacing: .space8) {
            Text(label).type(.body3(.regular), style: .secondary)
            Text(value).type(.body3(.semibold), style: .primary(for: .label))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Shared pieces

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Constants.sectionSpacing) {
            Text(title).type(.body2(.semibold), style: .primary(for: .label))
            content()
        }
    }

    private func fieldBox(@ViewBuilder content: () -> some View) -> some View {
        content()
            .padding(.horizontal, Constants.fieldHorizontalPadding)
            .frame(height: Constants.fieldHeight)
            .background(
                RoundedRectangle(cornerRadius: .radiusControl)
                    .stroke(Color.borderPrimary, lineWidth: .borderWidthHairline)
            )
    }

    private func copyRow(value: String, field: CopiedField, action: @escaping () -> Void) -> some View {
        HStack(spacing: .space8) {
            Text(value)
                .type(.body3(.regular), style: .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Constants.fieldHorizontalPadding)
                .frame(height: Constants.fieldHeight)
                .background(RoundedRectangle(cornerRadius: .radiusControl).fill(Color.backgroundSecondary))

            Button(action: action) {
                (copiedField == field ? IconKit.checkmark : IconKit.copy)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.white)
                    .frame(width: Constants.copyIconSize, height: Constants.copyIconSize)
                    .frame(width: Constants.copyButtonWidth, height: Constants.fieldHeight)
                    .background(RoundedRectangle(cornerRadius: .radiusControl).fill(copiedField == field ? Color.positive : Color.accent))
            }
            .buttonStyle(DSHapticButtonStyle())
        }
    }

    private func copy(_ string: String, as field: CopiedField) {
        UIPasteboard.general.string = string
        withAnimation { copiedField = field }
        Task {
            try? await Task.sleep(for: .seconds(Constants.copyFeedbackSeconds))
            withAnimation { if copiedField == field { copiedField = nil } }
        }
    }

    private static let summaryDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

#Preview("Form") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CreateShareLinkSheet(
            store: Store(
                initialState: CreateShareLinkFeature.State(
                    serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
                    itemName: "Electricity",
                    itemPath: "Documents/Bills",
                    isDirectory: true
                )
            ) {
                CreateShareLinkFeature()
            } withDependencies: {
                $0.filesClient = .previewValue
            }
        )
    }
}

#Preview("Created") {
    Color.clear.sheet(isPresented: .constant(true)) {
        CreateShareLinkSheet(
            store: Store(
                initialState: {
                    var state = CreateShareLinkFeature.State(
                        serverURL: URL(string: "https://cloud.example.com") ?? URL(fileURLWithPath: "/"),
                        itemName: "Electricity",
                        itemPath: "Documents/Bills",
                        isDirectory: true
                    )
                    state.createdShare = CreatedShare(
                        share: Share(
                            id: "s1", shareToken: "UrkLIGIHMF", ownerId: "u",
                            sourcePath: "Documents/Bills/Electricity", isDirectory: true,
                            accessMode: .readonly, sharingType: .anyone, hasPassword: false,
                            createdAt: Date(), updatedAt: Date()
                        ),
                        shareUrl: URL(string: "https://cloud.example.com/share/UrkLIGIHMF")!,
                        directFileUrl: URL(string: "https://cloud.example.com/api/share/UrkLIGIHMF/file")!
                    )
                    return state
                }()
            ) {
                CreateShareLinkFeature()
            } withDependencies: {
                $0.filesClient = .previewValue
            }
        )
    }
}
