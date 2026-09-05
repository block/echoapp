import Combine
import EchoPluginAPI
import Foundation

final class CrashReportingViewModel: ObservableObject {
    @Published var crashReports: [CrashReport] = []

    /// Cap the retained history so a long-lived session (or repeated reconnects that re-send
    /// disk-persisted reports) can't grow the array unbounded, matching the 2000-row cap used by
    /// `AnalyticsDesktopPlugin` and `LoggingDesktopPlugin`.
    private let maxReportCount = 2000

    private var connection: PluginConnection?
    private var cancellable: AnyCancellable?

    // MARK: - Connection

    func connect(connection: PluginConnection) {
        self.connection = connection

        // Install the subscription synchronously so cached reports replayed immediately after
        // `onConnect` (see `SessionViewModel.replayCachedDataToPlugins`) aren't dropped. A single
        // `AnyCancellable` ensures a second `connect` without an intervening `disconnect` cancels
        // the previous sink instead of doubling up inserts.
        cancellable = connection
            .receive(CrashReport.self)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] report in
                self?.insert(report)
            }
    }

    func disconnect() {
        connection = nil
        cancellable = nil
    }

    func clear() {
        crashReports.removeAll()
    }

    // MARK: - Reports

    private func insert(_ report: CrashReport) {
        // The Android client re-sends every persisted crash on each reconnect, so dedupe on the
        // report's stable composite id before inserting.
        guard !crashReports.contains(where: { $0.id == report.id }) else { return }

        crashReports.insert(report, at: 0)
        if crashReports.count > maxReportCount {
            crashReports.removeLast(crashReports.count - maxReportCount)
        }
    }
}
