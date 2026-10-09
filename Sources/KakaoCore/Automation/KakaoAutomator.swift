import AppKit
import ApplicationServices
import Foundation

/// Automates KakaoTalk UI for sending messages.
public final class KakaoAutomator {
    public static let bundleId = "com.kakao.KakaoTalkMac"

    public init() {}

    /// Send only to a unique, exact chat name (or the unique self-chat row).
    public func sendMessage(to chatName: String, message: String, selfChat: Bool = false) throws {
        try SendWorkflow(ui: KakaoSendUI()).send(to: chatName, message: message, selfChat: selfChat)
    }
}

private final class KakaoSendUI: SendUI {
    private var app: AXUIElement?

    func prepare() throws {
        let stateBefore = AppLifecycle.detectState()
        try AppLifecycle.ensureReady(credentials: CredentialStore())
        if stateBefore != .loggedIn { wait(2.0) }
        try AXHelpers.activateApp(bundleId: KakaoAutomator.bundleId)
        app = try AXHelpers.appElement(bundleId: KakaoAutomator.bundleId)
    }

    func windows() -> [SendWindow<AXUIElement>] {
        guard let app else { return [] }
        return AXHelpers.windows(app).map {
            SendWindow(element: $0, identifier: AXHelpers.identifier($0),
                       title: AXHelpers.title($0), isWindow: AXHelpers.role($0) == "AXWindow")
        }
    }

    func sameElement(_ lhs: AXUIElement, _ rhs: AXUIElement) -> Bool { CFEqual(lhs, rhs) }
    func closeWindow(_ window: AXUIElement) -> Bool { AXHelpers.closeWindow(window) }
    func wait(_ interval: TimeInterval) { Thread.sleep(forTimeInterval: interval) }

    func chatRows(in mainWindow: AXUIElement) throws -> [SendChatRow<AXUIElement>] {
        guard let tab = AXHelpers.findFirst(mainWindow, role: "AXCheckBox", identifier: "chatrooms"),
              AXHelpers.performAction(tab, kAXPressAction as String) else {
            throw AutomationError.sendFailed("Could not select the Chats tab")
        }
        wait(0.3)
        guard let table = AXHelpers.chatListTable(mainWindow) else {
            throw AutomationError.sendFailed("Could not find the chat list")
        }
        return AXHelpers.children(table).filter { AXHelpers.role($0) == "AXRow" }.map { row in
            let labels = AXHelpers.children(row).filter { AXHelpers.role($0) == "AXCell" }
                .flatMap { AXHelpers.children($0) }
            let names = labels.filter {
                AXHelpers.role($0) == "AXStaticText" && AXHelpers.identifier($0) == "_NS:18"
            }.compactMap { AXHelpers.value($0) }
            let isSelf = labels.contains {
                AXHelpers.role($0) == "AXImage" && (AXHelpers.description($0) ?? "").contains("badge me")
            }
            return SendChatRow(element: row, name: names.count == 1 ? names.first : nil, isSelfChat: isSelf)
        }
    }

    func openChat(_ row: AXUIElement, in mainWindow: AXUIElement) throws {
        guard AXHelpers.performAction(mainWindow, kAXRaiseAction as String),
              let table = AXHelpers.chatListTable(mainWindow) else {
            throw AutomationError.sendFailed("Could not activate the chat list")
        }
        wait(0.3)
        guard isFocusedWindow(mainWindow) else {
            throw AutomationError.sendFailed("The chat list window is not focused")
        }
        if AXHelpers.selectRow(row, in: table) {
            wait(0.2)
            var value: AnyObject?
            guard AXUIElementCopyAttributeValue(table, kAXSelectedRowsAttribute as CFString, &value) == .success,
                  let selected = value as? [AXUIElement], selected.count == 1,
                  let selectedRow = selected.first, sameElement(selectedRow, row),
                  isFocusedWindow(mainWindow) else {
                throw AutomationError.sendFailed("Could not verify the selected chat row")
            }
            try pressReturn()
        } else {
            guard let scrollArea = AXHelpers.chatListScrollArea(mainWindow),
                  AXHelpers.scrollRowToVisible(row, in: scrollArea), isFocusedWindow(mainWindow) else {
                throw AutomationError.sendFailed("Could not safely open the selected chat")
            }
            AXHelpers.doubleClickElement(row)
        }
    }

    func inputField(in window: AXUIElement) -> AXUIElement? {
        let inputs = AXHelpers.children(window).filter { AXHelpers.role($0) == "AXScrollArea" }
            .filter { area in !AXHelpers.children(area).contains { AXHelpers.role($0) == "AXTable" } }
            .flatMap { AXHelpers.children($0) }.filter { AXHelpers.role($0) == "AXTextArea" }
        return inputs.count == 1 ? inputs.first : nil
    }

    func focusInput(_ input: AXUIElement, in window: AXUIElement) throws {
        guard AXHelpers.performAction(window, kAXRaiseAction as String) else {
            throw AutomationError.sendFailed("Could not raise the selected chat window")
        }
        wait(0.3)
        guard AXHelpers.focus(input) else {
            throw AutomationError.sendFailed("Could not focus the verified message input")
        }
        wait(0.1)
    }

    private func focusedElement(_ attribute: String) -> AXUIElement? {
        guard let app else { return nil }
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(app, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private func isFocusedWindow(_ window: AXUIElement) -> Bool {
        guard let app, let focused = focusedElement(kAXFocusedWindowAttribute as String) else { return false }
        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return false }
        return sameElement(focused, window)
    }

    func isFocused(_ input: AXUIElement, in window: AXUIElement) -> Bool {
        guard isFocusedWindow(window), let focused = focusedElement(kAXFocusedUIElementAttribute as String) else {
            return false
        }
        return sameElement(focused, input)
    }

    func setMessage(_ message: String, in input: AXUIElement) -> Bool { AXHelpers.setValue(input, message) }
    func messageValue(in input: AXUIElement) -> String? { AXHelpers.value(input) }

    func pressReturn() throws {
        guard let app else { throw AutomationError.noWindows }
        var pid: pid_t = 0
        guard AXUIElementGetPid(app, &pid) == .success,
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
              let down = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: false) else {
            throw AutomationError.sendFailed("Could not send a key to KakaoTalk")
        }
        down.postToPid(pid)
        up.postToPid(pid)
    }
}

public enum AutomationError: Error, CustomStringConvertible {
    case noWindows
    case chatNotFound(String)
    case ambiguousChat(String)
    case inputFieldNotFound
    case sendFailed(String)

    public var description: String {
        switch self {
        case .noWindows:
            return "KakaoTalk has no uniquely identifiable main window"
        case .chatNotFound(let name):
            return "Chat '\(name)' not found in the chat list (an exact name is required)"
        case .ambiguousChat(let name):
            return "Multiple chats match '\(name)'; refusing to choose a recipient"
        case .inputFieldNotFound:
            return "Could not find a unique message input field"
        case .sendFailed(let msg):
            return "Failed to send message: \(msg)"
        }
    }
}
