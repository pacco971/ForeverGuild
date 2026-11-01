# Changelog

## 1.3 — 2026-11-01

- Removed the automatic `LoggingChat(false)` toggle from the Forever addon; Retail/Forever clients may clear or rotate the chat log when logging is toggled.
- Kept chat logging under the player’s explicit `/chatlog` control.
- Made the bridge safe for partially written log lines and UTF-8/BOM/NUL input.
- Made dry-run JSON safe on Windows consoles with emoji.
- Removed generated `__pycache__` and secret-bearing runtime files from the release package.

## 1.2

- Added the Forever addon and its Discord bridge.

