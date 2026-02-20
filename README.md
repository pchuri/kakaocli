# kakaocli

**CLI tool for KakaoTalk on macOS — read chats, search messages, send texts, and integrate with AI agents.**

**macOS용 카카오톡 CLI 도구 — 채팅 읽기, 메시지 검색, 텍스트 전송, AI 에이전트 연동.**

<p align="center">
  <img src="assets/demo.svg" alt="kakaocli demo" width="820">
</p>

> [!NOTE]
> This tool reads KakaoTalk's local database and automates the UI via macOS Accessibility APIs. It does not reverse-engineer the KakaoTalk protocol or call any Kakao APIs. See [Disclaimer](#disclaimer) for details.

---

**[English](#overview)** | **[한국어](#개요)**

---

## Overview

kakaocli gives you CLI access to your KakaoTalk conversations on Mac:

- **Read** — list chats, view messages, full-text search, raw SQL queries
- **Send** — send messages to any chat via UI automation
- **Sync** — real-time NDJSON message stream with webhook support
- **Harvest** — bulk-capture chat names and load older message history
- **AI Agent Integration** — JSON output, MCP skill, webhook delivery

### Why?

Kakao's official APIs cannot read chat history, export conversations, or send free-form messages. kakaocli fills that gap by reading the encrypted local database and automating the native macOS client.

## 개요

kakaocli는 Mac에서 카카오톡 대화에 CLI로 접근할 수 있게 해줍니다:

- **읽기** — 채팅 목록, 메시지 조회, 전체 텍스트 검색, SQL 쿼리
- **전송** — UI 자동화를 통한 메시지 전송
- **동기화** — 실시간 NDJSON 메시지 스트림 및 웹훅 지원
- **수집** — 채팅방 이름 일괄 수집 및 이전 메시지 로드
- **AI 에이전트 연동** — JSON 출력, MCP 스킬, 웹훅 전달

### 왜 필요한가요?

카카오 공식 API로는 채팅 기록을 읽거나, 대화를 내보내거나, 자유로운 메시지를 보낼 수 없습니다. kakaocli는 암호화된 로컬 데이터베이스를 읽고 네이티브 macOS 클라이언트를 자동화하여 이 부분을 해결합니다.

## Getting Started / 시작하기

### Install via Homebrew (recommended)

```bash
brew install silver-flight-group/tap/kakaocli
```

This installs sqlcipher automatically and builds kakaocli from source (~20 seconds).

### Or build from source / 소스에서 빌드

```bash
brew install sqlcipher
git clone https://github.com/silver-flight-group/kakaocli.git
cd kakaocli
swift build
```

### 3. Grant permissions / 권한 부여

Your terminal app needs two permissions in **System Settings > Privacy & Security**:

터미널 앱에 다음 두 가지 권한이 필요합니다 (**시스템 설정 > 개인정보 보호 및 보안**):

- **Accessibility** (접근성) — for UI automation (sending messages, harvest)
- **Full Disk Access** (전체 디스크 접근) — to read KakaoTalk's encrypted database

### 4. Verify it works / 동작 확인

```bash
# Check KakaoTalk installation and permissions
kakaocli status

# Verify database decryption
kakaocli auth

# List your most recent chats
kakaocli chats --limit 10
```

If `auth` succeeds, you're all set. All read commands work immediately — no KakaoTalk login or window required.

`auth`가 성공하면 준비 완료입니다. 모든 읽기 명령은 카카오톡 창 없이도 바로 작동합니다.

### 5. Try it out / 사용해보기

```bash
# Search across all your messages
kakaocli search "점심"

# Read recent messages from a chat (substring match on name)
kakaocli messages --chat "지수" --since 7d

# Send a message (opens KakaoTalk UI automatically)
kakaocli send "지수" "안녕!"

# Send to self-chat (나와의 채팅) — safe for testing
kakaocli send --me _ "test message"

# Stream new messages as JSON
kakaocli sync --follow

# Run a custom SQL query against the database
kakaocli query "SELECT COUNT(*) FROM NTChatMessage"
```

> [!TIP]
> Use `--me` to send to your self-chat (나와의 채팅) when testing. This is the safest way to verify send functionality.

## Commands

### Read / 읽기

| Command | Description |
|---------|-------------|
| `kakaocli status` | Check KakaoTalk installation and permissions |
| `kakaocli auth` | Verify database decryption |
| `kakaocli chats` | List chats sorted by last activity |
| `kakaocli messages --chat "name"` | Show messages from a chat (substring match) |
| `kakaocli search "keyword"` | Full-text search across all messages |
| `kakaocli schema` | Dump raw database schema |
| `kakaocli query "SQL"` | Run read-only SQL against the decrypted database |

All read commands support `--json` for structured output.

모든 읽기 명령은 `--json` 옵션으로 구조화된 출력을 지원합니다.

### Send / 전송

```bash
kakaocli send "chat name" "message"    # Send to a chat
kakaocli send --me _ "message"         # Send to self-chat (나와의 채팅)
kakaocli send --dry-run "name" "msg"   # Preview without sending
```

### Sync / 동기화

```bash
kakaocli sync --follow                              # NDJSON stream of new messages
kakaocli sync --follow --interval 1                  # Poll every 1 second
kakaocli sync --follow --webhook http://localhost:8080/kakao  # POST to webhook
```

See [AGENTS.md](AGENTS.md) for AI agent integration instructions.

### Harvest / 수집

```bash
kakaocli harvest                   # Capture display names for all chats
kakaocli harvest --scroll          # Also load older message history
kakaocli harvest --scroll --top 20 # Process top 20 most recent chats
kakaocli harvest --dry-run         # Preview without changes
```

The harvest command iterates through your chat list to:
1. Capture **display names** from the UI (many group chats show `(unknown)` in the database)
2. With `--scroll`: open each chat, scroll to top, click "View Previous Chats" to load older messages
3. Auto-dismiss **Talk Drive Plus paywall** popups
4. Save metadata to `~/.kakaocli/metadata.json`

Chats with unread messages are skipped to avoid marking them as read.

### Login / 로그인

```bash
kakaocli login                                       # Store credentials (interactive)
kakaocli login --email user@example.com --password pw # Non-interactive
kakaocli login --status                               # Check status
kakaocli login --clear                                # Remove credentials
```

When you run `send`, `sync`, or any command that needs KakaoTalk, the tool automatically launches the app, detects the login screen, fills credentials, and waits for login to complete.

## How It Works / 동작 원리

**Database access:** KakaoTalk Mac stores conversations in an SQLCipher-encrypted database. The encryption key is derived using PBKDF2-HMAC-SHA256 (100k iterations) from the device UUID and user's KakaoTalk ID. The database is opened in **read-only mode** (`SQLITE_OPEN_READONLY`) — kakaocli never modifies the KakaoTalk database.

**데이터베이스 접근:** 카카오톡 Mac은 SQLCipher로 암호화된 데이터베이스에 대화를 저장합니다. kakaocli는 **읽기 전용 모드**(`SQLITE_OPEN_READONLY`)로 열어 데이터베이스를 절대 수정하지 않습니다.

**UI automation:** Uses the macOS Accessibility API (AXUIElement) to navigate the KakaoTalk window, open chats, type messages, and press Enter. The Vision framework is used for OCR-based button detection during harvest.

**UI 자동화:** macOS 접근성 API(AXUIElement)를 사용하여 카카오톡 창을 탐색하고, 채팅을 열고, 메시지를 입력합니다.

### Architecture

```
Sources/
  KakaoCore/                    # Core library
    Database/
      KeyDerivation.swift       # PBKDF2-SHA256 key derivation
      DeviceInfo.swift          # Device UUID, container path, user ID
      DatabaseReader.swift      # SQLCipher database access (read-only)
      Models/                   # Chat, Message, Contact structs
    Automation/
      AXHelpers.swift           # macOS Accessibility API helpers
      AppLifecycle.swift        # App state detection, launch, login
      ChatHarvester.swift       # Bulk chat history loading via UI
      KakaoAutomator.swift      # UI automation (send messages)
    Sync/
      DatabaseWatcher.swift     # Polls DB for new messages
      WebhookPublisher.swift    # POSTs messages to webhook URL
  KakaoCLI/                     # CLI entry point (swift-argument-parser)
    Commands/                   # Subcommands
  CSQLCipher/                   # System library wrapper for sqlcipher
Tests/
  KakaoCoreTests/
    KeyDerivationTests.swift    # Key derivation tests
```

### KakaoTalk Database Schema

| Table | Purpose |
|-------|---------|
| NTChatRoom | Chat rooms — chatId, type (0=direct, 1-3=group, 4=open, 5=self), activeMembersCount, lastUpdatedAt |
| NTChatMessage | Messages — chatId, logId, authorId, message, sentAt, type (1=text) |
| NTUser | Users — userId, displayName, friendNickName, nickName |
| NTOpenLink | Open channel links — linkId, linkName |
| NTChatContext | User context — userId for current user |

## Disclaimer

> **This project is not affiliated with, endorsed by, or associated with Kakao Corp. in any way.**
>
> "KakaoTalk" and "카카오톡" are trademarks of Kakao Corp. This tool is an independent, unofficial project.
>
> **What this tool does:**
> - Reads the KakaoTalk local database on your own machine (read-only, never modifies it)
> - Automates the native KakaoTalk Mac client via standard macOS Accessibility APIs
>
> **What this tool does NOT do:**
> - Does not reverse-engineer or reimplement the KakaoTalk protocol (LOCO)
> - Does not call any Kakao APIs or servers
> - Does not decompile or modify the KakaoTalk application
> - Does not bypass any authentication or security mechanisms
>
> This tool accesses only your own data stored locally on your own computer. Use responsibly and at your own risk. The authors are not responsible for any consequences of using this software, including but not limited to account restrictions by Kakao.

## 면책 조항

> **이 프로젝트는 카카오와 제휴, 보증, 또는 관련이 없습니다.**
>
> "KakaoTalk" 및 "카카오톡"은 카카오의 상표입니다. 이 도구는 독립적인 비공식 프로젝트입니다.
>
> **이 도구가 하는 것:**
> - 사용자의 컴퓨터에 있는 카카오톡 로컬 데이터베이스를 읽기 전용으로 읽습니다
> - 표준 macOS 접근성 API를 통해 카카오톡 Mac 클라이언트를 자동화합니다
>
> **이 도구가 하지 않는 것:**
> - 카카오톡 프로토콜(LOCO)을 역분석하거나 재구현하지 않습니다
> - 카카오 API나 서버를 호출하지 않습니다
> - 카카오톡 애플리케이션을 디컴파일하거나 수정하지 않습니다
>
> 이 도구는 사용자 본인의 컴퓨터에 저장된 본인의 데이터에만 접근합니다. 책임감 있게 사용하시기 바랍니다. 카카오의 계정 제한 등 이 소프트웨어 사용으로 인한 결과에 대해 저자는 책임지지 않습니다.

## Credits / 크레딧

Developed by **[Brian ByungHyun Shin](https://github.com/brianshin22)** at **[Silver Flight Group](https://github.com/silver-flight-group)**.

Database decryption approach based on research by [blluv](https://gist.github.com/blluv/8418e3ef4f4aa86004657ea524f2de14).

Inspired by [wacli](https://github.com/steipete/wacli) by Peter Steinberger — a similar CLI tool for WhatsApp on Mac.

Built with [Claude Code](https://claude.ai/code).

## License

MIT License. Copyright (c) 2026 Silver Flight Group, LLC. See [LICENSE](LICENSE) for details.

## Changelog

### v0.5.0 - Chat Harvest (Phase 4)
- `harvest` command: bulk-capture chat display names and load message history
- Vision framework OCR to locate "View Previous Chats" button
- CGEvent-based clicking for reliable UI interaction
- CGWindow API for paywall popup detection
- Auto-dismiss Talk Drive Plus paywall dialogs
- MetadataStore: persistent chatId → displayName at `~/.kakaocli/metadata.json`
- `query` command: raw read-only SQL queries against the decrypted database

### v0.4.1 - Robust Auto-Login
- Fix credential storage: switch from Security framework to `security` CLI
- Fix state detection: use status bar menu when AX window is not visible
- Fix login transition: non-aggressive polling avoids interfering with login flow

### v0.4.0 - App Lifecycle & Login (Phase 3.5)
- `login` command: store/check/clear credentials (macOS Keychain)
- AppLifecycle: auto-launch KakaoTalk, auto-login via AX automation
- `ensureReady()` called before all send operations

### v0.3.0 - Agent Integration (Phase 3)
- `sync` command with `--follow` for real-time NDJSON message streaming
- Webhook support: `--webhook <url>` POSTs new message batches
- AGENTS.md: AI agent integration instructions

### v0.2.0 - UI Automation (Phase 2)
- Send messages via macOS Accessibility API
- `send` command with chat name matching
- `--me` flag for self-chat (나와의 채팅) via badge detection
- `inspect` command to dump UI element tree

### v0.1.0 - Database Reader (Phase 1)
- SQLCipher database decryption (PBKDF2-SHA256, cipher_default_compatibility=3)
- Auto-detect device UUID, user ID, container path
- `auth`, `chats`, `messages`, `search`, `schema`, `status` commands
- JSON output for all read commands
