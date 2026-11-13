import FilesClient
import Localization

/// What every search says under a term too short for the server to search.
public enum SearchHint {
    public static var tooShort: String {
        L10n.Browse.searchTooShort(FilesClient.minimumSearchTermLength)
    }
}
