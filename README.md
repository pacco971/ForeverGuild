# ForeverGuild

ForeverGuild is a World of Warcraft Forever guild addon with a companion Discord webhook bridge.

## Included

- `ForeverGuild/` — in-game guild UI, roster/map tools, death log, guild announcements and `[KU]` event messages.
- `KU_Discord_Bridge_Forever/` — Python 3 bridge that reads `WoWChatLog.txt` and posts Discord embeds.

## Install the addon

Copy `ForeverGuild` into the Forever client’s `Interface/AddOns/` folder. Enable the addon in-game and reload the UI.

## Configure Discord

1. Copy `KU_Discord_Bridge_Forever/config.example.json` to `config.json`.
2. Enter the Discord webhook URL in `config.json`. Never commit or share that file.
3. Keep the bridge running on exactly one PC.
4. In WoW, enable chat logging once with `/chatlog` and confirm the yellow message says it is being saved.
5. Start `start_bridge.bat`, or run:

   ```text
   python ku_bridge.py
   ```

Forever may only flush the chat log when the game exits. For a full test, start the bridge, use `/ku test`, close WoW, and wait a few seconds.

## Tests

```text
python ku_bridge.py --test
python ku_bridge.py --check
python ku_bridge.py --dry-run --from-start
```

`/ku test` intentionally generates synthetic sample events. It validates the addon → chat log → bridge → Discord path; it does not describe the character’s real level or professions.

## Safety

The bridge reads local chat logs and sends matching `[KU]` messages to the configured webhook. Do not commit `config.json`, `state.json`, or real chat logs.

