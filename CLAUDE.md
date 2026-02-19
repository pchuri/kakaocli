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

- **SQLCipher**: `PRAGMA cipher_default_compatibility = 3` (NOT `cipher_compatibility`)
- **Container path**: `com.kakao.KakaoTalkMac` (NOT `KakaoTalk`)
- **DB files**: No `.db` extension - raw hex filenames
- **User ID**: Extracted from `FSChatWindowTransparency` plist key common suffix
- **sqlcipher header**: `#include <sqlite3.h>` (NOT `<sqlcipher/sqlite3.h>`)
- **Self-chat**: Identified in UI by `"badge me"` AX image descriptor, NOT by name

## Safety Rules

- **NEVER send test messages to other people's chats.** Use `--me` flag for self-chat only.
- Always close existing chat windows before opening a new one (prevents sending to wrong window).
- The `inspect --open-chat` command double-clicks a chat row - treat it as a UI action that could trigger side effects.
