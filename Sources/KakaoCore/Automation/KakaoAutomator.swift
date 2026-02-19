import AppKit
import ApplicationServices
import Foundation

/// Automates KakaoTalk UI for sending messages.
public final class KakaoAutomator {
    public static let bundleId = "com.kakao.KakaoTalkMac"

    public init() {}

    /// Send a message to a chat by navigating the UI.
    ///
    /// Steps:
    /// 1. Activate KakaoTalk
    /// 2. Find the chat in the list and double-click to open
    /// 3. Find the message input area in the chat window
    /// 4. Type the message and press Enter
    public func sendMessage(to chatName: String, message: String, selfChat: Bool = false) throws {
        // 0. Ensure KakaoTalk is running and logged in
        try AppLifecycle.ensureReady(credentials: CredentialStore())

        // 1. Activate KakaoTalk
        try AXHelpers.activateApp(bundleId: Self.bundleId)
        let app = try AXHelpers.appElement(bundleId: Self.bundleId)

        let windows = AXHelpers.windows(app)
        guard !windows.isEmpty else {
            throw AutomationError.noWindows
        }

        // 2. Find the main window (id="Main Window")
        guard let mainWindow = windows.first(where: { AXHelpers.identifier($0) == "Main Window" }) else {
            throw AutomationError.noWindows
        }

        // 3. Close any existing chat windows to avoid sending to the wrong one
        for w in windows where AXHelpers.identifier(w) != "Main Window" {
            _ = AXHelpers.closeWindow(w)
        }
        if windows.count > 1 {
            Thread.sleep(forTimeInterval: 0.3)
        }

        // 4. Ensure we're on the Chats tab
        if let chatroomsTab = AXHelpers.findFirst(mainWindow, role: "AXCheckBox", identifier: "chatrooms") {
            _ = AXHelpers.performAction(chatroomsTab, kAXPressAction as String)
            Thread.sleep(forTimeInterval: 0.3)
        }

        // 4. Find the chat row in the list
        guard let table = AXHelpers.chatListTable(mainWindow) else {
            throw AutomationError.chatNotFound(chatName)
        }

        let row: AXUIElement
        if selfChat {
            guard let selfRow = AXHelpers.findSelfChatRow(table) else {
                throw AutomationError.chatNotFound("self-chat (나와의 채팅)")
            }
            row = selfRow
        } else {
            guard let chatRow = AXHelpers.findChatRow(table, chatName: chatName) else {
                throw AutomationError.chatNotFound(chatName)
            }
            row = chatRow
        }

        // 6. Double-click the row to open the chat window
        AXHelpers.doubleClickElement(row)
        Thread.sleep(forTimeInterval: 1.0)

        // 7. Find the newly opened chat window (only non-main window after closing others)
        let updatedWindows = AXHelpers.windows(app)
        let chatWindow = updatedWindows.first(where: { AXHelpers.identifier($0) != "Main Window" })

        guard let chatWindow else {
            throw AutomationError.inputFieldNotFound
        }

        // 8. Find the message input: AXTextArea inside a top-level AXScrollArea (no AXTable)
        guard let inputField = findInputField(in: chatWindow) else {
            print("DEBUG: Chat window UI tree:")
            print(AXHelpers.dumpTree(chatWindow, maxDepth: 4))
            throw AutomationError.inputFieldNotFound
        }

        // 9. Raise the chat window to make it the key window
        _ = AXHelpers.performAction(chatWindow, kAXRaiseAction as String)
        Thread.sleep(forTimeInterval: 0.3)

        // 10. Click the input field to ensure it's focused
        AXHelpers.clickElement(inputField)
        Thread.sleep(forTimeInterval: 0.3)

        // 11. Use AXValue to set text directly, then press Enter
        //     This is more reliable than CGEvent keystrokes which go to the frontmost window
        if AXHelpers.setValue(inputField, message) {
            Thread.sleep(forTimeInterval: 0.2)
            AXHelpers.pressKey(keyCode: 36) // Return key
        } else {
            // Fallback: type using CGEvent
            _ = AXHelpers.focus(inputField)
            Thread.sleep(forTimeInterval: 0.1)
            AXHelpers.typeText(message)
            Thread.sleep(forTimeInterval: 0.2)
            AXHelpers.pressKey(keyCode: 36) // Return key
        }

        // 12. Close the chat window so it doesn't linger
        Thread.sleep(forTimeInterval: 0.3)
        _ = AXHelpers.closeWindow(chatWindow)
    }

    /// Find the message input AXTextArea in a chat window.
    /// The input is in a top-level AXScrollArea that does NOT contain an AXTable (messages).
    private func findInputField(in window: AXUIElement) -> AXUIElement? {
        for child in AXHelpers.children(window) {
            guard AXHelpers.role(child) == "AXScrollArea" else { continue }
            // The message list scroll area contains an AXTable; the input one doesn't
            let hasTable = AXHelpers.children(child).contains { AXHelpers.role($0) == "AXTable" }
            if !hasTable {
                // This scroll area should contain the input AXTextArea
                for subchild in AXHelpers.children(child) {
                    if AXHelpers.role(subchild) == "AXTextArea" {
                        return subchild
                    }
                }
            }
        }
        return nil
    }

}

public enum AutomationError: Error, CustomStringConvertible {
    case noWindows
    case chatNotFound(String)
    case inputFieldNotFound
    case sendFailed(String)

    public var description: String {
        switch self {
        case .noWindows:
            return "KakaoTalk has no open windows"
        case .chatNotFound(let name):
            return "Chat '\(name)' not found in the chat list"
        case .inputFieldNotFound:
            return "Could not find the message input field"
        case .sendFailed(let msg):
            return "Failed to send message: \(msg)"
        }
    }
}
