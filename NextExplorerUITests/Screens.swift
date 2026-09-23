import CoreModels
import Localization
import XCTest

// Screen objects: one place per screen for element locators, so a changed identifier or string
// is fixed once. Every property is a live query (recomputed on access), never a cached element.

extension XCUIApplication {
    /// A button matched by its visible label rather than identifier. Menu and context menu items
    /// carry icon derived identifiers (e.g. "checkmark.circle"), so the `app.buttons["Label"]`
    /// subscript, which matches identifiers, misses them.
    func labeledButton(_ label: String) -> XCUIElement {
        buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
    }
}

struct TabBar {
    let app: XCUIApplication
    var browse: XCUIElement {
        app.buttons[AccessibilityIdentifiers.Tab.browse]
    }

    var favorites: XCUIElement {
        app.buttons[AccessibilityIdentifiers.Tab.favorites]
    }

    var shared: XCUIElement {
        app.buttons[AccessibilityIdentifiers.Tab.shared]
    }

    var downloads: XCUIElement {
        app.buttons[AccessibilityIdentifiers.Tab.downloads]
    }

    var settings: XCUIElement {
        app.buttons[AccessibilityIdentifiers.Tab.settings]
    }
}

struct LoginScreen {
    let app: XCUIApplication
    var hostField: XCUIElement {
        app.textFields[AccessibilityIdentifiers.Login.hostField]
    }

    var testConnectionButton: XCUIElement {
        app.buttons[AccessibilityIdentifiers.Login.testConnectionButton]
    }

    var emailField: XCUIElement {
        app.textFields[AccessibilityIdentifiers.Login.emailField]
    }

    var passwordField: XCUIElement {
        app.secureTextFields[AccessibilityIdentifiers.Login.passwordField]
    }

    var submitButton: XCUIElement {
        app.buttons[AccessibilityIdentifiers.Login.submitButton]
    }
}

struct BrowseScreen {
    let app: XCUIApplication
    /// The breadcrumb's leading "Locations" crumb. The bar only shows below the root, so it
    /// proves a push into a folder landed (the upload menu exists at the root too).
    var breadcrumbRoot: XCUIElement {
        app.buttons[L10n.Browse.locations].firstMatch
    }

    var searchField: XCUIElement {
        app.textFields[AccessibilityIdentifiers.Search.field]
    }

    var uploadMenu: XCUIElement {
        app.buttons[AccessibilityIdentifiers.Browse.uploadMenu]
    }

    var emptyStateMessage: XCUIElement {
        app.staticTexts[L10n.EmptyState.folderEmpty]
    }

    var retryButton: XCUIElement {
        app.buttons[L10n.Common.retry].firstMatch
    }

    var previewBackButton: XCUIElement {
        app.navigationBars.buttons.firstMatch
    }

    /// A file or folder row's name label.
    func item(_ name: String) -> XCUIElement {
        app.staticTexts[name]
    }

    /// The tappable/long-pressable row button (its label bundles name + metadata, so match on a
    /// substring). Long press this, not the name label, to open the row's context menu.
    func row(_ name: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
    }

    /// New folder flow. Menu and sheet buttons are matched by label (icon identifiers shadow them).
    var newFolderMenuItem: XCUIElement {
        app.labeledButton(L10n.Browse.actionNewFolder)
    }

    var newFolderNameField: XCUIElement {
        app.textFields[L10n.Browse.newFolderPlaceholder]
    }

    var newFolderConfirm: XCUIElement {
        app.labeledButton(L10n.Browse.newFolderConfirm)
    }

    /// The trailing "..." toolbar menu (Select / Sort / view toggle / clipboard paste).
    var moreMenu: XCUIElement {
        app.buttons[AccessibilityIdentifiers.Browse.moreMenu]
    }

    var selectMenuItem: XCUIElement {
        app.labeledButton(L10n.Common.select)
    }

    var selectAllButton: XCUIElement {
        app.labeledButton(L10n.Select.selectAll)
    }

    var cancelButton: XCUIElement {
        app.labeledButton(L10n.Common.cancel)
    }

    var pasteMenuItem: XCUIElement {
        app.labeledButton(L10n.Browse.actionPaste)
    }

    /// Row context menu actions (surfaced by long pressing a row).
    var renameAction: XCUIElement {
        app.labeledButton(L10n.Browse.actionRename)
    }

    var copyAction: XCUIElement {
        app.labeledButton(L10n.Browse.actionCopy)
    }

    var shareAction: XCUIElement {
        app.labeledButton(L10n.Browse.actionShare)
    }

    var deleteAction: XCUIElement {
        app.labeledButton(L10n.Browse.actionDelete)
    }

    /// Rename sheet.
    var renameNameField: XCUIElement {
        app.textFields[L10n.Browse.renameNamePlaceholder]
    }

    var renameConfirm: XCUIElement {
        app.labeledButton(L10n.Common.save)
    }

    /// Delete confirmation sheet's destructive button.
    var deleteConfirmButton: XCUIElement {
        app.labeledButton(L10n.Common.delete)
    }

    /// Create share link sheet's submit button (proof the sheet opened).
    var createShareSubmit: XCUIElement {
        app.labeledButton(L10n.CreateShare.submit)
    }

    /// A search filter chip, matched by its category label (e.g. Images).
    func filterChip(_ label: String) -> XCUIElement {
        app.labeledButton(label)
    }

    /// New folder / rename sheet validation error for a name with a path separator.
    var separatorNameError: XCUIElement {
        app.staticTexts[L10n.Browse.nameErrorSeparators]
    }

    /// Row context menu: favorite toggle (folders only).
    var addToFavoritesAction: XCUIElement {
        app.labeledButton(L10n.Browse.actionAddToFavorites)
    }

    var removeFromFavoritesAction: XCUIElement {
        app.labeledButton(L10n.Browse.actionRemoveFromFavorites)
    }

    var compressAction: XCUIElement {
        app.labeledButton(L10n.Browse.actionCompress)
    }

    /// The "..." menu's list/grid view toggle (reads "Grid View" while in list mode).
    var gridViewToggle: XCUIElement {
        app.labeledButton(L10n.Select.gridView)
    }

    /// The "..." menu's Sort entry, which opens the SortSheet.
    var sortMenuItem: XCUIElement {
        app.labeledButton(L10n.Common.sort)
    }

    /// SortSheet header, proof the sheet opened.
    var sortSheetTitle: XCUIElement {
        app.staticTexts[L10n.Sort.sheetTitle]
    }

    /// The SortSheet's "Descending" direction radio row. Its button label aggregates the icon,
    /// title and radio, so match on the title substring.
    var sortDescendingOption: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", L10n.Sort.descending)).firstMatch
    }

    /// SortSheet's circular close button (DSSheetHeader).
    var sortSheetClose: XCUIElement {
        app.labeledButton(L10n.Common.close)
    }

    /// The transient "Sync completed" toast a successful pull to refresh raises.
    var syncCompletedToast: XCUIElement {
        app.staticTexts[L10n.Common.syncCompleted]
    }

    /// Select mode bottom bar delete button (now carries an accessibility label).
    var bulkDeleteButton: XCUIElement {
        app.labeledButton(L10n.Browse.actionDelete)
    }
}

struct FavoritesScreen {
    let app: XCUIApplication
    var emptyMessage: XCUIElement {
        app.staticTexts[L10n.Favorites.emptyList]
    }

    func item(_ name: String) -> XCUIElement {
        app.staticTexts[name]
    }
}

struct SharedScreen {
    let app: XCUIApplication
    var byMeSegment: XCUIElement {
        app.buttons[L10n.Shared.segmentByMe].firstMatch
    }

    var withMeSegment: XCUIElement {
        app.buttons[L10n.Shared.segmentWithMe].firstMatch
    }

    var emptyByMe: XCUIElement {
        app.staticTexts[L10n.Shared.emptyByMe]
    }

    func item(_ name: String) -> XCUIElement {
        app.staticTexts[name]
    }
}

struct DownloadsScreen {
    let app: XCUIApplication
    var emptyMessage: XCUIElement {
        app.staticTexts[L10n.Downloads.emptyList]
    }
}

struct TextPreviewScreen {
    let app: XCUIApplication
    var editButton: XCUIElement {
        app.buttons[L10n.Common.edit].firstMatch
    }

    var saveButton: XCUIElement {
        app.buttons[L10n.Common.save].firstMatch
    }
}

struct SettingsScreen {
    let app: XCUIApplication
    var languageRow: XCUIElement {
        app.staticTexts[L10n.Settings.rowLanguage]
    }

    var signOutButton: XCUIElement {
        app.buttons[L10n.Settings.signOutButton].firstMatch
    }

    /// The active account row (expands to reveal Change Password / Sign Out). A stable identifier
    /// since its label is a combined accessibility element.
    var activeAccountRow: XCUIElement {
        app.buttons[AccessibilityIdentifiers.Settings.activeAccount].firstMatch
    }

    /// The DSAlertSheet's destructive confirm button.
    var confirmSignOut: XCUIElement {
        app.buttons[L10n.Common.logOut].firstMatch
    }

    var pushedBackButton: XCUIElement {
        app.navigationBars.buttons.firstMatch
    }

    /// Multi-server switcher: the Accounts section header and the "Add Account" row.
    var accountsSectionHeader: XCUIElement {
        app.staticTexts[L10n.Settings.sectionAccounts]
    }

    var addAccountRow: XCUIElement {
        app.buttons[L10n.Settings.addAccount].firstMatch
    }

    /// An account row in the switcher, matched on the server host in its combined accessibility
    /// label (the row folds its name/host into one element, so the host isn't a separate static
    /// text).
    func accountRow(host: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", host)).firstMatch
    }

    /// Admin section row that pushes the thumbnail settings screen.
    var thumbnailsRow: XCUIElement {
        app.staticTexts[L10n.Settings.rowThumbnails]
    }

    var thumbnailSettingsTitle: XCUIElement {
        app.staticTexts[L10n.ThumbnailSettings.navigationTitle]
    }

    /// The version footer's "buy me a coffee" button, matched on the coffee substring since the
    /// label is a two part attributed string.
    var tipButton: XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", L10n.Settings.creditsBuyCoffee)).firstMatch
    }

    var tipJarTitle: XCUIElement {
        app.staticTexts[L10n.TipJar.title]
    }

    /// The Offline section row that opens the file/folder chooser.
    var offlineDownloadRow: XCUIElement {
        app.staticTexts[L10n.Offline.settingsRow]
    }
}

/// The "Download for Offline" selection sheet presented from Settings.
struct OfflineSelectionScreen {
    let app: XCUIApplication

    var title: XCUIElement {
        app.staticTexts[L10n.Offline.selectionTitle]
    }

    func itemRow(_ name: String) -> XCUIElement {
        app.staticTexts[name].firstMatch
    }

    var downloadButton: XCUIElement {
        app.buttons[L10n.Offline.selectionDownload].firstMatch
    }

    var closeButton: XCUIElement {
        app.buttons[L10n.Common.close].firstMatch
    }
}
