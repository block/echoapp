import Security
import SwiftUI

struct UpdatesSettingsView: View {
    let appViewModel: AppViewModel

    var body: some View {
        let updateState = appViewModel.updateState

        HStack {
            Spacer()
            Form {
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                if let availableUpdate = updateState.availableUpdate {
                                    Text("Update Available: \(availableUpdate.version)")
                                        .font(.body)
                                } else {
                                    Text("Current Version: \(currentVersion)")
                                        .font(.body)
                                }

                                Text("Last checked: \(lastCheckDate)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                if updateState.isCheckingForUpdates {
                                    Text("Checking for updates...")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                } else if updateState.availableUpdate == nil {
                                    Text("No updates available")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                }
                            }

                            Spacer()

                            if updateState.isCheckingForUpdates {
                                ProgressView()
                                    .scaleEffect(0.8)
                            } else {
                                Button("Update Now") {
                                    appViewModel.performUpdate()
                                }
                                .disabled(updateState.isCheckingForUpdates)
                            }
                        }
                    }
                } header: {
                    Text("EchoApp Updates")
                }
            }
            .frame(maxWidth: 500)
            .formStyle(.grouped)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    }

    private var lastCheckDate: String {
        guard let lastCheck = UserDefaults.standard.object(forKey: "EchoLastUpdateCheck") as? Date else {
            return "Never"
        }

        let formatter = RelativeDateTimeFormatter()
        formatter.dateTimeStyle = .named
        return formatter.localizedString(for: lastCheck, relativeTo: Date())
    }
}
