import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

/// The admin activity log: the switch that fills it, how long a line is kept, and the list of
/// what was recorded, with filters and paging. Mirrors the web client's `SettingsActivity.vue`.
@Reducer
public struct ActivityLogFeature {
    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        public var loadedSettings: ActivitySettings?
        public var isEnabledDraft = false
        public var retentionText = String(ActivitySettings.defaultRetentionDays)
        public var isSavingSettings = false
        public var settingsError: String?
        public var isUnavailable = false

        public var events: [ActivityEvent] = []
        public var actions: [String] = []
        public var isLogEnabled = false
        public var nextBefore: String?
        public var filter = ActivityFilter()
        /// The filter the list on screen was fetched with. Paging continues from this one, so a
        /// search typed but not submitted never mixes into the next page of the old one.
        public var submittedFilter = ActivityFilter()
        public var phase: DataPhase = .idle
        public var isLoadingMore = false
        public var listError: String?

        public var isConfirmingClear = false
        public var isClearing = false

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        var retentionDays: Int? {
            guard let days = Int(retentionText.trimmingCharacters(in: .whitespaces)),
                  ActivitySettings.retentionRange.contains(days) else { return nil }
            return days
        }

        var isRetentionValid: Bool {
            retentionDays != nil
        }

        var isSettingsDirty: Bool {
            guard let loadedSettings else { return false }
            return isEnabledDraft != loadedSettings.isEnabled || retentionDays != loadedSettings.retentionDays
        }

        var isSaveSettingsEnabled: Bool {
            isSettingsDirty && isRetentionValid && !isSavingSettings
        }

        var canLoadMore: Bool {
            nextBefore != nil && !isLoadingMore
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case settingsResponse(Result<SystemSettings, FilesClientError>)
        case pageResponse(Result<ActivityPage, FilesClientError>, isMore: Bool)
        case enabledChanged(Bool)
        case retentionChanged(String)
        case saveSettingsTapped
        case saveSettingsResponse(Result<ActivitySettings, FilesClientError>)
        case actionFilterChanged(String?)
        case outcomeFilterChanged(ActivityOutcome?)
        case queryChanged(String)
        case searchSubmitted
        case refreshTapped
        case loadMoreTapped
        case clearTapped
        case clearCancelled
        case clearConfirmed
        case clearResponse(Result<Bool, FilesClientError>)
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case settings, page, save, clear }

    public init() {}

    private func loadPage(_ state: inout State, more: Bool) -> Effect<Action> {
        if more {
            guard state.canLoadMore else { return .none }
            state.isLoadingMore = true
        } else {
            state.phase.beginReload()
            state.nextBefore = nil
            state.submittedFilter = state.filter
        }
        state.listError = nil
        let serverURL = state.serverURL
        let filter = state.submittedFilter
        let before = more ? state.nextBefore : nil
        let filesClient = filesClient
        return .api(
            cancelID: CancelID.page,
            operation: { try await filesClient.fetchActivity(serverURL, filter, before) },
            response: { .pageResponse($0, isMore: more) }
        )
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.isSavingSettings else { return .none }
                let settings = Effect<Action>.loadSettings(
                    filesClient,
                    serverURL: state.serverURL,
                    cancelID: CancelID.settings,
                    response: { .settingsResponse($0) }
                )
                return .merge(settings, loadPage(&state, more: false))

            case .settingsResponse(.success) where state.isSavingSettings:
                return .none

            case let .settingsResponse(.success(settings)):
                state.isUnavailable = false
                guard let activity = settings.activity else {
                    state.isUnavailable = true
                    return .none
                }
                let untouched = !state.isSettingsDirty
                state.loadedSettings = activity
                if untouched {
                    state.isEnabledDraft = activity.isEnabled
                    state.retentionText = String(activity.retentionDays)
                }
                return .none

            case let .settingsResponse(.failure(error)):
                state.settingsError = error.userMessage
                return .none

            case let .pageResponse(.success(page), isMore):
                state.phase = .loaded
                state.isLoadingMore = false
                state.events = isMore ? state.events + page.events : page.events
                state.actions = page.actions
                state.isLogEnabled = page.isEnabled
                state.nextBefore = page.nextBefore
                return .none

            case let .pageResponse(.failure(error), isMore):
                state.isLoadingMore = false
                if isMore || state.phase.hasLoaded {
                    state.listError = error.userMessage
                } else {
                    state.phase = .failed(error.userMessage)
                }
                return .none

            case let .enabledChanged(isOn):
                state.isEnabledDraft = isOn
                state.settingsError = nil
                return .none

            case let .retentionChanged(text):
                state.retentionText = text.filter(\.isASCIIDigit)
                state.settingsError = nil
                return .none

            case .saveSettingsTapped:
                guard state.isSaveSettingsEnabled, let days = state.retentionDays else { return .none }
                state.isSavingSettings = true
                state.settingsError = nil
                return .saveSettings(
                    filesClient,
                    serverURL: state.serverURL,
                    patch: SystemSettingsPatch(activity: ActivitySettings(
                        isEnabled: state.isEnabledDraft,
                        retentionDays: days
                    )),
                    section: \.activity,
                    missingMessage: "Settings response carried no activity.",
                    cancelLoad: CancelID.settings,
                    cancelID: CancelID.save,
                    response: { .saveSettingsResponse($0) }
                )

            case let .saveSettingsResponse(.success(activity)):
                state.isSavingSettings = false
                state.loadedSettings = activity
                state.isEnabledDraft = activity.isEnabled
                state.retentionText = String(activity.retentionDays)
                return loadPage(&state, more: false)

            case let .saveSettingsResponse(.failure(error)):
                state.isSavingSettings = false
                state.settingsError = error.userMessage
                return .none

            case let .actionFilterChanged(action):
                state.filter.action = action
                return loadPage(&state, more: false)

            case let .outcomeFilterChanged(outcome):
                state.filter.outcome = outcome
                return loadPage(&state, more: false)

            case let .queryChanged(query):
                state.filter.query = query
                return .none

            case .searchSubmitted, .refreshTapped:
                return loadPage(&state, more: false)

            case .loadMoreTapped:
                return loadPage(&state, more: true)

            case .clearTapped:
                state.isConfirmingClear = true
                return .none

            case .clearCancelled:
                state.isConfirmingClear = false
                return .none

            case .clearConfirmed:
                state.isConfirmingClear = false
                state.isClearing = true
                state.listError = nil
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .api(
                    cancelID: CancelID.clear,
                    operation: {
                        try await filesClient.clearActivity(serverURL)
                        return true
                    },
                    response: { .clearResponse($0) }
                )

            case .clearResponse(.success):
                state.isClearing = false
                return loadPage(&state, more: false)

            case let .clearResponse(.failure(error)):
                state.isClearing = false
                state.listError = error.userMessage
                return .none
            }
        }
    }
}
