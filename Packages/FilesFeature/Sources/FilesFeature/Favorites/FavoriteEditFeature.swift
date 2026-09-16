import ComposableArchitecture
import CoreModels
import FilesClient
import Foundation

/// Editing one favorite's name, icon and colour via `PATCH /api/favorites/:id`, mirroring
/// the web client's `FavoriteEditDialog.vue`. Presented as a sheet from the Favorites tab;
/// the path itself is fixed and shown read only.
@Reducer
public struct FavoriteEditFeature {
    public enum IconStyle: String, Equatable, Sendable, CaseIterable {
        case outline, solid
    }

    /// Semantic name-field error; the view maps it to `L10n`.
    public enum NameError: Equatable, Sendable {
        case empty
    }

    @ObservableState
    public struct State: Equatable, Identifiable {
        public let serverURL: URL
        public let favorite: Favorite
        public var nameDraft: String
        public var iconDraft: String
        public var iconStyleDraft: IconStyle
        public var colorDraft: String?
        public var isSaving = false
        public var errorMessage: String?

        public var id: Favorite.ID {
            favorite.id
        }

        public init(serverURL: URL, favorite: Favorite) {
            self.serverURL = serverURL
            self.favorite = favorite
            // Seeded from the resolved display name (folder name when no label is set) so the
            // field is never empty on open and a save always keeps a real name.
            nameDraft = favorite.displayName
            iconDraft = FavoriteIcon.bareName(favorite.icon) ?? FavoriteIcon.fallbackName
            iconStyleDraft = FavoriteIcon.isFilled(favorite.icon) ? .solid : .outline
            colorDraft = favorite.color
        }

        var trimmedName: String {
            nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var nameError: NameError? {
            trimmedName.isEmpty ? .empty : nil
        }

        /// The `"<style>:<name>"` token this edit would persist.
        var iconToken: String {
            FavoriteIcon.token(name: iconDraft, filled: iconStyleDraft == .solid)
        }

        private var originalIcon: String {
            FavoriteIcon.token(
                name: FavoriteIcon.bareName(favorite.icon) ?? FavoriteIcon.fallbackName,
                filled: FavoriteIcon.isFilled(favorite.icon)
            )
        }

        var isDirty: Bool {
            trimmedName != favorite.displayName
                || iconToken != originalIcon
                || !FavoriteColor.matches(colorDraft, favorite.color)
        }

        var isSaveEnabled: Bool {
            isDirty && nameError == nil && !isSaving
        }
    }

    public enum Action: Equatable, Sendable {
        case nameChanged(String)
        case iconSelected(String)
        case iconStyleSelected(IconStyle)
        case colorSelected(String?)
        case saveTapped
        case saveResponse(Result<Favorite, FilesClientError>)
        case delegate(Delegate)

        public enum Delegate: Equatable, Sendable {
            case updated(Favorite)
        }
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case save }

    public init() {}

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case let .nameChanged(value):
                state.nameDraft = value
                state.errorMessage = nil
                return .none

            case let .iconSelected(icon):
                state.iconDraft = icon
                state.errorMessage = nil
                return .none

            case let .iconStyleSelected(style):
                state.iconStyleDraft = style
                state.errorMessage = nil
                return .none

            case let .colorSelected(color):
                state.colorDraft = color
                state.errorMessage = nil
                return .none

            case .saveTapped:
                guard state.isSaveEnabled else { return .none }
                state.isSaving = true
                state.errorMessage = nil
                let serverURL = state.serverURL
                let id = state.favorite.id
                let label = state.trimmedName
                let icon = state.iconToken
                let color = state.colorDraft
                let filesClient = filesClient
                return .run { send in
                    try await send(.saveResponse(apiResult {
                        try await filesClient.updateFavorite(serverURL, id, label, icon, color)
                    }))
                }
                .cancellable(id: CancelID.save, cancelInFlight: true)

            case let .saveResponse(.success(favorite)):
                state.isSaving = false
                return .send(.delegate(.updated(favorite)))

            case let .saveResponse(.failure(error)):
                state.isSaving = false
                state.errorMessage = error.userMessage
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
