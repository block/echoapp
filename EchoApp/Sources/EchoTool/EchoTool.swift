import ArgumentParser

@main
struct EchoTool: ParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "EchoTool",
        subcommands: [
            BuildPluginCommand.self,
            EditPluginCommand.self,
        ]
    )

}
