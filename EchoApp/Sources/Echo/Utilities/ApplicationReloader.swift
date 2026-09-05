import AppKit
import Foundation

/// A utility which handles reloading the application.
/// It spawns a background process which opens the application after some delay
/// and then immediately quits the current instance.
struct ApplicationReloader {
    /// The delay before the application is reloaded.
    let reloadDelay: TimeInterval = 2

    /// Reloads the application.
    func reload() {
        let appPath = Bundle.main.bundlePath

        // Command to quit the app and relaunch it using nohup
        let command = """
        nohup sh -c '
        sleep \(reloadDelay)
        open "\(appPath)"
        ' &
        """

        // Create a task to run the command
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", command]

        // Run the command
        task.launch()

        // Terminate the current app
        NSApplication.shared.terminate(nil)
    }
}
