import EchoPluginUI
import SwiftUI

struct NavigationView: View {
    @StateObject var viewModel: NavigationViewModel

    var body: some View {
        if let snapshot = viewModel.currentSnapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    currentScreenCard(snapshot.currentScreen)

                    if !snapshot.backstack.isEmpty {
                        backstackSection(snapshot.backstack)
                    }

                    metadataSection(snapshot)
                }
                .padding()
            }
        } else {
            EchoNullStateView(
                iconName: "arrow.triangle.turn.up.right.diamond",
                message: "Connect a mobile app with navigation tracking to visualize the navigation stack."
            )
        }
    }

    // MARK: - Current Screen Card

    @ViewBuilder
    private func currentScreenCard(_ screen: NavigationScreen) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.accentColor)
                    .font(.caption)
                Text("Current Screen")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(screen.title)
                    .font(.title2)
                    .fontWeight(.semibold)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.turn.up.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(screen.route)
                        .font(.callout)
                        .foregroundColor(.secondary)
                }

                if let className = screen.className {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(className)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fontDesign(.monospaced)
                    }
                }

                if let parameters = screen.parameters, !parameters.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Parameters")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)

                        ForEach(Array(parameters.keys.sorted()), id: \.self) { key in
                            if let value = parameters[key] {
                                HStack(spacing: 4) {
                                    Text(key)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .fontDesign(.monospaced)
                                    Text(":")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(value)
                                        .font(.caption)
                                        .fontDesign(.monospaced)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.1))
        .cornerRadius(8)
    }

    // MARK: - Backstack Section

    @ViewBuilder
    private func backstackSection(_ backstack: [NavigationScreen]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "arrow.left")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("Back Stack")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
                Spacer()
                Text("\(backstack.count) screen\(backstack.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(backstack.enumerated()), id: \.element.id) { index, screen in
                    backstackRow(screen: screen, index: backstack.count - index)

                    if index < backstack.count - 1 {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func backstackRow(screen: NavigationScreen, index: Int) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(index)")
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
                .frame(width: 24, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                Text(screen.title)
                    .font(.body)
                    .fontWeight(.medium)

                Text(screen.route)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let className = screen.className {
                    Text(className)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontDesign(.monospaced)
                }
            }

            Spacer()
        }
    }

    // MARK: - Metadata Section

    @ViewBuilder
    private func metadataSection(_ snapshot: NavigationSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                    .font(.caption)
                Text("Metadata")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)
            }

            VStack(alignment: .leading, spacing: 8) {
                if let navigationType = snapshot.navigationType {
                    metadataRow(label: "Navigation Type", value: navigationType)
                }

                metadataRow(
                    label: "Timestamp",
                    value: formatDate(snapshot.timestamp)
                )

                metadataRow(
                    label: "Total Screens",
                    value: "\(snapshot.totalScreens)"
                )
            }
            .padding()
            .background(Color(.controlBackgroundColor))
            .cornerRadius(8)
        }
    }

    @ViewBuilder
    private func metadataRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontDesign(.monospaced)
        }
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
