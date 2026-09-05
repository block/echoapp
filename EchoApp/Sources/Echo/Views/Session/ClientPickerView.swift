import EchoConnection
import Network
import SwiftUI

/// A macOS-style client device picker matching system settings design
struct ClientPickerView: View {
    let sessionViewModel: SessionViewModel
    let appViewModel: AppViewModel
    let port: Int

    @Environment(\.openWindow) var openWindow
    @State private var showingPortInfo = false

    private var cliExecutableName: String {
        #if ECHOAPP_PUBLIC_DISTRIBUTION
        "echoapp"
        #else
        "echo-cli"
        #endif
    }

    var body: some View {
        HSplitView {
            statusScreen()
                .frame(minWidth: 300, maxWidth: .infinity)
            availableDevicesSection()
                .frame(minWidth: 200, maxWidth: 400)
        }
    }

    // MARK: - Status Screen

    @ViewBuilder
    private func statusScreen() -> some View {
        VStack(spacing: 32) {
            Spacer()

            if let connectedClient = sessionViewModel.connectedClient {
                connectedDeviceView(client: connectedClient)
            } else {
                emptyDevicePlaceholder()
            }

            HStack(spacing: 8) {
                Button(action: {
                    showingPortInfo = true
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "network.badge.shield.half.filled")
                            .font(.caption)
                        Text("Port \(String(port))")
                            .font(.callout)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showingPortInfo, arrowEdge: .bottom) {
                    portInfoPopover()
                }

                if sessionViewModel.connectedClient != nil {
                    Button(action: {
                        sessionViewModel.disconnectClient()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                            Text("Disconnect")
                                .font(.callout)
                                .fontWeight(.medium)
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.red)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()
        }
        .padding(40)
    }

    // MARK: - Available Devices Section

    @ViewBuilder
    private func availableDevicesSection() -> some View {
        List {
            Section {
                let filteredBonjourClients = filteredAvailableBonjourClients(
                    sessionViewModel.availableBonjourClients,
                    connectedClient: sessionViewModel.connectedClient
                )

                if filteredBonjourClients.isEmpty {
                    EmptyStateView(
                        icon: "magnifyingglass",
                        title: "Searching for devices...",
                        subtitle: "Make sure your device is on the same network",
                        action: {
                            sessionViewModel.refreshBonjourDevices()
                        }
                    )
                } else {
                    ForEach(filteredBonjourClients, id: \.name) { service in
                        bonjourDeviceRow(service: service)
                    }
                }
            } header: {
                HStack {
                    Text("Bonjour Devices")
                    Spacer()
                }
                .padding(.bottom, 8)
            }

            Section {
                if let adbError = sessionViewModel.adbError {
                    ErrorStateView(
                        title: "ADB Error",
                        message: adbError.completeErrorDescription
                    )
                    .listRowBackground(Color.clear)
                } else {
                    let filteredADBClients = filteredAvailableADBClients(
                        sessionViewModel.availableADBClients,
                        connectedClient: sessionViewModel.connectedClient
                    )

                    if filteredADBClients.isEmpty {
                        EmptyStateView(
                            icon: "ladybug",
                            title: "Connect an Android device via USB or WiFi",
                            subtitle: "Relaunch the app if necessary",
                            action: {
                                sessionViewModel.refreshADBDevices()
                            }
                        )
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(filteredADBClients, id: \.androidIdOrName) { device in
                            adbDeviceRow(device: device)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("ADB Devices")
                    Spacer()
                }
                .padding(.bottom, 8)
            }

            Section {
                if appViewModel.activeCLISessions.isEmpty {
                    EmptyStateView(
                        icon: "terminal",
                        title: "No active CLI sessions",
                        subtitle: "Run \(cliExecutableName) connect to start one"
                    )
                } else {
                    ForEach(appViewModel.activeCLISessions) { session in
                        cliSessionRow(session: session)
                    }
                }
            } header: {
                HStack {
                    Text("CLI Sessions")
                    Text(cliExecutableName)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.15))
                        .cornerRadius(4)
                    Spacer()
                }
                .padding(.bottom, 8)
            }
        }
        .listStyle(.sidebar)
    }

    // MARK: - Device Rows

    @ViewBuilder
    private func bonjourDeviceRow(service: BonjourService) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "bonjour")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(service.displayName ?? service.name)
                    .font(.body)

                Text(endpointDescription(for: service.endpoint))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                handleDeviceSelection(.bonjour(service))
            }) {
                Text("Connect")
                    .font(.callout)
            }
            .buttonStyle(.borderedProminent)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func adbDeviceRow(device: ADB.Device) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "ladybug")
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.model ?? device.name)
                    .font(.body)

                Text("\(device.deviceType) (\(device.name))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: {
                handleDeviceSelection(.adb(device))
            }) {
                Text("Connect")
                    .font(.callout)
            }
            .buttonStyle(.borderedProminent)
        }
        .contentShape(Rectangle())
    }

    // MARK: - CLI Session Row

    @ViewBuilder
    private func cliSessionRow(session: CLISession) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "terminal")
                .font(.title2)
                .foregroundColor(.green)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.deviceName)
                    .font(.body)

                HStack(spacing: 4) {
                    Text(session.deviceType)
                        .font(.caption)
                        .foregroundColor(.secondary)

                    if !session.plugins.isEmpty {
                        Text("- \(session.plugins.count) plugins")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Button(action: {
                NSWorkspace.shared.selectFile(
                    nil,
                    inFileViewerRootedAtPath: session.sessionPath
                )
            }) {
                Text("Reveal")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .help("Reveal session directory in Finder")

            Button(action: {
                let sessionId = appViewModel.openCLISession(session)
                openWindow(value: SessionWindow(id: sessionId))
            }) {
                Text("Open")
                    .font(.callout)
            }
            .buttonStyle(.borderedProminent)
        }
        .contentShape(Rectangle())
    }

    // MARK: - Empty / Connected Placeholders

    @ViewBuilder
    private func emptyDevicePlaceholder() -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 20) {
                Image(systemName: "apps.iphone")
                    .font(.system(size: 60))
                    .foregroundColor(.secondary.opacity(0.5))
                    .symbolRenderingMode(.hierarchical)

                VStack(spacing: 8) {
                    Text("Connect to a Device")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    Text("Select a device from the list →")
                        .font(.subheadline)
                        .foregroundColor(.secondary.opacity(0.8))
                }
            }
            .frame(maxWidth: 320, minHeight: 260)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(style: StrokeStyle(lineWidth: 2, dash: [8, 8]))
                    .foregroundColor(Color.secondary.opacity(0.3))
            )
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .onTapGesture {
                sessionViewModel.refreshAvailableClients()
            }
            .help("Refresh device lists")
        }
    }

    @ViewBuilder
    private func connectedDeviceView(client: ConnectedClient) -> some View {
        VStack(spacing: 16) {
            VStack(spacing: 20) {
                ZStack {
                    Image(systemName: "apps.iphone")
                        .font(.system(size: 60))
                        .foregroundColor(.accentColor)
                        .symbolRenderingMode(.hierarchical)

                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.green)
                        .background(Circle().fill(Color(nsColor: .windowBackgroundColor)).padding(-2))
                        .offset(x: 25, y: -25)
                }

                VStack(spacing: 12) {
                    Text(client.deviceName ?? client.deviceIdentifier.value)
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(client.appIdentifier)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if let clientInfo = client.clientInfo {
                        HStack(spacing: 4) {
                            Image(systemName: "puzzlepiece.fill")
                                .font(.caption)
                            Text("\(clientInfo.clientPluginIDs.count) plugins")
                                .font(.caption)
                        }
                        .foregroundColor(.secondary)
                    }
                }
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: 320, minHeight: 260)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.3), lineWidth: 1.5)
        )
    }

    // MARK: - Helper Methods

    private func filteredAvailableBonjourClients(
        _ clients: [BonjourService],
        connectedClient: ConnectedClient?
    ) -> [BonjourService] {
        guard let connectedDeviceId = connectedClient?.deviceIdentifier.value else {
            return clients
        }
        return clients.filter { $0.name != connectedDeviceId }
    }

    private func filteredAvailableADBClients(
        _ clients: [ADB.Device],
        connectedClient: ConnectedClient?
    ) -> [ADB.Device] {
        guard let connectedDeviceId = connectedClient?.deviceIdentifier.value else {
            return clients
        }
        return clients.filter { device in
            if let androidId = device.androidId {
                return androidId != connectedDeviceId
            } else {
                return device.name != connectedDeviceId
            }
        }
    }

    private func handleDeviceSelection(_ client: DiscoveredClient) {
        if sessionViewModel.connectedClient != nil {
            let sessionId = UUID()
            _ = appViewModel.createSession(initialClient: client, sessionID: sessionId)
            openWindow(value: SessionWindow(id: sessionId))
        } else {
            sessionViewModel.selectClient(client)
        }
    }

    private func endpointDescription(for endpoint: NWEndpoint) -> String {
        switch endpoint {
        case .hostPort(let host, let port):
            return "\(host):\(port)"
        case .service(_, let type, let domain, _):
            if !domain.isEmpty {
                return "\(type).\(domain)"
            }
            return type
        case .unix:
            return "Unix socket"
        case .url(let url):
            return url.host ?? "Network service"
        case .opaque:
            return "Network service"
        @unknown default:
            return "Network service"
        }
    }

    // MARK: - Port Info Popover

    private var serverAddress: String {
        let ip = getPreferredIPAddress() ?? "127.0.0.1"
        return "ws://\(ip):\(port)/channel"
    }

    @ViewBuilder
    private func portInfoPopover() -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentColor)

                Text("Session Port")
                    .font(.headline)
                    .fontWeight(.semibold)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("This EchoApp session is running on port \(String(port)).")
                    .font(.body)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Server Address")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 8) {
                        Text(serverAddress)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(6)

                        Button(action: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(serverAddress, forType: .string)
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.callout)
                        }
                        .buttonStyle(.bordered)
                        .help("Copy server address")
                    }
                }

                Text("If your device isn't appearing in the device list, you can connect manually by entering this address in your client app's debug menu. Each session uses a unique port, allowing you to run multiple EchoApp instances simultaneously.")
                    .font(.body)
                    .foregroundColor(.secondary)

                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("To create additional EchoApp sessions, use:")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 4) {
                        Text("File → New Session")
                            .font(.caption)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)

                        Text("or")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text("⌘N")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(nsColor: .controlBackgroundColor))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 350)
    }
}

// MARK: - Supporting Views

struct EmptyStateView: View {
    let icon: String
    let title: String
    let subtitle: String
    var action: (() -> Void)?
    @State private var isHovering = false

    var body: some View {
        if let action {
            Button(action: action) {
                content
            }
            .buttonStyle(EmptyStateButtonStyle(isHovering: isHovering))
            .contentShape(Rectangle())
            .onHover { isHovering = $0 }
            .help("Refresh")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.secondary.opacity(0.5))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.secondary)

                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if action != nil {
                Image(systemName: "arrow.clockwise")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .opacity(isHovering ? 1 : 0)
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct EmptyStateButtonStyle: ButtonStyle {
    let isHovering: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(backgroundColor(isPressed: configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(borderColor(isPressed: configuration.isPressed), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: isHovering)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(0.16)
        }
        if isHovering {
            return Color.primary.opacity(0.08)
        }
        return Color.clear
    }

    private func borderColor(isPressed: Bool) -> Color {
        if isPressed {
            return Color.accentColor.opacity(0.25)
        }
        if isHovering {
            return Color.primary.opacity(0.08)
        }
        return Color.clear
    }
}

struct ErrorStateView: View {
    let title: String
    let message: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.title2)
                .foregroundColor(.orange.opacity(0.7))
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                    .foregroundColor(.secondary)

                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, 8)
    }
}

// MARK: - View Extensions

extension View {
    func hoverEffect(_ effect: @escaping (Bool) -> some View) -> some View {
        modifier(HoverEffectModifier(effect: effect))
    }
}

struct HoverEffectModifier<EffectView: View>: ViewModifier {
    let effect: (Bool) -> EffectView
    @State private var isHovering = false

    func body(content: Content) -> some View {
        content
            .background(effect(isHovering))
            .onHover { hovering in
                isHovering = hovering
            }
    }
}
