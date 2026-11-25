#if os(macOS)
    import CoreModels
    import SwiftUI

    @MainActor
    @Observable
    final class MacToastCenter {
        enum Surface: Hashable {
            case pane
            case host(UUID)
        }

        struct Entry: Identifiable {
            let owner: UUID
            let surface: Surface
            let message: DSToastMessage
            let clear: (String) -> Void

            var id: String {
                message.id
            }
        }

        static let shared = MacToastCenter()
        static let maxKept = 5

        private(set) var entries: [Entry] = []
        private(set) var renderer: Surface?
        private(set) var isPaused = false
        @ObservationIgnored private var timers: [String: Task<Void, Never>] = [:]
        @ObservationIgnored private let dismissDelay: Duration

        init(dismissDelay: Duration = DSToastMessage.autoDismissDelay) {
            self.dismissDelay = dismissDelay
        }

        func update(
            from old: DSToastMessage?,
            to new: DSToastMessage?,
            owner: UUID,
            surface: Surface,
            clear: @escaping (String) -> Void
        ) {
            if let old, old != new, old.isPersistent || new == nil {
                if let new, new.isPersistent, old.isPersistent,
                   let index = entries.firstIndex(where: { $0.id == old.id })
                {
                    entries[index] = Entry(owner: owner, surface: surface, message: new, clear: clear)
                    return
                }
                remove(old.id)
            }
            guard let new, !entries.contains(where: { $0.id == new.id }) else { return }
            let entry = Entry(owner: owner, surface: surface, message: new, clear: clear)
            entries.append(entry)
            renderer = surface
            AccessibilityNotification.Announcement(new.text).post()
            schedule(entry)
            trim()
        }

        func dismiss(_ id: String) {
            guard let entry = entries.first(where: { $0.id == id }) else { return }
            remove(id)
            entry.clear(id)
        }

        func run(_ id: String) {
            let action = entries.first { $0.id == id }?.message.action
            dismiss(id)
            action?()
        }

        func hostGone(_ owner: UUID) {
            for entry in entries where entry.owner == owner {
                remove(entry.id)
            }
            if renderer == .host(owner) {
                renderer = entries.last?.surface
            }
        }

        func setPaused(_ paused: Bool) {
            guard paused != isPaused else { return }
            isPaused = paused
            if paused {
                timers.values.forEach { $0.cancel() }
                timers = [:]
            } else {
                entries.forEach(schedule)
            }
        }

        private func schedule(_ entry: Entry) {
            let message = entry.message
            guard !isPaused, !message.isPersistent,
                  !(UITestEnvironment.isActive && message.action != nil) else { return }
            let id = entry.id
            let delay = dismissDelay
            timers[id]?.cancel()
            timers[id] = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                self?.dismiss(id)
            }
        }

        private func remove(_ id: String) {
            timers.removeValue(forKey: id)?.cancel()
            entries.removeAll { $0.id == id }
        }

        private func trim() {
            while entries.count > Self.maxKept, let oldest = entries.first(where: { !$0.message.isPersistent }) {
                dismiss(oldest.id)
            }
        }
    }
#endif
