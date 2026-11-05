# ForeverGuild

World of Warcraft Forever guild addon by Kritisch Ungemütlich.

**Version 1.9.0 für WoW Forever (Interface 16001).**

<p align="center">
  <img src="./assets/foreverguild-banner.jpg" alt="ForeverGuild Banner" width="100%">
</p>

<p align="center">
  <img src="./assets/foreverguild-ui-preview.jpg" alt="ForeverGuild UI preview" width="100%">
</p>

The addon icon is available at [`assets/foreverguild-icon-small.png`](assets/foreverguild-icon-small.png).

## Forever 1.9 / API

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
2. Extract the `ForeverGuild` folder into the `Interface/AddOns/` folder of your WoW Forever installation.
   Example: `<Forever-install-folder>/Interface/AddOns/ForeverGuild/`
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

## Layer Hop (v1.5+)

Open the **Layer Hop** tab with `/fg layer` or `/ku layer`.

Only online guild members who respond from this updated addon are listed. Click a member to send a group-invite request. That member can approve the request and invite you, or decline it. You can also right-click to whisper them.

**Limits:** WoW Forever may not expose a reliable layer ID to addons, so the tab displays "Layer unbekannt" rather than inventing layer numbers. A group invitation may help with layering, but cannot force or guarantee a layer switch. All participants must install v1.5+ for peer discovery and requests. In-game validation on the Forever client is still needed.

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
