import AppKit
import ApplicationServices
import Foundation

/// Represents the observed state of KakaoTalk.
public enum KakaoAppState: String, Sendable {
    case notRunning
    case launching
    case loginScreen
    case loggedIn
    case updateRequired
    case unknown
}

/// Manages KakaoTalk.app lifecycle: launch, state detection, readiness.
public enum AppLifecycle {

    public static let bundleId = KakaoAutomator.bundleId
    public static let appPath = "/Applications/KakaoTalk.app"

    // MARK: - State Detection

    public static func isRunning() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).isEmpty
    }

    public static func detectState() -> KakaoAppState {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId).first else {
            return .notRunning
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windows = AXHelpers.windows(axApp)

        if windows.isEmpty {
            // KakaoTalk hides its window when "closed" (still running in menu bar).
            // Activate it to make windows visible, then re-check.
            app.activate()
            Thread.sleep(forTimeInterval: 0.5)
            windows = AXHelpers.windows(axApp)
        }

        if windows.isEmpty {
            return .launching
        }

        // "Main Window" means logged in
        if windows.contains(where: { AXHelpers.identifier($0) == "Main Window" }) {
            return .loggedIn
        }

        // Check for update dialog
        for window in windows {
            if AXHelpers.findFirst(window, role: "AXButton", text: "update") != nil ||
               AXHelpers.findFirst(window, role: "AXButton", text: "업데이트") != nil {
                return .updateRequired
            }
        }

        // Windows exist but no Main Window — login screen
        return .loginScreen
    }

    // MARK: - Launch

    public static func launch() throws {
        guard !isRunning() else { return }

        let appURL = URL(fileURLWithPath: appPath)
        guard FileManager.default.fileExists(atPath: appPath) else {
            throw KakaoError.kakaoTalkNotInstalled
        }

        let config = NSWorkspace.OpenConfiguration()
        config.activates = true

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var launchError: (any Error)?

        NSWorkspace.shared.openApplication(at: appURL, configuration: config) { _, error in
            launchError = error
            semaphore.signal()
        }
        semaphore.wait()

        if let error = launchError {
            throw LifecycleError.launchFailed(error.localizedDescription)
        }
    }

    // MARK: - Wait Utilities

    public static func waitForAnyState(
        _ targets: Set<KakaoAppState>,
        timeout: TimeInterval = 30.0,
        pollInterval: TimeInterval = 0.5
    ) -> KakaoAppState {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let current = detectState()
            if targets.contains(current) { return current }
            Thread.sleep(forTimeInterval: pollInterval)
        }
        return detectState()
    }

    // MARK: - Ensure Ready

    /// Ensure KakaoTalk is running and logged in.
    /// If not running, launches it. If on login screen and credentials are available,
    /// attempts auto-login.
    public static func ensureReady(credentials: CredentialStore? = nil) throws {
        let state = detectState()

        switch state {
        case .loggedIn:
            return

        case .notRunning:
            fputs("Launching KakaoTalk...\n", stderr)
            try launch()
            let afterLaunch = waitForAnyState([.loggedIn, .loginScreen, .updateRequired], timeout: 15.0)
            if afterLaunch == .loggedIn { return }
            if afterLaunch == .updateRequired { throw LifecycleError.updateRequired }
            if afterLaunch == .loginScreen {
                try attemptLogin(credentials: credentials)
                return
            }
            throw LifecycleError.launchTimeout

        case .launching:
            let afterWait = waitForAnyState([.loggedIn, .loginScreen, .updateRequired], timeout: 15.0)
            if afterWait == .loggedIn { return }
            if afterWait == .loginScreen {
                try attemptLogin(credentials: credentials)
                return
            }
            throw LifecycleError.launchTimeout

        case .loginScreen:
            try attemptLogin(credentials: credentials)

        case .updateRequired:
            throw LifecycleError.updateRequired

        case .unknown:
            throw LifecycleError.unknownState
        }
    }

    // MARK: - Private

    private static func attemptLogin(credentials: CredentialStore?) throws {
        guard let creds = credentials, let email = creds.email, let password = creds.password else {
            throw LifecycleError.loginRequired
        }
        try LoginAutomator.login(email: email, password: password)
    }
}

/// Errors specific to app lifecycle management.
public enum LifecycleError: Error, CustomStringConvertible {
    case launchFailed(String)
    case launchTimeout
    case loginRequired
    case loginFailed(String)
    case otpRequired
    case updateRequired
    case wrongPassword
    case networkError
    case unknownState

    public var description: String {
        switch self {
        case .launchFailed(let msg): return "Failed to launch KakaoTalk: \(msg)"
        case .launchTimeout: return "KakaoTalk launched but did not become ready within timeout"
        case .loginRequired: return "KakaoTalk is showing the login screen but no credentials are stored. Run: kakaocli login"
        case .loginFailed(let msg): return "Login failed: \(msg)"
        case .otpRequired: return "KakaoTalk is requesting a 2FA verification code. Complete login manually."
        case .updateRequired: return "KakaoTalk requires an update. Please update the app manually."
        case .wrongPassword: return "Login failed: incorrect email or password"
        case .networkError: return "Login failed: network error (check your internet connection)"
        case .unknownState: return "KakaoTalk is in an unrecognized state"
        }
    }
}
