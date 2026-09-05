import ArgumentParser
import Foundation

struct ClearCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "clear",
        abstract: "Clear all captured data in the current session."
    )

    func run() throws {
        // During the executable rename, an older connect process may still own
        // echo-cli.pid while a newer clear command is running.
        while let writer = CLIWriterPIDFile.activeWriter(
            in: SessionDirectory.baseURL,
            isEchoCLIProcess: isEchoCLIProcess(pid:)
        ) {
            let result = kill(writer.pid, SIGUSR1)
            if result == 0 {
                print("Session data cleared.")
                return
            }
            // The process exited between validation and signaling. Remove its
            // stale file and continue so the legacy filename is still checked.
            try? FileManager.default.removeItem(at: writer.url)
        }

        try clearFilesDirectly()
    }

    private func clearFilesDirectly() throws {
        // No running connect process -- clear files directly
        guard let sessionURL = SessionDirectory.currentSessionURL() else {
            print("No active session to clear.")
            return
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: sessionURL,
            includingPropertiesForKeys: nil
        )
        var cleared = 0
        for file in contents where file.pathExtension == "jsonl" {
            do {
                try FileManager.default.removeItem(at: file)
                cleared += 1
            } catch {
                FileHandle.standardError.write("Warning: failed to clear \(file.lastPathComponent): \(error)\n".data(using: .utf8)!)
            }
        }
        print("Cleared \(cleared) data files.")
    }

    private func isEchoCLIProcess(pid: Int32) -> Bool {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        let result = sysctl(&mib, UInt32(mib.count), &info, &size, nil, 0)
        guard result == 0, size > 0 else { return false }
        let name = withUnsafePointer(to: info.kp_proc.p_comm) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN)) {
                String(cString: $0)
            }
        }
        // Internal builds still ship the executable as "echo-cli" until the
        // distribution pipeline moves to the new name.
        return name == "echoapp" || name == "echo-cli"
    }
}

enum CLIWriterPIDFile {
    private static let filenames = ["echoapp.pid", "echo-cli.pid"]

    static func activeWriter(
        in baseURL: URL,
        isEchoCLIProcess: (Int32) -> Bool
    ) -> (pid: Int32, url: URL)? {
        for filename in filenames {
            let url = baseURL.appendingPathComponent(filename)
            guard let pidString = try? String(contentsOf: url, encoding: .utf8),
                  let pid = Int32(pidString.trimmingCharacters(in: .whitespacesAndNewlines)),
                  isEchoCLIProcess(pid) else {
                // Malformed, stale, or unrelated PID files must not prevent the
                // transition fallback from checking the next filename.
                try? FileManager.default.removeItem(at: url)
                continue
            }
            return (pid, url)
        }
        return nil
    }
}
