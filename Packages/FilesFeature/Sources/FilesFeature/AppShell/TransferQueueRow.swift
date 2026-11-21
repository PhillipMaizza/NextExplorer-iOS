import Foundation

struct TransferQueueRow: Identifiable {
    enum Status {
        case waiting
        case running(progress: Double?, detail: String?)
        case done(String)
        case failed(String)
    }

    let id: UUID
    let name: String
    let status: Status
}
