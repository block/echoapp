import Combine
import EchoPluginAPI
import Foundation

final class NavigationViewModel: ObservableObject {
    @Published var currentSnapshot: NavigationSnapshot?

    private let connection: CurrentValueSubject<PluginConnection?, Never>
    private var cancellables = Set<AnyCancellable>()

    init(connection: CurrentValueSubject<PluginConnection?, Never>) {
        self.connection = connection
    }

    func connect(connection: PluginConnection) {
        self.connection.send(connection)

        connection.receive(NavigationSnapshot.self)
            .sink { [weak self] snapshot in
                self?.currentSnapshot = snapshot
            }
            .store(in: &cancellables)
    }

    func disconnect() {
        connection.send(nil)
        cancellables.removeAll()
        currentSnapshot = nil
    }
}
