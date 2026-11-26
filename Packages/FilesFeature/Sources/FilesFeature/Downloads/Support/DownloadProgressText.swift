import Foundation
import Localization

/// The "412 MB of 1.6 GB · 2 min left" line under a running download. Without a total (a folder
/// zip streamed on the fly) it is just the byte count; the estimate appears once a rate settles.
enum DownloadProgressText {
    private static let separator = " · "

    static func detail(for job: DownloadQueueFeature.DownloadJob, locale: Locale) -> String? {
        guard job.status == .downloading, job.receivedBytes > 0 || job.expectedBytes != nil else { return nil }
        let received = bytes(job.receivedBytes, locale: locale)
        guard let expected = job.expectedBytes else { return received }
        var parts = [L10n.DownloadQueue.bytesOf(received, bytes(expected, locale: locale))]
        if let seconds = job.estimatedSecondsRemaining {
            parts.append(L10n.DownloadQueue.timeLeft(duration(seconds, locale: locale)))
        }
        return parts.joined(separator: separator)
    }

    static func queueSummary(_ done: String, failed: String?, secondsRemaining: Double?, locale: Locale) -> String {
        [done, failed, timeLeft(secondsRemaining, locale: locale)]
            .compactMap(\.self)
            .joined(separator: separator)
    }

    static func timeLeft(_ seconds: Double?, locale: Locale) -> String? {
        seconds.map { L10n.DownloadQueue.timeLeft(duration($0, locale: locale)) }
    }

    static func bytes(_ count: Int64, locale: Locale) -> String {
        count.formatted(.byteCount(style: .file).locale(locale))
    }

    static func duration(_ seconds: Double, locale: Locale) -> String {
        let rounded = Duration.seconds(max(Int(seconds.rounded(.up)), 1))
        return rounded
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow, maximumUnitCount: 2)
                .locale(locale))
    }
}

enum TransferFailureText {
    static func uploads(_ count: Int) -> String {
        count == 1 ? L10n.Uploads.barFailedOne : L10n.Uploads.barFailedMany(count)
    }

    static func downloads(_ count: Int) -> String {
        count == 1 ? L10n.DownloadQueue.barFailedOne : L10n.DownloadQueue.barFailedMany(count)
    }
}
