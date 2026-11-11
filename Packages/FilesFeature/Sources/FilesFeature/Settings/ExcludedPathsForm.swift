import CoreModels

/// The list of excluded folders the search index and folder size pages edit, which behaves the
/// same way on both: a draft beside what the server has, an add field, and a Save and Discard.
protocol ExcludedPathsForm {
    var draftPaths: [String] { get set }
    var newPath: String { get set }
    var isSaving: Bool { get }
    var loadedExcluded: ExcludedPaths? { get }
}

extension ExcludedPathsForm {
    var environmentPaths: [String] {
        loadedExcluded?.environmentPaths ?? []
    }

    /// Every path the server has or the draft holds, so one unchecked stays on screen, ready to be
    /// checked again, until the change is saved or discarded.
    var displayedPaths: [String] {
        Set(loadedExcluded?.paths ?? []).union(draftPaths).sorted { $0.localizedCompare($1) == .orderedAscending }
    }

    var isDirty: Bool {
        guard let loadedExcluded else { return false }
        return draftPaths != loadedExcluded.paths
    }

    var isSaveEnabled: Bool {
        isDirty && !isSaving
    }

    mutating func addNewPath() {
        draftPaths = ExcludedPaths(paths: draftPaths, environmentPaths: environmentPaths).adding(newPath)
        newPath = ""
    }

    mutating func togglePath(_ path: String) {
        if draftPaths.contains(path) {
            draftPaths.removeAll { $0 == path }
        } else {
            draftPaths = ExcludedPaths(paths: draftPaths).adding(path)
        }
    }

    mutating func discardPaths() {
        draftPaths = loadedExcluded?.paths ?? []
        newPath = ""
    }

    /// Whether the edits on screen must survive what the server just answered: they do while they
    /// are unsaved, unless this answer is the save of the paths themselves.
    func keepsUnsavedEdits(whenReplacing replacesPaths: Bool) -> Bool {
        isDirty && !replacesPaths
    }

    mutating func adopt(serverPaths: [String], keepingUnsavedEdits: Bool) {
        if !keepingUnsavedEdits {
            draftPaths = serverPaths
        }
    }
}
