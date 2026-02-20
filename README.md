# kakaocli

CLI tool for KakaoTalk on macOS, built for AI agent integration. Reads the encrypted local database and automates the UI for sending messages.

## Requirements

- macOS 14+
- Swift 6.0+
- [sqlcipher](https://github.com/nickreeves/sqlcipher) (`brew install sqlcipher`)
- KakaoTalk Mac installed and logged in
- Accessibility permission for the terminal app (for UI automation)
- Full Disk Access for the terminal app (to read KakaoTalk's container)

## Build

```bash
swift build
swift test
```

## Commands

### Read-only (Phase 1)

```bash
# Check KakaoTalk installation and permissions
kakaocli status

# Verify database decryption (lists tables)
kakaocli auth

# List all chats sorted by last activity
kakaocli chats
kakaocli chats --json

# Show messages from a chat (substring match on name)
kakaocli messages --chat "Mom"
kakaocli messages --chat "Mom" --since 7d
kakaocli messages --chat "Mom" --json

# Full-text search across all messages
kakaocli search "dinner"
kakaocli search "dinner" --json

# Dump raw database schema (for reverse engineering)
kakaocli schema

# Run raw SQL query against the decrypted database
kakaocli query "SELECT chatId, type, activeMembersCount FROM NTChatRoom LIMIT 5"
```

### UI Automation (Phase 2)

```bash
# Send a message to a chat (opens chat window via double-click)
kakaocli send "Mom" "hello"

# Send to self-chat (나와의 채팅) using badge detection
kakaocli send --me _ "test message"

# Dry run (shows what would happen without sending)
kakaocli send --dry-run "Mom" "hello"

# Inspect KakaoTalk's accessibility element tree
kakaocli inspect
kakaocli inspect --depth 8
kakaocli inspect --open-chat "Mom" --depth 5
```

### Sync Mode (Phase 3)

```bash
# Check current high-water mark
kakaocli sync

# Watch for new messages as NDJSON stream
kakaocli sync --follow

# Custom poll interval (default: 2s)
kakaocli sync --follow --interval 1

# POST new messages to a webhook
kakaocli sync --follow --webhook http://localhost:8080/kakao

# Start from a specific logId instead of latest
kakaocli sync --follow --since-log-id 12345
```

See [AGENTS.md](AGENTS.md) for detailed AI agent integration instructions.

### Harvest Mode (Phase 4)

```bash
# Capture display names from UI for all chats (fast, no scrolling)
kakaocli harvest

# Full harvest: open each chat, scroll to top, click "View Previous Chats"
kakaocli harvest --scroll

# Process only top N most recent chats
kakaocli harvest --scroll --top 20

# Control max "View Previous Chats" clicks per chat
kakaocli harvest --scroll --max-clicks 5

# Preview without making changes
kakaocli harvest --dry-run
```

**What it does:**

1. Iterates through the chat list (ordered by last activity)
2. Captures **display names** from the UI (many are `(unknown)` in the DB for group chats)
3. With `--scroll`: opens each chat, scrolls to top, and clicks "View Previous Chats" to load older message history from the server
4. Detects and dismisses **Talk Drive Plus paywall** popups automatically
5. Saves metadata (chatId → displayName, member count, message count) to `~/.kakaocli/metadata.json`
6. Skips chats with unread messages (to avoid marking them as read)

**Technical approach:**
- Uses **Vision framework OCR** to locate "View Previous Chats" text in screenshots (position varies per chat)
- Takes screenshots via `peekaboo image --window-id` for reliable window capture
- Clicks via **CGEvent** (direct mouse events, more reliable than external tools)
- Detects paywall popups via **CGWindow API** (the popup is a sheet that doesn't appear in the AX window list)

### Login & Lifecycle Management

```bash
# Store credentials (interactive password prompt)
kakaocli login

# Non-interactive (required for AI agent / automation contexts)
kakaocli login --email user@example.com --password secret

# Check current status (app state, stored credentials)
kakaocli login --status

# Remove stored credentials from Keychain
kakaocli login --clear
```

**Automatic lifecycle management:** When you run `send`, `sync`, or any command that needs KakaoTalk, the tool automatically:

1. **Launches KakaoTalk** if not running
2. **Detects login screen** via AX window title and status bar menu
3. **Auto-fills credentials** and clicks "Log in" if credentials are stored
4. **Checks "Keep me logged in"** so future launches skip the login screen
5. **Waits for login to complete** before proceeding

If KakaoTalk is already running and logged in, this all happens instantly.

#### Credential Storage

Credentials are stored in the **macOS login Keychain** using the `security` CLI tool:

- **Service:** `com.kakaocli.credentials`
- **Items:** `kakaotalk-email` and `kakaotalk-password`
- **Access:** Any process running as the current macOS user can read them (no per-app ACL, since `swift run` changes binary paths on rebuild)
- **Encryption:** Protected by the macOS Keychain encryption (AES-256-GCM, locked when user logs out)

To inspect stored credentials manually:
```bash
security find-generic-password -s "com.kakaocli.credentials" -a "kakaotalk-email" -w
```

#### App State Detection

The tool detects KakaoTalk's state via multiple methods:

| Method | When Used | How |
|--------|-----------|-----|
| AX Window inspection | Window is visible | Check window title, presence of login elements vs chat list |
| Status bar menu | Window is hidden | Read menu items: "Log out" = logged in, "Log in" = not |
| Process check | Always | `NSRunningApplication` by bundle ID |

KakaoTalk's AX hierarchy is non-standard — `kAXWindowsAttribute` may return `AXApplication` elements instead of `AXWindow`. The status bar menu is the most reliable state indicator.

## Architecture

```
Sources/
  KakaoCore/                    # Core library (no CLI dependency)
    Database/
      KeyDerivation.swift       # PBKDF2-SHA256 key derivation (blluv's method)
      DeviceInfo.swift          # Device UUID, container path, user ID detection
      DatabaseReader.swift      # SQLCipher database access
      Models/                   # Chat, Message, Contact structs
    Automation/
      AXHelpers.swift           # macOS Accessibility API + keyboard helpers
      AppLifecycle.swift        # App state detection, launch, ensureReady()
      LoginAutomator.swift      # AX-based login screen automation
      CredentialStore.swift     # macOS Keychain credential storage
      KakaoAutomator.swift      # KakaoTalk UI automation (send messages)
      ChatHarvester.swift       # UI automation for bulk chat history loading
    Sync/
      DatabaseWatcher.swift     # Polls DB for new messages by logId
      WebhookPublisher.swift    # POSTs message batches to webhook URL
  KakaoCLI/                     # CLI entry point
    KakaoCLI.swift              # Main command registration
    Commands/                   # Subcommands (auth, chats, messages, login, harvest, etc.)
  CSQLCipher/                   # System library wrapper for sqlcipher
Tests/
  KakaoCoreTests/
    KeyDerivationTests.swift    # Key derivation determinism tests
```

### Database Decryption

KakaoTalk Mac stores its database in an SQLCipher-encrypted file at:
```
~/Library/Containers/com.kakao.KakaoTalkMac/Data/Library/Application Support/com.kakao.KakaoTalkMac/<hex-name>
```

The database key is derived using PBKDF2-HMAC-SHA256 (100k iterations) from a combination of the device UUID (from `ioreg`) and the user's KakaoTalk ID. The user ID is extracted from the common suffix of `FSChatWindowTransparency` preference keys.

Uses `PRAGMA cipher_default_compatibility = 3` for SQLCipher compatibility.

### UI Automation

Uses macOS Accessibility API (AXUIElement) directly from Swift:

1. **Close stale windows** - prevents sending to wrong chat
2. **Find main window** by `id="Main Window"`
3. **Navigate chat list** - AXTable > AXRow > AXCell > AXStaticText
4. **Self-chat detection** - identified by `"badge me"` AX image descriptor
5. **Double-click** to open chat window
6. **Find input field** - AXScrollArea (without AXTable child) > AXTextArea
7. **Set text** via AXValue (more reliable than CGEvent keystrokes)
8. **Press Enter** to send

### KakaoTalk Database Schema (key tables)

| Table | Purpose |
|-------|---------|
| NTChatRoom | Chat rooms — chatId, type (0=direct, 1-3=group, 4=open, 5=self), chatName (usually empty), activeMembersCount, lastUpdatedAt, displayMemberIds (binary plist of userId array), directChatMemberUserId, linkId |
| NTChatMessage | Messages — chatId, logId, authorId, message, sentAt, type (1=text) |
| NTUser | Users — userId, displayName, friendNickName, nickName, linkId (0=friend, >0=open channel member) |
| NTOpenLink | Open channel links — linkId, linkName |
| NTChatContext | User context — userId for current user |

## Changelog

### v0.5.0 - Chat Harvest (Phase 4)
- `harvest` command: bulk-capture chat display names and load message history
- Vision framework OCR to locate "View Previous Chats" button (position varies per chat)
- CGEvent-based clicking for reliable UI interaction
- CGWindow API for paywall popup detection (AX doesn't see sheet-style popups)
- Auto-dismiss Talk Drive Plus paywall dialogs
- MetadataStore: persistent chatId → displayName mapping at `~/.kakaocli/metadata.json`
- Scroll-to-top via `cliclick` mouse positioning + `peekaboo scroll --no-auto-focus`
- Screenshots via `peekaboo image --window-id` (avoids hidden sub-window capture)
- Skips chats with unread messages by default

### v0.4.1 - Robust Auto-Login
- Fix credential storage: switch from Security framework to `security` CLI (avoids code-signing ACL issues with `swift run`)
- Fix state detection: use status bar menu when AX window is not visible
- Fix login transition: non-aggressive polling avoids interfering with login flow
- Add AppleScript-based window recovery for hidden-window state
- Detect login state reliably even when window is hidden (menu bar "Log out" check)

### v0.4.0 - App Lifecycle & Login (Phase 3.5)
- `login` command: store/check/clear KakaoTalk credentials (macOS Keychain)
- AppLifecycle: auto-launch KakaoTalk when not running
- LoginAutomator: auto-login via AX automation when login screen detected
- CredentialStore: secure credential storage via macOS Keychain
- `ensureReady()` called before all send operations
- Login screen detection: window title "Log in" + Logo image check
- "Keep me logged in" checkbox auto-checked
- `status` command shows app state and credential status
- Keyboard helpers (typeText, pressKey) extracted to shared AXHelpers

### v0.3.0 - Agent Integration (Phase 3)
- `sync` command with `--follow` for real-time NDJSON message streaming
- DatabaseWatcher: polls for new messages by tracking logId high-water mark
- Webhook support: `--webhook <url>` POSTs new message batches as JSON
- Configurable poll interval via `--interval`
- Resume from specific point via `--since-log-id`
- AGENTS.md: instructions for AI agent integration
- SKILL.md: OpenClaw skill definition
- Auto-close chat window after sending
- Version bump to 0.3.0

### v0.2.0 - UI Automation (Phase 2)
- Send messages via macOS Accessibility API
- `send` command with chat name matching
- `--me` flag for self-chat (나와의 채팅) via badge detection
- `inspect` command to dump UI element tree
- Close stale chat windows before opening target
- AXValue text input with CGEvent fallback
- Window raise + click focus for reliable targeting

### v0.1.0 - Database Reader (Phase 1)
- SQLCipher database decryption (PBKDF2-SHA256, cipher_default_compatibility=3)
- Auto-detect device UUID, user ID, container path
- `auth`, `chats`, `messages`, `search`, `schema`, `status` commands
- JSON output support for all read commands
- Sender name resolution via NTUser JOIN
