# CLAUDE.md

## Build & Test

```bash
swift build
swift test
```

No external dependencies besides `sqlcipher` (Homebrew). The `CSQLCipher` system library target wraps it via pkg-config.

## Project Structure

- `Sources/KakaoCore/` - Core library: database decryption, models, UI automation
- `Sources/KakaoCLI/` - CLI using swift-argument-parser
- `Sources/CSQLCipher/` - System library modulemap for sqlcipher
- `Tests/KakaoCoreTests/` - Unit tests

## Key Technical Details

### Database
- **SQLCipher**: `PRAGMA cipher_default_compatibility = 3` (NOT `cipher_compatibility`)
- **Container path**: `com.kakao.KakaoTalkMac` (NOT `KakaoTalk`)
- **DB files**: No `.db` extension - raw hex filenames
- **User ID**: Extracted from `FSChatWindowTransparency` plist key common suffix
- **sqlcipher header**: `#include <sqlite3.h>` (NOT `<sqlcipher/sqlite3.h>`)

### UI Automation (AX)
- **Self-chat**: Identified in UI by `"badge me"` AX image descriptor, NOT by name
- **Main window**: `id="Main Window"` for both login screen AND logged-in state
- **Login screen vs logged-in**: Distinguish by window title ("Log in" vs "KakaoTalk") or Logo image
- **Login fields**: Two regular `AXTextField` elements — email first, password second. Password is NOT `AXSecureTextField`.
- **Non-standard AX hierarchy**: `kAXWindowsAttribute` returns `AXApplication` elements instead of `AXWindow` when the window is hidden
- **Status bar menu**: Most reliable way to check login state — "Log out" = logged in
- **Window may not appear**: After clicking "Open KakaoTalk" in status bar, the AXWindow may take several seconds to materialize or may not appear at all

### Credential Storage
- Uses `security` CLI tool, NOT Security.framework (avoids code-signing ACL issues with `swift run`)
- Keychain service: `com.kakaocli.credentials`
- Accounts: `kakaotalk-email`, `kakaotalk-password`
- Any process by the current macOS user can access (no per-app ACL)

### App Lifecycle
- `AppLifecycle.detectState(aggressive:)` — `aggressive: true` tries to show hidden window, `false` just checks
- `AppLifecycle.ensureReady()` — called before all send operations; handles launch + login
- `LoginAutomator.login()` — fills credentials, clicks login, polls status bar for completion
- After login button click, the window disappears during transition — poll with non-aggressive mode
- "Keep me logged in" checkbox is auto-checked — subsequent launches skip login

### Harvest / Chat History Loading
- **Vision OCR**: Uses `VNRecognizeTextRequest` to find "View Previous Chats" in screenshots. Bounding box origin is bottom-left (flip Y axis).
- **Screenshots**: Use `peekaboo image --window-id <ID>` — `--app` alone captures hidden sub-windows (69x19 tiny images)
- **Window ID**: Get via `peekaboo window list --app "KakaoTalk" -j`, match by `window_title`
- **Clicking**: Use **CGEvent** directly, NOT `peekaboo click --app` (which activates the app and can reset scroll position)
- **Scrolling**: `cliclick m:X,Y` (move cursor, no click) then `peekaboo scroll --direction up --amount 100 --no-auto-focus`
- **Activation order**: `activateAndRaise()` BEFORE scrolling — never activate right before clicking
- **Paywall popup**: Invisible to AX (`kAXWindowsAttribute`), visible to CGWindow API (`peekaboo window list`). Dismiss with Escape.
- **MetadataStore**: `~/.kakaocli/metadata.json` maps chatId → displayName, memberCount, chatType, messageCount
- **Harvest name mapping is position-based** (UI row[i] → DB row[i]) — unreliable because UI order shifts when messages arrive. Use DB-based name resolution instead.

### Database Name Resolution
- **Direct chats**: `NTUser.friendNickName` or `displayName` via `directChatMemberUserId` JOIN (filter `linkId = 0`)
- **Group chats**: Parse `NTChatRoom.displayMemberIds` — a binary plist (`bplist00`) containing `NSArray<NSNumber>` of userIds. Resolve each from NTUser.
- **Open channels/groups**: `NTOpenLink.linkName` via `linkId` JOIN
- **Self-chat** (type 5): Only 1 member, label as "Self-chat (Notes)"
- **`NTChatRoom.chatName`**: Usually empty — only set for custom-named group chats
- **`kakaocli chats --limit N`**: Default limit is 50. Use `--limit 999999` to get all chats.
- **Local DB message cache**: Only ~1-4 messages per chat are cached locally. Full history lives on KakaoTalk's servers.

### Query Command
- `kakaocli query "SELECT ..."` — runs raw read-only SQL against the decrypted DB, returns JSON array of arrays.
- Useful for ad-hoc data extraction (e.g., member lists, message stats, schema exploration).

## Safety Rules

- **NEVER send test messages to other people's chats.** Use `--me` flag for self-chat only.
- Always close existing chat windows before opening a new one (prevents sending to wrong window).
- The `inspect --open-chat` command double-clicks a chat row - treat it as a UI action that could trigger side effects.
