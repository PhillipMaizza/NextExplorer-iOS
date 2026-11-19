import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import Localization
import SwiftUI

private enum Constants {
    static let actionHeight: CGFloat = .size48
    static let deletingOpacity: Double = 0.4
}

/// One share in the item sheet: the item, the copy split button, who it reaches, then its facts
/// and Edit and Delete. With me drops every owner control and says who controls the share. The
/// sheet's root when the item has one share, otherwise pushed from the share list.
struct SharedSharePage: View {
    let store: StoreOf<SharedFeature>
    let segment: SharedFeature.Segment
    let item: SharedFeature.Item
    let share: Share
    let isPushed: Bool
    let onCopied: (String) -> Void

    @AppStorage(AppStorageKeys.dateDisplayFormat) private var dateFormatRaw = DateDisplayFormat.system.rawValue
    @State private var directLinkMode: DirectLinkMode = .auto

    private var isByMe: Bool {
        segment == .byMe
    }

    private var isExpired: Bool {
        store.state.isExpired(share)
    }

    private var isDeleting: Bool {
        store.deletingIDs.contains(share.id)
    }

    private var dateFormat: DateDisplayFormat {
        DateDisplayFormat(rawValue: dateFormatRaw) ?? .system
    }

    private var facts: SharedShareFacts {
        SharedShareFacts(share: share, notice: store.state.expiryNotice(for: share), dateFormat: dateFormat)
    }

    private var badge: SharedFeature.ShareBadge? {
        item.badges.first { $0.id == share.id }
    }

    private var sharerName: String {
        badge?.people.first?.name ?? store.state.sharedByLabel(for: share)
    }

    var body: some View {
        let facts = facts
        DSGroupedList {
            Section {
                SharedDetailHero(
                    share: share,
                    iconName: item.name,
                    title: isPushed ? share.trimmedLabel ?? item.name : item.name,
                    subtitle: isByMe
                        ? SharedDetailHero.fullPath(of: share) ?? item.name
                        : L10n.Shared.fromSharer(sharerName),
                    serverURL: store.serverURL,
                    isByMe: isByMe,
                    isExpired: isExpired
                )
                .clearRow()
                if isByMe {
                    SharedCopyLinkButton(
                        share: share,
                        serverURL: store.serverURL,
                        directLinkMode: directLinkMode,
                        isExpired: isExpired,
                        onCopied: onCopied,
                        onSetNewDate: { store.send(.editTapped(share)) }
                    )
                    .clearRow()
                    .padding(.top, .space12)
                }
            }

            if let badge {
                Section {
                    SharedPeopleCircles(badge: badge)
                        .padding(.vertical, .space4)
                } header: {
                    DSFieldLabel(isByMe ? L10n.Shared.metaSharedWith : L10n.Shared.metaSharedBy)
                }
            }

            Section {
                fact(L10n.Shared.metaAccess, share.accessMode.title)
                fact(L10n.Common.password, facts.password)
                fact(facts.expiresTitle, facts.expires, style: facts.expiresStyle)
                if isByMe {
                    DSMenuPickerRow(selection: $directLinkMode, value: directLinkMode.title) {
                        ForEach(DirectLinkMode.allCases) { Text($0.title).tag($0) }
                    } label: {
                        Text(facts.linkModeTitle)
                            .type(.body2(.regular), style: .primaryOnSurface)
                    }
                    .tint(Color.secondaryDS)
                }
            } footer: {
                if isByMe, let note = facts.expiredNote {
                    Text(note)
                        .type(.body3(.regular), style: .error)
                }
            }

            Section {
                fact(L10n.Shared.metaLabel, facts.label)
                fact(isByMe ? L10n.Shared.metaShared : L10n.Shared.metaReceived, facts.created)
                if isByMe {
                    fact(L10n.Shared.metaLastOpened, facts.lastOpened)
                    fact(L10n.Shared.metaDownloads, facts.downloads)
                }
            } footer: {
                if !isByMe {
                    Text(L10n.Shared.controlsShare(sharerName)).type(.body3(.regular), style: .secondary)
                }
            }

            if isByMe {
                Section {
                    HStack(spacing: .space8) {
                        action(L10n.Common.edit, style: .primaryOnSurface) { store.send(.editTapped(share)) }
                        action(L10n.Common.delete, style: .error) { store.send(.deleteTapped(share)) }
                            .accessibilityIdentifier(AccessibilityIdentifiers.Shared.deleteShare)
                    }
                    .clearRow()
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.backgroundPrimary)
        .opacity(isDeleting ? Constants.deletingOpacity : 1)
        .disabled(isDeleting)
        .navigationTitle(isPushed ? item.name : "")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func fact(_ label: String, _ value: String, style: Typography.TextStyle = .secondary) -> some View {
        HStack(spacing: .space12) {
            Text(label).type(.body2(.regular), style: .primaryOnSurface)
            Spacer(minLength: .space8)
            Text(value)
                .type(.body2(.regular), style: style)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func action(_ title: String, style: Typography.TextStyle, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Text(title)
                .type(.body2(.semibold), style: style)
                .frame(maxWidth: .infinity, minHeight: Constants.actionHeight)
                .background(RoundedRectangle(cornerRadius: .radiusCard, style: .continuous)
                    .fill(Color.backgroundSecondary))
                .contentShape(Rectangle())
        }
        .buttonStyle(DSPressableButtonStyle())
    }
}

extension View {
    /// A list row with no card behind it, for content that draws its own surface.
    func clearRow() -> some View {
        listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}

#Preview("Page: public link expiring soon") {
    sharedDetailPreview(.byMe, "personal:Photos/2026/Vacation Photos")
}

#Preview("Page: people, read and write") {
    sharedDetailPreview(.byMe, "personal:Work/Team Roadmap", pushed: "s5")
}

#Preview("Page: expired") {
    sharedDetailPreview(.byMe, "personal:Design/Brand/Logo final.png")
}

#Preview("Page: deleting") {
    sharedDetailPreview(.byMe, "personal:Finance/Budget 2027.xlsx") { $0.deletingIDs = ["s8"] }
}

#Preview("Page: with me, dark") {
    sharedDetailPreview(.withMe, "w2")
        .preferredColorScheme(.dark)
}

#Preview("Page: large type") {
    sharedDetailPreview(.byMe, "personal:Work/Meeting notes.md")
        .dynamicTypeSize(.accessibility2)
}
