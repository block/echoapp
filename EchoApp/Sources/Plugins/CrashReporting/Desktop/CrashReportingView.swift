import EchoPluginUI
import SwiftUI

struct CrashReportingView: View {
    @StateObject private var viewModel: CrashReportingViewModel

    init(viewModel: CrashReportingViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        if viewModel.crashReports.isEmpty {
            EchoNullStateView(
                iconName: "exclamationmark.triangle",
                message: "No crash reports yet. Crash reports from the connected app will appear here."
            )
        } else {
            VStack(spacing: 0) {
                toolbar
                Divider()
                crashList
            }
        }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            Text("\(viewModel.crashReports.count) crash report\(viewModel.crashReports.count == 1 ? "" : "s")")
                .font(.callout)
                .foregroundColor(.secondary)
            Spacer()
            Button("Clear") {
                viewModel.clear()
            }
            .buttonStyle(.bordered)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    // MARK: - List

    private var crashList: some View {
        List(viewModel.crashReports) { report in
            CrashReportRow(report: report)
        }
        .listStyle(.plain)
    }
}

// MARK: - Crash Report Row

private struct CrashReportRow: View {
    let report: CrashReport

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                stackTraceSection(title: "Stack Trace", trace: report.stackTrace)

                if let causeChain = report.causeChain, !causeChain.isEmpty {
                    ForEach(Array(causeChain.enumerated()), id: \.offset) { index, cause in
                        let title = "Caused by (\(index + 1)): \(cause.title)"
                        // The client may omit per-cause frames (they're already in the top-level
                        // stack trace), so only show the trace block when one was sent.
                        if let trace = cause.stackTrace, !trace.isEmpty {
                            stackTraceSection(title: title, trace: trace)
                        } else {
                            Text(title)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)

                    Text(report.title)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(2)
                }

                HStack(spacing: 12) {
                    Label(report.formattedTimestamp, systemImage: "clock")
                    Label("\(report.threadName) (\(report.threadId))", systemImage: "cpu")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
        }
    }

    private func stackTraceSection(title: String, trace: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
                .fontWeight(.semibold)

            Text(trace)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
                .background(Color(.textBackgroundColor))
                .cornerRadius(6)
        }
    }
}
