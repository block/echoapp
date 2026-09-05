import EchoPluginUI
import SwiftUI

public struct DebugPayloadView: View {
    let appViewModel: AppViewModel
    @State private var searchText: String = ""

    public var body: some View {
        VStack(spacing: 0) {
            HSplitView {
                PayloadListView(appViewModel: appViewModel)
                    .frame(minWidth: 300)
                PayloadDetailView(appViewModel: appViewModel)
                    .frame(minWidth: 400)
            }

            Divider()

            HStack(alignment: .center) {
                Button {
                    appViewModel.setDebuggerPaused(!appViewModel.debuggerState.isPaused)
                } label: {
                    Image(systemName: appViewModel.debuggerState.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14))
                }
                .help(appViewModel.debuggerState.isPaused ? "Resume recording messages" : "Pause recording messages")
                .buttonStyle(HoverButtonStyle(textColor: .secondaryLabel))

                if appViewModel.debuggerState.isPaused {
                    Text("PAUSED")
                        .padding(.horizontal, 4)
                        .padding(.vertical, 4)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color.white)
                        .background(Color.red)
                        .cornerRadius(4.0)
                }

                Text(
                    "\(appViewModel.debuggerState.filteredPayloads.count) payload\(appViewModel.debuggerState.filteredPayloads.count == 1 ? "" : "s")"
                )
                .lineLimit(1)
                .truncationMode(.tail)

                Spacer()

                HStack {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundColor(Color.tertiaryLabel)

                    Menu {
                        Button("All") {
                            appViewModel.setPluginFilter(nil)
                        }
                        ForEach(appViewModel.debuggerState.availablePluginIds, id: \.self) { pluginID in
                            Button(pluginID) {
                                appViewModel.setPluginFilter(pluginID)
                            }
                        }
                    } label: {
                        Text(appViewModel.debuggerState.selectedPluginFilter ?? "All")
                    }
                    .frame(maxWidth: 200)
                    .tint(Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help("Select a filter for Plugin")

                    if appViewModel.debuggerState.selectedPluginFilter != nil {
                        Button {
                            appViewModel.setPluginFilter(nil)
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    MessageLimitField(appViewModel: appViewModel)

                    Button {
                        appViewModel.clearDebuggerPayloads()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 14))
                    }
                    .help("Clear all")
                    .buttonStyle(HoverButtonStyle(textColor: .secondaryLabel))
                }
            }
            .padding(8)
        }
        .searchable(
            text: $searchText,
            prompt: "Search messages..."
        )
        .onChange(of: searchText) { _, newValue in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if searchText == newValue {
                    appViewModel.setDebuggerSearchText(newValue)
                }
            }
        }
        .onAppear {
            searchText = appViewModel.debuggerState.searchText
            appViewModel.setDebuggerEnabled(true)
        }
        .onDisappear {
            appViewModel.setDebuggerEnabled(false)
        }
    }
}

// MARK: - PayloadListView

private struct PayloadListView: View {
    let appViewModel: AppViewModel

    var timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            List(appViewModel.debuggerState.filteredPayloads, id: \.id) { payload in
                PayloadRowView(
                    payload: payload,
                    timestampFormatter: timestampFormatter,
                    isSelected: appViewModel.debuggerState.selectedPayloadId == payload.id
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    appViewModel.selectPayload(payload.id)
                }
            }
            .listStyle(.plain)
        }
    }
}

// MARK: - PayloadRowView

private struct PayloadRowView: View {
    let payload: DebugPayload
    let timestampFormatter: DateFormatter
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(payload.pluginID)
                    .font(.caption)
                    .foregroundColor(.blue)
                    .fontWeight(.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer()
                Text(timestampFormatter.string(from: payload.time))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            HStack {
                Text(payload.prefixData)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("\(payload.prettyData.count)\nchars")
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
        .cornerRadius(4)
        .contentShape(Rectangle())
    }
}

// MARK: - PayloadDetailView

private struct PayloadDetailView: View {
    let appViewModel: AppViewModel

    var timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if let selectedPayload = appViewModel.debuggerState.selectedPayload {
                    Text(selectedPayload.pluginID)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .fontWeight(.medium)

                    Spacer()

                    Text(timestampFormatter.string(from: selectedPayload.time))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.top, 8)
            .padding(.horizontal, 16)

            if let selectedPayload = appViewModel.debuggerState.selectedPayload {
                ScrollView([.vertical]) {
                    HighlightedSyntaxView(code: selectedPayload.prettyData, language: "json")
                        .frame(maxWidth: .infinity)
                }
                .padding(8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack {
                    Spacer()
                    Text("Select a message to view details")
                        .font(.title3)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - MessageLimitField

private struct MessageLimitField: View {
    let appViewModel: AppViewModel
    @State private var textValue: String = ""

    var body: some View {
        HStack(spacing: 4) {
            Text("Limit:")
                .font(.system(size: 13.0, weight: .medium))
                .foregroundColor(.secondary)

            TextField("500", text: $textValue)
                .textFieldStyle(.roundedBorder)
                .frame(width: 50)
                .onSubmit {
                    if let intValue = Int(textValue), intValue > 0 {
                        appViewModel.setMessageLimit(intValue)
                    } else {
                        textValue = "\(appViewModel.debuggerState.messageLimit)"
                    }
                }
                .onAppear {
                    textValue = "\(appViewModel.debuggerState.messageLimit)"
                }
                .onChange(of: appViewModel.debuggerState.messageLimit) { _, newValue in
                    textValue = "\(newValue)"
                }
        }
    }
}
