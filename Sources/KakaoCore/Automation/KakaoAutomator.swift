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
    public func sendMessage(to chatName: String, message: String) throws {
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

        // 3. Ensure we're on the Chats tab
        if let chatroomsTab = AXHelpers.findFirst(mainWindow, role: "AXCheckBox", identifier: "chatrooms") {
            _ = AXHelpers.performAction(chatroomsTab, kAXPressAction as String)
            Thread.sleep(forTimeInterval: 0.3)
        }

        // 4. Find the chat row in the list
        guard let table = AXHelpers.chatListTable(mainWindow) else {
            throw AutomationError.chatNotFound(chatName)
        }
        guard let row = AXHelpers.findChatRow(table, chatName: chatName) else {
            throw AutomationError.chatNotFound(chatName)
        }

        // 5. Double-click the row to open the chat window
        AXHelpers.doubleClickElement(row)
        Thread.sleep(forTimeInterval: 1.0)

        // 6. Find the chat window (any window that is NOT the main window)
        let updatedWindows = AXHelpers.windows(app)
        guard let chatWindow = updatedWindows.first(where: { AXHelpers.identifier($0) != "Main Window" }) else {
            throw AutomationError.inputFieldNotFound
        }

        // 7. Find the message input: it's an AXTextArea inside a top-level AXScrollArea
        //    (NOT the message list scroll area which contains a table).
        //    Structure: AXWindow > AXScrollArea(input) > AXTextArea
        let input = findInputField(in: chatWindow)

        guard let inputField = input else {
            print("DEBUG: Chat window UI tree:")
            print(AXHelpers.dumpTree(chatWindow, maxDepth: 4))
            throw AutomationError.inputFieldNotFound
        }

        // 8. Focus and type the message
        _ = AXHelpers.focus(inputField)
        Thread.sleep(forTimeInterval: 0.2)

        // Type using CGEvent for reliability (handles Unicode)
        typeText(message)
        Thread.sleep(forTimeInterval: 0.2)

        // 9. Press Enter to send
        pressKey(keyCode: 36) // Return key
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

    /// Type text using CGEvent (handles Unicode correctly).
    private func typeText(_ text: String) {
        for char in text {
            let utf16 = Array(char.utf16)
            if let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
               let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) {
                down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                up.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                down.post(tap: .cghidEventTap)
                up.post(tap: .cghidEventTap)
                usleep(5000) // 5ms between keystrokes
            }
        }
    }

    /// Press a key using CGEvent.
    private func pressKey(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        if let down = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
           let up = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) {
            down.flags = flags
            up.flags = flags
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
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
