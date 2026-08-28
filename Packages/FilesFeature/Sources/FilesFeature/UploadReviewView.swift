import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI
import UIKit

private enum Constants {
    static let thumbnailSize: CGFloat = .iconLarge
    static let removeButtonSize: CGFloat = .iconSmall
    static let rowSpacing: CGFloat = .space12
    static let rowTextSpacing: CGFloat = .space2
    static let buttonPadding: CGFloat = .space16
    /// Rough per-piece heights, summed to pick a fitted `presentationDetent` (capped below
    /// `screenFraction` of the screen, past which it behaves like `.large` and the list scrolls).
    static let chromeHeight: CGFloat = 56 + 96
    static let fixedSectionHeight: CGFloat = 150
    static let fileRowHeight: CGFloat = 52
    static let filesHeaderHeight: CGFloat = 44
    static let screenFraction: CGFloat = 0.88
}

/// The review sheet: what's about to upload, where to, how big, and the Upload button.
struct UploadReviewView: View {
    @Bindable var store: StoreOf<UploadReviewFeature>

    private static let byteFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter
    }()

    private func rowIcon(_ image: Image) -> some View {
        image
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color.secondaryDS)
            .frame(width: .iconSmall, height: .iconSmall)
    }

    private func fileRow(_ file: PickedFile) -> some View {
        HStack(spacing: Constants.rowSpacing) {
            thumbnail(for: file)
            VStack(alignment: .leading, spacing: Constants.rowTextSpacing) {
                Text(file.fileName)
                    .type(.body2(.regular), style: .primary(for: .label))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(Self.byteFormatter.string(fromByteCount: file.size))
                    .type(.body3(.regular), style: .secondary)
            }
            Spacer(minLength: Constants.rowSpacing)
            Button {
                store.send(.removeFileTapped(id: file.id), animation: .default)
            } label: {
                IconKit.closeCircle
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.secondaryDS)
                    .frame(width: Constants.removeButtonSize, height: Constants.removeButtonSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Common.remove)
        }
    }

    @ViewBuilder
    private func thumbnail(for file: PickedFile) -> some View {
        let kind = (file.fileName as NSString).pathExtension.lowercased()
        if FileItem.isImageKind(kind), kind != "svg" {
            AsyncImage(url: file.fileURL) { phase in
                if case let .success(image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    Color.backgroundSecondary
                }
            }
            .frame(width: Constants.thumbnailSize, height: Constants.thumbnailSize)
            .clipShape(RoundedRectangle(cornerRadius: .radiusSmall))
        } else {
            FileTypeIcon(kind: kind)
                .frame(width: Constants.thumbnailSize, height: Constants.thumbnailSize)
        }
    }

    private var title: String {
        store.totalCount == 1
            ? L10n.Uploads.reviewTitleOne
            : L10n.Uploads.reviewTitleMany(store.totalCount)
    }

    /// Fits the sheet to its content, capping below full height (past which the list scrolls).
    private var detents: Set<PresentationDetent> {
        let estimated = Constants.chromeHeight + Constants.fixedSectionHeight
            + Constants.filesHeaderHeight + CGFloat(store.totalCount) * Constants.fileRowHeight
        let cap = UIScreen.main.bounds.height * Constants.screenFraction
        return [.height(min(estimated, cap)), .large]
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button { store.send(.pathTapped) } label: {
                        HStack(spacing: Constants.rowSpacing) {
                            rowIcon(IconKit.folder)
                            Text(L10n.Uploads.reviewSectionPath)
                                .type(.body2(.regular), style: .primary(for: .label))
                            Spacer()
                            Text(store.hasDestination
                                ? (store.destination as NSString).lastPathComponent
                                : L10n.Uploads.reviewChooseFolder)
                                .type(.body2(.regular), style: .secondary)
                                .lineLimit(1)
                            IconKit.chevronRight
                                .resizable().scaledToFit()
                                .foregroundStyle(Color.secondaryDS)
                                .frame(width: .iconXSmall, height: .iconXSmall)
                        }
                        .contentShape(Rectangle())
                    }
                    .tint(.primaryDS)

                    HStack(spacing: Constants.rowSpacing) {
                        rowIcon(IconKit.size)
                        Text(L10n.Uploads.reviewSectionSize)
                            .type(.body2(.regular), style: .primary(for: .label))
                        Spacer()
                        Text(Self.byteFormatter.string(fromByteCount: store.totalSize))
                            .type(.body2(.regular), style: .secondary)
                    }
                }

                Section(L10n.Uploads.reviewSectionFiles) {
                    ForEach(store.files) { file in
                        fileRow(file)
                    }
                    if store.isPreparing {
                        HStack(spacing: Constants.rowSpacing) {
                            ProgressView()
                            Text(L10n.Uploads.reviewPreparing(store.preparingCount))
                                .type(.body3(.regular), style: .secondary)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color.backgroundPrimary)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { store.send(.cancelTapped) } label: {
                        IconKit.close.foregroundStyle(Color.primaryDS)
                    }
                    .accessibilityLabel(L10n.Common.close)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                DSButton(L10n.Uploads.reviewUploadButton, icon: IconKit.upload, style: .primary, isLoading: store.isPreparing) {
                    store.send(.uploadTapped)
                }
                .disabled(!store.canUpload)
                .padding(Constants.buttonPadding)
                .background(Color.backgroundPrimary)
            }
            .navigationDestination(
                item: $store.scope(state: \.folderPicker, action: \.folderPicker)
            ) { pickerStore in
                DestinationPickerView(store: pickerStore, isPushed: true)
            }
        }
        .presentationDetents(detents)
        .presentationDragIndicator(.visible)
    }
}
