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
      AXHelpers.swift           # macOS Accessibility API helpers
      KakaoAutomator.swift      # KakaoTalk UI automation (send messages)
  KakaoCLI/                     # CLI entry point
    KakaoCLI.swift              # Main command registration
    Commands/                   # Subcommands (auth, chats, messages, etc.)
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
| NTChatRoom | Chat rooms (chatId, chatName, activeMembersCount, lastUpdatedAt) |
| NTChatMessage | Messages (chatId, logId, authorId, message, sentAt, type) |
| NTUser | Users (userId, displayName, friendNickName, nickName) |
| NTChatContext | User context (userId for current user) |

## Changelog

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
