import ArgumentParser
import Foundation

extension URL: @retroactive ExpressibleByArgument {

    public init(argument: String) {
        let resolvedPath = (argument as NSString).expandingTildeInPath

        if resolvedPath.first == "/" {
            self.init(filePath: resolvedPath)
        } else {
            self.init(
                filePath: argument,
                relativeTo: URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
            )
        }
    }

}
