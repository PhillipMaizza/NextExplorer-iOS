import ComposableArchitecture
import CoreModels
import FilesClient
import FolderPickerFeature
import Foundation

/// The trash and file versions, for an administrator: whether deleting goes to the trash, how long
/// it keeps things and how much of a volume it may hold, how earlier versions of files are thinned
/// out, and per volume what is held, what the last maintenance did and whether the books agree
/// with the disk. Mirrors the web client's `SettingsTrash.vue`.
@Reducer
public struct TrashSettingsFeature {
    /// The trash form as typed: numbers stay text until saved, so a half typed value is not
    /// rounded under the admin's fingers.
    public struct TrashDraft: Equatable, Sendable {
        public var isEnabled: Bool
        public var retentionText: String
        public var maxPercentText: String
        public var maxSizeText: String
        /// What the server holds. The field shows it to two decimals, so an untouched field must
        /// send these bytes back and not the rounded text.
        private let originalMaxBytes: Int?

        public init(_ settings: TrashSettings = TrashSettings()) {
            originalMaxBytes = settings.maxBytes
            isEnabled = settings.isEnabled
            retentionText = String(settings.retentionDays)
            maxPercentText = String(settings.maxPercent)
            maxSizeText = settings.maxSizeGiBText
        }

        var parsed: TrashSettings? {
            guard let retention = Int(retentionText), TrashSettings.retentionRange.contains(retention),
                  let percent = Int(maxPercentText), TrashSettings.maxPercentRange.contains(percent)
            else { return nil }
            let maxBytes: Int?
            if maxSizeText == TrashSettings(maxBytes: originalMaxBytes).maxSizeGiBText {
                maxBytes = originalMaxBytes
            } else if let typed = TrashSettings.maxBytes(fromGiBText: maxSizeText) {
                maxBytes = typed
            } else {
                return nil
            }
            return TrashSettings(isEnabled: isEnabled, retentionDays: retention, maxPercent: percent, maxBytes: maxBytes)
        }
    }

    public struct VersionsDraft: Equatable, Sendable {
        public var isEnabled: Bool
        public var keepAllHoursText: String
        public var hourlyDaysText: String
        public var dailyDaysText: String
        public var maxPerFileText: String
        public var checkpointMinutesText: String

        public init(_ settings: VersionsSettings = VersionsSettings()) {
            isEnabled = settings.isEnabled
            keepAllHoursText = String(settings.keepAllHours)
            hourlyDaysText = String(settings.hourlyDays)
            dailyDaysText = String(settings.dailyDays)
            maxPerFileText = String(settings.maxPerFile)
            checkpointMinutesText = String(settings.sessionCheckpointMinutes)
        }

        var parsed: VersionsSettings? {
            guard let keepAll = Int(keepAllHoursText), VersionsSettings.keepAllHoursRange.contains(keepAll),
                  let hourly = Int(hourlyDaysText), VersionsSettings.hourlyDaysRange.contains(hourly),
                  let daily = Int(dailyDaysText), VersionsSettings.dailyDaysRange.contains(daily),
                  let perFile = Int(maxPerFileText), VersionsSettings.maxPerFileRange.contains(perFile),
                  let checkpoint = Int(checkpointMinutesText), VersionsSettings.sessionCheckpointMinutesRange.contains(checkpoint)
            else { return nil }
            let tieredHourly = VersionsSettings.hourlyDays(hourly, keepAllHours: keepAll)
            return VersionsSettings(
                isEnabled: isEnabled,
                keepAllHours: keepAll,
                hourlyDays: tieredHourly,
                dailyDays: max(daily, tieredHourly),
                maxPerFile: perFile,
                sessionCheckpointMinutes: checkpoint
            )
        }
    }

    public enum VersionField: Equatable, Sendable {
        case keepAllHours, hourlyDays, dailyDays, maxPerFile, checkpointMinutes
    }

    /// What a save sent back: only the sections that were saved.
    public struct SavedSettings: Equatable, Sendable {
        public var trash: TrashSettings?
        public var versions: VersionsSettings?
    }

    @ObservableState
    public struct State: Equatable {
        public let serverURL: URL
        public var loadedTrash: TrashSettings?
        public var loadedVersions: VersionsSettings?
        public var trashDraft = TrashDraft()
        public var versionsDraft = VersionsDraft()
        public var phase: DataPhase = .idle
        public var isSaving = false
        public var errorMessage: String?
        public var isUnavailable = false

        public var zones: [TrashZone] = []
        public var zonesPhase: DataPhase = .idle
        public var zonesError: String?
        public var verification: [TrashVerification]?
        public var isVerifying = false
        public var isMaintaining = false

        public init(serverURL: URL) {
            self.serverURL = serverURL
        }

        var isTrashDirty: Bool {
            guard let loadedTrash else { return false }
            return trashDraft != TrashDraft(loadedTrash)
        }

        var isVersionsDirty: Bool {
            guard let loadedVersions else { return false }
            return versionsDraft != VersionsDraft(loadedVersions)
        }

        var isDirty: Bool {
            isTrashDirty || isVersionsDirty
        }

        /// A form that was not touched cannot be wrong, so only a changed one is checked.
        var isTrashInvalid: Bool {
            isTrashDirty && trashDraft.parsed == nil
        }

        var isVersionsInvalid: Bool {
            isVersionsDirty && versionsDraft.parsed == nil
        }

        var isSaveEnabled: Bool {
            isDirty && !isTrashInvalid && !isVersionsInvalid && !isSaving
        }

        var totalViolations: Int {
            (verification ?? []).reduce(0) { $0 + $1.violationCount }
        }
    }

    public enum Action: Equatable, Sendable {
        case onAppear
        case settingsResponse(Result<SystemSettings, FilesClientError>)
        case zonesResponse(Result<[TrashZone], FilesClientError>)
        case trashEnabledChanged(Bool)
        case retentionChanged(String)
        case maxPercentChanged(String)
        case maxSizeChanged(String)
        case versionsEnabledChanged(Bool)
        case versionFieldChanged(VersionField, String)
        case discardTapped
        case saveTapped
        case saveResponse(Result<SavedSettings, FilesClientError>)
        case verifyTapped
        case verifyResponse(Result<[TrashVerification], FilesClientError>)
        case maintenanceTapped
        case maintenanceResponse(Result<Bool, FilesClientError>)
    }

    @Dependency(\.filesClient) var filesClient

    private enum CancelID { case settings, zones, save, verify, maintenance }

    public init() {}

    private func loadZones(_ state: inout State) -> Effect<Action> {
        state.zonesPhase.beginReload()
        state.zonesError = nil
        let serverURL = state.serverURL
        let filesClient = filesClient
        return .api(
            cancelID: CancelID.zones,
            operation: { try await filesClient.fetchTrashZones(serverURL) },
            response: { .zonesResponse($0) }
        )
    }

    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                guard !state.isSaving else { return .none }
                state.phase.beginReload()
                state.errorMessage = nil
                let settings = Effect<Action>.loadSettings(
                    filesClient,
                    serverURL: state.serverURL,
                    cancelID: CancelID.settings,
                    response: { .settingsResponse($0) }
                )
                return .merge(settings, loadZones(&state))

            case .settingsResponse(.success) where state.isSaving:
                return .none

            case let .settingsResponse(.success(settings)):
                state.phase = .loaded
                state.isUnavailable = false
                guard let trash = settings.trash, let versions = settings.versions else {
                    state.isUnavailable = true
                    return .none
                }
                if !state.isTrashDirty {
                    state.trashDraft = TrashDraft(trash)
                }
                if !state.isVersionsDirty {
                    state.versionsDraft = VersionsDraft(versions)
                }
                state.loadedTrash = trash
                state.loadedVersions = versions
                return .none

            case let .settingsResponse(.failure(error)):
                if state.loadedTrash == nil {
                    state.phase = .failed(error.userMessage)
                } else {
                    state.errorMessage = error.userMessage
                }
                return .none

            case let .zonesResponse(.success(zones)):
                state.zonesPhase = .loaded
                state.zones = zones
                return .none

            case let .zonesResponse(.failure(error)):
                state.zonesPhase = state.zones.isEmpty ? .failed(error.userMessage) : .loaded
                state.zonesError = error.userMessage
                return .none

            case let .trashEnabledChanged(isOn):
                state.trashDraft.isEnabled = isOn
                state.errorMessage = nil
                return .none

            case let .retentionChanged(text):
                state.trashDraft.retentionText = text.filter(\.isASCIIDigit)
                state.errorMessage = nil
                return .none

            case let .maxPercentChanged(text):
                state.trashDraft.maxPercentText = text.filter(\.isASCIIDigit)
                state.errorMessage = nil
                return .none

            case let .maxSizeChanged(text):
                state.trashDraft.maxSizeText = text.filter { $0.isASCIIDigit || $0 == "." || $0 == "," }
                state.errorMessage = nil
                return .none

            case let .versionsEnabledChanged(isOn):
                state.versionsDraft.isEnabled = isOn
                state.errorMessage = nil
                return .none

            case let .versionFieldChanged(field, text):
                let digits = text.filter(\.isASCIIDigit)
                switch field {
                case .keepAllHours: state.versionsDraft.keepAllHoursText = digits
                case .hourlyDays: state.versionsDraft.hourlyDaysText = digits
                case .dailyDays: state.versionsDraft.dailyDaysText = digits
                case .maxPerFile: state.versionsDraft.maxPerFileText = digits
                case .checkpointMinutes: state.versionsDraft.checkpointMinutesText = digits
                }
                state.errorMessage = nil
                return .none

            case .discardTapped:
                if let trash = state.loadedTrash {
                    state.trashDraft = TrashDraft(trash)
                }
                if let versions = state.loadedVersions {
                    state.versionsDraft = VersionsDraft(versions)
                }
                state.errorMessage = nil
                return .none

            case .saveTapped:
                guard state.isSaveEnabled else { return .none }
                var patch = SystemSettingsPatch()
                if state.isTrashDirty {
                    patch.trash = state.trashDraft.parsed
                }
                if state.isVersionsDirty {
                    patch.versions = state.versionsDraft.parsed
                }
                state.isSaving = true
                state.errorMessage = nil
                let sentTrash = patch.trash != nil
                let sentVersions = patch.versions != nil
                let serverURL = state.serverURL
                let filesClient = filesClient
                let saveEffect = Effect<Action>.api(
                    cancelID: CancelID.save,
                    operation: { [patch] in
                        let echoed = try await filesClient.updateSystemSettings(serverURL, patch)
                        if sentTrash, echoed.trash == nil {
                            throw FilesClientError.decoding("Settings response carried no trash settings.")
                        }
                        if sentVersions, echoed.versions == nil {
                            throw FilesClientError.decoding("Settings response carried no version settings.")
                        }
                        return SavedSettings(
                            trash: sentTrash ? echoed.trash : nil,
                            versions: sentVersions ? echoed.versions : nil
                        )
                    },
                    response: { .saveResponse($0) }
                )
                return .merge(.cancel(id: CancelID.settings), saveEffect)

            case let .saveResponse(.success(saved)):
                state.isSaving = false
                if let trash = saved.trash {
                    state.loadedTrash = trash
                    state.trashDraft = TrashDraft(trash)
                }
                if let versions = saved.versions {
                    state.loadedVersions = versions
                    state.versionsDraft = VersionsDraft(versions)
                }
                return loadZones(&state)

            case let .saveResponse(.failure(error)):
                state.isSaving = false
                state.errorMessage = error.userMessage
                return .none

            case .verifyTapped:
                guard !state.isVerifying else { return .none }
                state.isVerifying = true
                state.zonesError = nil
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .api(
                    cancelID: CancelID.verify,
                    operation: { try await filesClient.verifyTrash(serverURL) },
                    response: { .verifyResponse($0) }
                )

            case let .verifyResponse(.success(results)):
                state.isVerifying = false
                state.verification = results
                return .none

            case let .verifyResponse(.failure(error)):
                state.isVerifying = false
                state.zonesError = error.userMessage
                return .none

            case .maintenanceTapped:
                guard !state.isMaintaining else { return .none }
                state.isMaintaining = true
                state.zonesError = nil
                let serverURL = state.serverURL
                let filesClient = filesClient
                return .api(
                    cancelID: CancelID.maintenance,
                    operation: {
                        try await filesClient.runTrashMaintenance(serverURL)
                        return true
                    },
                    response: { .maintenanceResponse($0) }
                )

            case .maintenanceResponse(.success):
                state.isMaintaining = false
                state.verification = nil
                return loadZones(&state)

            case let .maintenanceResponse(.failure(error)):
                state.isMaintaining = false
                state.zonesError = error.userMessage
                return .none
            }
        }
    }
}
