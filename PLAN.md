# Phase 2 Plan: UI Automation (Send Messages)

## Approach
Use macOS Accessibility API (AXUIElement) directly from Swift. No external dependencies needed.

## Steps

1. **Add `inspect` command** — dumps KakaoTalk's UI element tree to understand the hierarchy
2. **Implement KakaoAutomator** in KakaoCore/Automation/:
   - Activate KakaoTalk app
   - Find and click on a chat by name in the chat list
   - Find the message input text area
   - Set text and press Enter to send
3. **Add `send` CLI command** — `kakaocli send "나와의 채팅" "test message"`
4. **Test only with self-chat** ("나와의 채팅" / My Chat)

## Key technical decisions
- Use AXUIElement C API directly (no AXorcist dependency for now — keep it simple)
- CGEvent for keystrokes (more reliable than AXUIElement setValue for chat apps)
- Add delays between steps (activate → find chat → type → send)
- Require Accessibility permission (will prompt on first use)

## Safety
- NEVER send to other people during testing
- Default to self-chat for testing
- Add --dry-run flag that shows what would happen without sending
