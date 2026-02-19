import AppKit
import ApplicationServices
import Foundation

/// Automates the KakaoTalk login screen via Accessibility API.
public enum LoginAutomator {

    /// Perform credential-based login on the KakaoTalk login screen.
    public static func login(email: String, password: String) throws {
        let bundleId = AppLifecycle.bundleId
        try AXHelpers.activateApp(bundleId: bundleId)
        let app = try AXHelpers.appElement(bundleId: bundleId)

        let windows = AXHelpers.windows(app)
        guard !windows.isEmpty else {
            throw LifecycleError.loginFailed("No login window found")
        }

        guard let loginWindow = windows.first(where: { AXHelpers.identifier($0) != "Main Window" }) else {
            throw LifecycleError.loginFailed("Could not identify login window")
        }

        fputs("Attempting auto-login...\n", stderr)

        // Switch to email login tab if on QR mode
        if let emailTab = findEmailLoginTab(in: loginWindow) {
            _ = AXHelpers.performAction(emailTab, kAXPressAction as String)
            Thread.sleep(forTimeInterval: 0.5)
        }

        // Find text fields
        let textFields = AXHelpers.findAll(loginWindow, role: "AXTextField")
        let secureFields = AXHelpers.findAll(loginWindow, role: "AXSecureTextField")

        guard let emailField = textFields.first else {
            fputs("DEBUG: Login window tree:\n", stderr)
            fputs(AXHelpers.dumpTree(loginWindow, maxDepth: 5), stderr)
            throw LifecycleError.loginFailed("Could not find email field. The login UI may have changed.")
        }
        guard let passwordField = secureFields.first else {
            fputs("DEBUG: Login window tree:\n", stderr)
            fputs(AXHelpers.dumpTree(loginWindow, maxDepth: 5), stderr)
            throw LifecycleError.loginFailed("Could not find password field. The login UI may have changed.")
        }

        // Fill email
        _ = AXHelpers.focus(emailField)
        Thread.sleep(forTimeInterval: 0.1)
        if !AXHelpers.setValue(emailField, email) {
            AXHelpers.clickElement(emailField)
            Thread.sleep(forTimeInterval: 0.1)
            AXHelpers.selectAll()
            AXHelpers.typeText(email)
        }
        Thread.sleep(forTimeInterval: 0.2)

        // Fill password (secure fields usually need CGEvent)
        AXHelpers.clickElement(passwordField)
        Thread.sleep(forTimeInterval: 0.2)
        _ = AXHelpers.focus(passwordField)
        Thread.sleep(forTimeInterval: 0.1)
        AXHelpers.typeText(password)
        Thread.sleep(forTimeInterval: 0.3)

        // Click login button or press Enter
        if let loginButton = findLoginButton(in: loginWindow) {
            _ = AXHelpers.performAction(loginButton, kAXPressAction as String)
        } else {
            AXHelpers.pressKey(keyCode: 36) // Return
        }

        // Wait for result
        let result = AppLifecycle.waitForAnyState([.loggedIn, .loginScreen], timeout: 15.0, pollInterval: 1.0)

        switch result {
        case .loggedIn:
            fputs("Login successful.\n", stderr)
            return
        case .loginScreen:
            try checkForLoginErrors(app: app)
        default:
            throw LifecycleError.loginFailed("Unexpected state after login attempt: \(result.rawValue)")
        }
    }

    // MARK: - Private Helpers

    private static func findEmailLoginTab(in window: AXUIElement) -> AXUIElement? {
        let candidates = ["카카오계정", "이메일", "email", "계정", "Account"]
        for text in candidates {
            if let el = AXHelpers.findFirst(window, role: "AXButton", text: text) { return el }
            if let el = AXHelpers.findFirst(window, role: "AXCheckBox", text: text) { return el }
            if let el = AXHelpers.findFirst(window, role: "AXStaticText", text: text) { return el }
        }
        return nil
    }

    private static func findLoginButton(in window: AXUIElement) -> AXUIElement? {
        let candidates = ["로그인", "Login", "Log In", "Sign In", "확인"]
        for text in candidates {
            if let button = AXHelpers.findFirst(window, role: "AXButton", text: text) { return button }
        }
        return nil
    }

    private static func checkForLoginErrors(app: AXUIElement) throws {
        let windows = AXHelpers.windows(app)
        for window in windows {
            let allText = AXHelpers.findAll(window, role: "AXStaticText")
            for textElement in allText {
                let text = (AXHelpers.value(textElement) ?? AXHelpers.title(textElement) ?? "").lowercased()
                if text.contains("인증") || text.contains("verification") || text.contains("otp") || text.contains("2fa") {
                    throw LifecycleError.otpRequired
                }
                if (text.contains("비밀번호") && text.contains("틀")) || text.contains("incorrect") || text.contains("wrong") {
                    throw LifecycleError.wrongPassword
                }
                if text.contains("네트워크") || text.contains("network") || text.contains("connection") {
                    throw LifecycleError.networkError
                }
            }
        }
        throw LifecycleError.loginFailed("Login did not succeed. Check your credentials.")
    }
}
