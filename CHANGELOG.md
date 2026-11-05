# Changelog

## 1.7.0 — 2026-11-05

- Fixed Retail/modern secret-value errors from `UnitHealth` and `UnitHealthMax` arithmetic.
- Switched health percentage checks to the safe `UnitHealthPercent` API with a protected legacy fallback.
- Guarded worldbuff aura reads and expiration calculations when aura data is restricted or secret.
- Prevented repeated taint/error spam from the health alert and worldbuff timer.

## 1.6 — 2026-11-03

- Ported profession-rank detection to Forever's `C_SkillInfo` API.
- Ported recipe scanning to `C_TradeSkillUI`; removed obsolete Classic skill/tradeskill calls and the restricted combat-log path.
- Updated profession events for Forever's asynchronous trade-skill data.
- Added `/fg check` for API, chat-log and SavedVariables diagnostics.
- Improved chat-log status detection through `C_ChatInfo.IsLoggingChat`.
- Updated documentation for synthetic bridge tests, SavedVariables testing and the separate Discord bridge.

## 1.4 — 2026-11-01

- Restyled the guild list and death log with the ForeverGuild dark-violet/orange-gold theme.
- Added clearer headers, active tabs, hover states, framed panels and improved spacing.

## 1.3 — 2026-11-01

- Removed the automatic `LoggingChat(false)` toggle from the Forever addon; Retail/Forever clients may clear or rotate the chat log when logging is toggled.
- Kept chat logging under the player’s explicit `/chatlog` control.
- Removed generated runtime files from the addon release package.

## 1.2

- Added the Forever addon and its Discord bridge.
