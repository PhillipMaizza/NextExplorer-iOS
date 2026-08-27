import SwiftUI

/// Central catalog of the app's SF Symbols: one name per icon, spelled once, so call
/// sites never type a raw `Image(systemName:)` string. Named for what the icon *means* at
/// its call site(s) wherever there's one clear meaning (e.g. `download`, `search`) — a few
/// (`folder`/`folderFill`, `star`/`starFill`, `document`, `tag`, `calendar`, ...) stay literal
/// because they're genuinely reused across unrelated meanings (a directory icon, a tab icon,
/// and a "this is a folder" row glyph, for instance), where a single semantic name would be
/// wrong at some of its own call sites.
public enum IconKit {
    public static let checkmark = Image(systemName: "checkmark")
    public static let close = Image(systemName: "xmark")
    public static let back = Image(systemName: "chevron.left")
    public static let envelope = Image(systemName: "envelope")
    public static let lock = Image(systemName: "lock")
    public static let lockOpen = Image(systemName: "lock.open")
    public static let eye = Image(systemName: "eye")
    public static let eyeSlash = Image(systemName: "eye.slash")
    public static let person = Image(systemName: "person")
    public static let logo = Image("logo", bundle: .module)

    /// Static vector artwork exported from Symbols.app (Template rendering, single scale),
    /// not `Image(systemName:)` — `Tab(value:)`'s automatic outline/filled swap by selection
    /// does not hold on iOS 26+'s "Liquid Glass" tab bar, which renders every tab icon filled
    /// regardless of API or symbol variant used (verified on a real iOS 27 device). `MainTabView`
    /// picks the outline/filled pair explicitly by selection state instead.
    public static let tabBrowse = Image("tabBrowse", bundle: .module).renderingMode(.template)
    public static let tabBrowseFill = Image("tabBrowseFill", bundle: .module).renderingMode(.template)
    public static let tabFavorites = Image("tabFavorites", bundle: .module).renderingMode(.template)
    public static let tabFavoritesFill = Image("tabFavoritesFill", bundle: .module).renderingMode(.template)
    public static let tabShare = Image("tabShare", bundle: .module).renderingMode(.template)
    public static let tabShareFill = Image("tabShareFill", bundle: .module).renderingMode(.template)
    public static let tabDownloads = Image("tabDownloads", bundle: .module).renderingMode(.template)
    public static let tabDownloadsFill = Image("tabDownloadsFill", bundle: .module).renderingMode(.template)
    public static let tabSettings = Image("tabSettings", bundle: .module).renderingMode(.template)
    public static let tabSettingsFill = Image("tabSettingsFill", bundle: .module).renderingMode(.template)

    // Main screen (browse / favorites / settings)
    public static let folder = Image(systemName: "folder")
    public static let folderFill = Image(systemName: "folder.fill")
    public static let document = Image(systemName: "doc")
    public static let search = Image(systemName: "magnifyingglass")
    public static let star = Image(systemName: "star")
    public static let starFill = Image(systemName: "star.fill")
    public static let gearshape = Image(systemName: "gearshape")
    public static let chevronRight = Image(systemName: "chevron.right")
    public static let warning = Image(systemName: "exclamationmark.triangle")
    public static let darkMode = Image(systemName: "moon.fill")
    public static let signOut = Image(systemName: "rectangle.portrait.and.arrow.right")
    public static let photo = Image(systemName: "photo")
    public static let web = Image(systemName: "globe")
    public static let server = Image(systemName: "macpro.gen3.server")
    public static let listBullet = Image(systemName: "list.bullet")
    public static let squareGrid = Image(systemName: "square.grid.2x2")
    public static let sort = Image(systemName: "arrow.up.arrow.down")
    public static let sortAscending = Image(systemName: "arrow.up")
    public static let sortDescending = Image(systemName: "arrow.down")
    /// "Go up one level" in a hierarchy (e.g. the admin volume directory picker).
    public static let levelUp = Image(systemName: "arrow.up.left")
    public static let textformat = Image(systemName: "textformat")
    public static let calendar = Image(systemName: "calendar")
    public static let home = Image(systemName: "house")
    public static let radioUnselected = Image(systemName: "circle")
    public static let radioSelected = Image(systemName: "largecircle.fill.circle")
    public static let tag = Image(systemName: "tag")
    public static let delete = Image(systemName: "trash")
    public static let time = Image(systemName: "clock")
    public static let rename = Image(systemName: "square.and.pencil")
    public static let haptics = Image(systemName: "waveform")
    public static let download = Image(systemName: "arrow.down.circle")
    public static let checkmarkCircleFill = Image(systemName: "checkmark.circle.fill")
    public static let moreOptions = Image(systemName: "ellipsis.circle")
    public static let selectAll = Image(systemName: "checklist")
    public static let share = Image(systemName: "square.and.arrow.up")
    public static let drive = Image(systemName: "externaldrive.fill")
    public static let shareLink = Image(systemName: "point.3.connected.trianglepath.dotted")
    public static let link = Image(systemName: "link")
    public static let people = Image(systemName: "person.2")
    public static let copy = Image(systemName: "doc.on.doc")
    public static let shield = Image(systemName: "checkmark.shield")
    public static let key = Image(systemName: "key")
    public static let cloud = Image(systemName: "cloud")
    public static let plus = Image(systemName: "plus")
    public static let archivePage = Image(systemName: "zipper.page")
    public static let select = Image(systemName: "checkmark.circle")
    public static let unfavorite = Image(systemName: "star.slash")
    public static let info = Image(systemName: "info.circle")
    public static let extract = Image(systemName: "archivebox")
    public static let archiveDocument = Image(systemName: "doc.zipper")
    public static let size = Image(systemName: "internaldrive")
}
