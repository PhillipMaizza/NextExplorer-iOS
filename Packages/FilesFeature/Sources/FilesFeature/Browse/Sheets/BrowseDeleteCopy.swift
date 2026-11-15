import AppStorageKeys
import ComposableArchitecture
import CoreModels
import DesignSystem
import FilesClient
import Localization
import SwiftUI

/// The words of the single and bulk delete confirmations.
enum BrowseDeleteCopy {
    static func title(_ store: StoreOf<BrowseFeature>) -> String {
        guard let item = store.deleteConfirmationItem else { return L10n.Browse.deleteConfirmTitle }
        return L10n.Browse.deleteConfirmOne(item.name)
    }

    static func bulkTitle(_ store: StoreOf<BrowseFeature>) -> String {
        let selected = store.items.filter { store.selectedItemIDs.contains($0.id) }
        if selected.count == 1, let item = selected.first {
            return L10n.Browse.deleteConfirmOne(item.name)
        }
        return L10n.Browse.deleteConfirmMany(store.selectedItemIDs.count)
    }

    /// `deleteMessage` plus, once `delete-impact` answers, a line about the share links the
    /// delete would break. Shared by the single and bulk delete alerts since only one is
    /// ever up. A still running or failed check adds nothing or a soft note respectively.
    static func message(_ store: StoreOf<BrowseFeature>) -> String {
        let base = L10n.Browse.deleteMessage
        switch store.deleteImpactCheck {
        case let .loaded(impact) where impact.shareCount == 1:
            return base + "\n\n" + L10n.Browse.deleteLinkedSharesOne
        case let .loaded(impact) where impact.shareCount > 1:
            return base + "\n\n" + L10n.Browse.deleteLinkedSharesMany(impact.shareCount)
        case .unavailable:
            return base + "\n\n" + L10n.Browse.deleteLinkedSharesUnavailable
        case .idle, .checking, .loaded:
            return base
        }
    }
}
