import Foundation

/// Extracts device UUID and KakaoTalk user ID from the local system.
public enum DeviceInfo {

    /// Get the IOPlatformUUID from IORegistry.
    public static func platformUUID() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        process.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        // Parse: "IOPlatformUUID" = "XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX"
        guard let range = output.range(of: #""IOPlatformUUID" = "([^"]+)""#, options: .regularExpression),
              let uuidRange = output[range].range(of: #"[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}"#, options: .regularExpression)
        else {
            throw KakaoError.uuidNotFound
        }
        return String(output[uuidRange])
    }

    /// Path to the KakaoTalk preferences plist.
    public static var preferencesPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Preferences/com.kakao.KakaoTalkMac.plist"
    }

    /// Path to the KakaoTalk container data directory.
    public static var containerPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/Library/Containers/com.kakao.KakaoTalkMac/Data/Library/Application Support/com.kakao.KakaoTalkMac"
    }

    /// Path to the container preferences plist (has more data than the global one).
    public static var containerPreferencesPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let prefDir = "\(home)/Library/Containers/com.kakao.KakaoTalkMac/Data/Library/Preferences"
        // Find the hex-suffixed plist: com.kakao.KakaoTalkMac.<HEX>.plist
        if let files = try? FileManager.default.contentsOfDirectory(atPath: prefDir) {
            for file in files where file.hasPrefix("com.kakao.KakaoTalkMac.") && file.hasSuffix(".plist") && file != "com.kakao.KakaoTalkMac.plist" {
                return "\(prefDir)/\(file)"
            }
        }
        return "\(prefDir)/com.kakao.KakaoTalkMac.plist"
    }

    /// Extract user ID from the KakaoTalk preferences plist.
    ///
    /// The user ID is embedded as a suffix in FSChatWindowTransparency keys:
    /// `FSChatWindowTransparency<chatRoomId><userId>` — the userId is the
    /// common suffix shared across all such keys.
    public static func userId() throws -> Int {
        // Try container plist first, then global
        let plistPaths = [containerPreferencesPath, preferencesPath]
        for plistPath in plistPaths {
            guard FileManager.default.fileExists(atPath: plistPath) else { continue }

            let url = URL(fileURLWithPath: plistPath)
            let data = try Data(contentsOf: url)
            guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                continue
            }

            // Strategy 1: Extract common suffix from FSChatWindowTransparency keys
            let prefix = "FSChatWindowTransparency"
            let fsChatKeys = plist.keys.filter { $0.hasPrefix(prefix) }
            if fsChatKeys.count >= 2 {
                let suffixes = fsChatKeys.map { String($0.dropFirst(prefix.count)) }
                // Find the longest common suffix among all keys
                if let commonSuffix = longestCommonSuffix(suffixes), let id = Int(commonSuffix) {
                    return id
                }
            }

            // Strategy 2: Direct key lookup
            let candidateKeys = ["userId", "user_id", "KAKAO_USER_ID", "userID"]
            for key in candidateKeys {
                if let id = plist[key] as? Int { return id }
                if let str = plist[key] as? String, let id = Int(str) { return id }
            }
        }

        throw KakaoError.userIdNotFound(["Could not extract from FSChatWindowTransparency keys or direct lookup"])
    }

    private static func longestCommonSuffix(_ strings: [String]) -> String? {
        guard let first = strings.first else { return nil }
        let reversed = strings.map { String($0.reversed()) }
        var commonLen = 0
        for i in reversed[0].indices {
            let ch = reversed[0][i]
            if reversed.allSatisfy({ i < $0.endIndex && $0[i] == ch }) {
                commonLen += 1
            } else {
                break
            }
        }
        guard commonLen > 0 else { return nil }
        return String(first.suffix(commonLen))
    }
}

public enum KakaoError: Error, CustomStringConvertible {
    case uuidNotFound
    case plistNotFound(String)
    case plistParseError
    case userIdNotFound([String])
    case databaseNotFound(String)
    case databaseOpenFailed(String)
    case sqlError(String)
    case kakaoTalkNotInstalled

    public var description: String {
        switch self {
        case .uuidNotFound:
            return "Could not read IOPlatformUUID from ioreg"
        case .plistNotFound(let path):
            return "KakaoTalk preferences not found at \(path). Is KakaoTalk installed?"
        case .plistParseError:
            return "Failed to parse KakaoTalk preferences plist"
        case .userIdNotFound(let keys):
            return "Could not find user ID in plist. Available keys: \(keys.joined(separator: ", "))"
        case .databaseNotFound(let path):
            return "KakaoTalk database not found at \(path)"
        case .databaseOpenFailed(let msg):
            return "Failed to open database: \(msg)"
        case .sqlError(let msg):
            return "SQL error: \(msg)"
        case .kakaoTalkNotInstalled:
            return "KakaoTalk.app is not installed"
        }
    }
}
