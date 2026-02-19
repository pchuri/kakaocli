import ArgumentParser

@main
struct KakaoCLI: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "kakaocli",
        abstract: "KakaoTalk CLI for AI agents",
        version: "0.1.0",
        subcommands: [
            AuthCommand.self,
            ChatsCommand.self,
            MessagesCommand.self,
            SearchCommand.self,
            SchemaCommand.self,
            StatusCommand.self,
            InspectCommand.self,
            SendCommand.self,
        ]
    )
}
