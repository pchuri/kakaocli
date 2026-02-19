# AGENTS.md — KakaoCLI for AI Agents

Instructions for AI agents that want to read and send KakaoTalk messages.

## Prerequisites

- macOS 14+ with KakaoTalk desktop app installed and logged in
- `kakaocli` binary built and in PATH (or run via `swift run kakaocli`)
- System Settings > Privacy & Security: Full Disk Access + Accessibility granted

## Quick Start

```bash
# Verify access
kakaocli auth

# List recent chats
kakaocli chats --json

# Read messages from a specific chat
kakaocli messages --chat "Mom" --since 1h --json

# Send a message
kakaocli send "Mom" "I'll be home soon"

# Send to self-chat (for testing)
kakaocli send x --me "Test message"

# Watch for new messages (NDJSON stream)
kakaocli sync --follow
```

## Reading Messages

### List Chats
```bash
kakaocli chats --json --limit 20
```
Returns: `[{"id", "type", "display_name", "member_count", "unread_count", "last_message_at"}]`

### Read Messages
```bash
kakaocli messages --chat "Name" --since 1h --json
kakaocli messages --chat-id 12345 --limit 100 --json
```
Returns: `[{"id", "chat_id", "sender_id", "sender", "text", "type", "timestamp", "is_from_me"}]`

### Search
```bash
kakaocli search "keyword" --json
```

## Sending Messages

```bash
kakaocli send "Chat Name" "Message text"
kakaocli send x --me "Self-chat message"    # --me flag for self-chat
kakaocli send "Mom" "Hello" --dry-run       # Preview without sending
```

**Important constraints:**
- Requires KakaoTalk desktop app to be running and visible
- UI automation needs Accessibility permission
- Rate limit: wait at least 2 seconds between sends
- The chat window opens, types, sends, then closes automatically

## Sync Mode (Real-Time Monitoring)

### NDJSON Stream
```bash
kakaocli sync --follow
```
Outputs one JSON object per line (NDJSON) for each new message:
```json
{"type":"message","log_id":123,"chat_id":456,"chat_name":"Mom","sender_id":789,"sender":"Mom","text":"Are you coming?","message_type":1,"timestamp":"2026-02-20T10:30:00Z","is_from_me":false}
```

### With Webhook
```bash
kakaocli sync --follow --webhook http://localhost:8080/kakao
```
POSTs batches of new messages as JSON arrays to the webhook URL.

### Options
- `--interval <seconds>` — Poll frequency (default: 2s)
- `--since-log-id <id>` — Start from a specific point instead of latest
- `--webhook <url>` — POST new messages to this URL

### One-Shot Status
```bash
kakaocli sync
```
Returns: `{"status":"ready","max_log_id":12345}` — useful for getting the current high-water mark.

## Agent Integration Pattern

Typical agent loop:

```python
import subprocess, json

# 1. Check for new messages
proc = subprocess.run(["kakaocli", "messages", "--since", "5m", "--json"],
                      capture_output=True, text=True)
messages = json.loads(proc.stdout)

# 2. Process and respond
for msg in messages:
    if not msg["is_from_me"] and needs_response(msg):
        subprocess.run(["kakaocli", "send", msg["chat_name"], response_text])
```

Or use sync mode for real-time:

```bash
kakaocli sync --follow | while read -r line; do
  echo "$line" | jq -r '.text' | process_message
done
```

## Safety Rules

1. **Never send test messages to other people's chats.** Use `--me` flag for testing.
2. **Always use `--dry-run` first** when testing new send logic.
3. **Rate limit sends** — at least 2 seconds between messages.
4. **Respect hours** — avoid sending between 11 PM and 7 AM unless urgent.
5. **Confirm before sending** — agents should verify message content with the user before sending to others.
