# ForeverGuild

World of Warcraft Forever guild addon by Kritisch Ungemütlich.

**Version 1.11.0 für WoW Forever (Interface 16001).**

<p align="center">
  <img src="./assets/foreverguild-banner.jpg" alt="ForeverGuild Banner" width="100%">
</p>

<p align="center">
  <img src="./assets/foreverguild-ui-preview.jpg" alt="ForeverGuild UI preview" width="100%">
</p>

The addon icon is available at [`assets/foreverguild-icon-small.png`](assets/foreverguild-icon-small.png).

## Forever 1.11 / API

ForeverGuild targets WoW Forever's modern interface (`16001`). Profession ranks are read through `C_SkillInfo`; recipe scans use `C_TradeSkillUI` after a profession window is opened. Use `/fg check` to verify the API, chat-log state and the SavedVariables probe in-game.

The **Berufe** tab lists only recipes shared by guild members. Click a recipe to expand its crafter list; clicking a crafter opens a whisper, and each name shows whether the member is online or offline.

### Gildenkarte und Dashboard

**Gildenkarte** shows online members by zone and supplies the world-map/minimap pins when a member's addon shares a position. **Dashboard** is the complete roster view with online/offline status, level, class, professions, last sync and addon activity. Shift-click a member to mark or remove a favorite.

### Gilden-Aktivität

The activity tab collects guild deaths, level-ups, profession and recipe updates, rare loot and crafting-order changes during the current saved-data history.

### Crafting-Aufträge und Finder

Create an order in the **Aufträge** tab with item, quantity and note. Other members can click it to claim it; the crafter can click it again when finished. The **Finder** tab broadcasts dungeon or group goals and keeps Layer-Hop requests together with direct whisper/invite actions.

## Installation

1. Download the latest ForeverGuild release from CurseForge or GitHub.
2. Extract the `ForeverGuild` folder into the `Interface/AddOns/` folder inside your WoW Forever installation.
   Example: `<WoW-install-folder>/_forever_/Interface/AddOns/ForeverGuild/`
3. In the character-selection screen, enable the addon. If it is marked out of date, enable “Load out of date AddOns”.
4. Log in and run `/reload` once.

## Commands

- `/ku` or `/fg` — open the guild list.
- `/ku opt` — open addon settings.
- `/ku hilfe` — show all commands.
- `/ku tod` — open the death log.
- `/ku pvp` — toggle the PvP warning.
- `/ku test` — send clearly synthetic `[KU]` sample messages to guild chat.
- `/fg check` — check Forever API support, chat-log status and SavedVariables loading.
- `/fg dashboard` — open the full guild dashboard.
- `/fg aktivitaet` — open the guild activity feed.
- `/fg auftrag` — open crafting orders.
- `/fg finder` — open the layer/group finder.
- `/fg karte` — open the online guild map/list.

## Layer Hop (v1.11+)

Open the **Layer** tab with `/fg layer` or `/ku layer`.

ForeverGuild detects the current raw layer ID experimentally from several nearby creature/vehicle GUID observations. Target or mouseover an NPC, or enable nameplates, then use **Layer aktualisieren**. The tab shows a local comparison label, raw ID, zone, last change, detection confidence, known peers and whether a peer is on the same or another layer. “Lokaler Layer 1/2/…” is only an ordering of IDs seen by your guild; it is not an official server layer number.

Layer information is shared through guild, party/raid, instance-group and direct addon messages. The addon now reports outgoing-message restrictions and API result codes in `/fg check`. **Hop Any** chooses a fresh peer with at least two matching observations and prefers a configured host. Clicking a peer sends a hop request. The helper must still invite you through Blizzard's normal group system, and the group should remain active after a successful Forever hop. The addon verifies the result for up to 25 seconds and reports success or timeout instead of pretending that an invitation changed the layer.

Commands:

- `/fg layer` — open the Layer tab.
- `/fg layer scan` — rescan and refresh layer data.
- `/fg layer hop` — request any other known layer.
- `/fg layer host` — toggle automatic hosting of matching requests.
- `/fg check` — include current layer and scan status in diagnostics.

**Limits:** WoW Forever has no documented `GetAllLayers()` or `SwitchToLayer()` API. The raw ID is therefore a client-observed value, not a guaranteed official layer service. Scanning pauses in combat and instances to avoid restricted/secret values. World refreshes mark the last observation as stale until a new scan confirms it. A group invitation may help with layering, but cannot force or guarantee a switch. All participants need the updated ForeverGuild build for peer data and requests.

Layer communication can also be restricted by the client after launch or during a chat-messaging lockdown. In that case the Layer tab and `/fg check` show the blocked state and the API result; no hop can be confirmed until addon messaging works again.

## Chat logging

The optional chat-log setting is intended for the separate Discord bridge. Enable it with `/chatlog` or in `/ku opt`. ForeverGuild deliberately does not toggle logging off and on after every message, because that can clear or rotate `WoWChatLog.txt`. Depending on the client build, the file may only be flushed on logout or exit.

Use `/fg check` before a bridge test. `/ku test` sends synthetic sample values and does not represent the character’s real level or professions.

## SavedVariables

ForeverGuild stores its data in `ForeverGuildDB`. Test persistence with `/fg check`, then change one setting, use `/reload`, and run `/fg check` again. If the probe resets, the issue is in the current Forever client’s SavedVariables loader rather than in the addon.

## Discord bridge

This repository intentionally contains the addon only. Discord embeds require the separate bridge, a writable `WoWChatLog.txt`, and a configured webhook outside this repository. No webhook secret or bridge credential belongs in ForeverGuild.

## Scope

This repository contains the ForeverGuild addon only. The Discord bridge is maintained separately.


## Automated CurseForge releases

Tagged GitHub releases are packaged and uploaded automatically to CurseForge project `1781463`.

The workflow runs when a tag matching `v*` is pushed. Before creating a release tag:

1. Update `## Version:` in `ForeverGuild/ForeverGuild.toc`.
2. Update `CHANGELOG.md`.
3. Push the commit.
4. Create and push a matching tag, for example `v1.7.1`.

The repository secret `CURSEFORGE_API_TOKEN` is required by GitHub Actions. The token must be stored only in GitHub Actions Secrets and must never be committed.
