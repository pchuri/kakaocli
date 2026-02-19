import ArgumentParser
import Foundation
import KakaoCore

struct SendCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Send a message via UI automation"
    )

    @Argument(help: "Chat name to send to (substring match)")
    var chat: String

    @Argument(help: "Message text to send")
    var message: String

    @Flag(name: .long, help: "Show what would happen without actually sending")
    var dryRun = false

    func run() throws {
        let automator = KakaoAutomator()
        if dryRun {
            print("DRY RUN: Would send to '\(chat)': \(message)")
            print("Steps: activate KakaoTalk → find chat '\(chat)' → type message → press Enter")
            return
        }
        try automator.sendMessage(to: chat, message: message)
        print("Message sent to '\(chat)'.")
    }
}
