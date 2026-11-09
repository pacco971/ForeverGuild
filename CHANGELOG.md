# Changelog

## 1.11.1 — 2026-11-09

- Fixed Layer refresh feedback: blocked addon communication is no longer reported as a successful network update.
- The Layer tab now distinguishes a local scan from a reachable peer network.

## 1.11.0 — 2026-11-09

- Added communication diagnostics for outgoing Forever addon messages, including restriction/lockdown state and API result codes.
- Added layer confidence levels and ignored weak single-observation layer IDs for hop targets.
- Added layer-hop verification: requests now wait for a confirmed target/new layer and report success or timeout.
- Added host availability, peer confidence and stale-world-refresh state to the Layer tab.
- Added compatibility parsing for both the new scored layer state message and older 1.10 peers.
- Updated Forever installation instructions and layer limitations for the `_forever_` client.
- Cleaned release packaging so generated CurseForge archives do not contain a nested ZIP.

## 1.10.0 — 2026-11-07

- Added experimental Forever layer detection from nearby creature and vehicle GUIDs.
- Added a dedicated Layer tab with friendly layer labels, raw IDs, zone, last-change time and peer status.
- Added guild, party/raid, instance-group and direct addon-message layer discovery.
- Added `Hop Any`, targeted hop requests, optional automatic layer hosting and `/fg layer scan|hop|host` commands.
- Pauses layer scanning in combat and instances to avoid restricted or secret client values.

## 1.9.2 — 2026-11-05

- Der eigene Charakter wird in der Rezept-/Crafterliste auch bei einem verzögerten Gildenroster sicher als online angezeigt.
- Asynchrone Roster-Updates können den lokalen Crafter nicht mehr fälschlich als offline markieren.

## 1.9.1 — 2026-11-05

- Retail-/Forever-Tooltip-Hooks behandeln geschützte „secret“ Unit-Werte sicher.
- PvP-Warnung überspringt nicht lesbare Target-Werte, statt die Kamera-/Target-Kette zu tainten.
- Spieler-Tooltip ergänzt Gildeninfos nur noch, wenn Unit-Token, Name und Status sicher auslesbar sind.

## 1.9.0 — 2026-11-05

- Added a separate Guild Dashboard with online/offline state, last addon sync, level, class, professions and addon activity.
- Clarified the existing Guild Map: it focuses on world/map positions and minimap pins, while the Dashboard is the full roster view.
- Added a shared Guild Activity tab for deaths, level-ups, profession/recipe updates, rare loot and crafting activity.
- Added shared Crafting Orders with open, claimed and completed states.
- Added a Layer & Group Finder with dungeon/goal posts and direct whisper/invite actions.
- Added Shift-click favorites, a resizable main window and clearer status/tooltips.

## 1.8.0 — 2026-11-05

- Reworked the Professions tab into a guild recipe catalog.
- Shows only recipes shared by guild members and groups duplicate recipes together.
- Click a recipe to expand its crafter list.
- Crafter rows can be clicked to whisper directly and show online/offline status.
- Search now matches profession, recipe name and crafter name.

## 1.7.1 — 2026-11-05

- Fixed the CurseForge/GitHub Actions package layout for the repository subfolder.
- CurseForge now receives a clean `ForeverGuild/` addon folder instead of a nested or incomplete package.

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
