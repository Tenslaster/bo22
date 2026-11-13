# Origins AI telemetry integration

This branch adds runtime diagnostics for the BO22 Origins bots.

## What changed

- `zm_bo2_bots.gsc`: starts a lightweight worker for every bot. It writes one `ORIGINS_AI_EVENT|...` record every two seconds using the stock GSC `logprint()` channel.
- `zm_bo2_bots.gsc`: adds a throttled objective-event helper so task selection is visible without flooding the game log.
- `zm_bo2_bots_map_origins.gsc`: emits task-selection events for Maxis Drone deployment, generators, shovel pickup, Ice Staff digging, Wind Staff robot part, chamber door, staff puzzles, crypt, staff charging, upgraded staff pickup, matching robot staff placement, main quest steps, and the final portal.

The bot-state record includes:
- bot entity ID, command mode, map, task category
- health, max health, current weapon, clip and reserve ammo
- combat danger, nearest distance, nearby / close / fast zombie counts
- current target entity ID and active firing-window indicator
- elapsed time since movement progress, flee and wander goal flags
- current living-zombie count
- robot-head ID and whether the bot holds each base elemental staff
- each elemental staff upgrade puzzle stage (Wind rings/smoke, Ice tiles/stones, Lightning piano/relays, Fire sacrifice/torches)
- whether the bot is registered by the stock tank script as riding the tank, plus tank movement, cooldown, and current station
- the Little Lost Girl flags and each individual staff-upgrade-unlocked flag

The Python observer parses these events, tracks transitions in staff inventory and quest flags, reports low-health / empty-ammo / apparent task-stall / last-zombie warning conditions, and keeps full snapshots in its JSONL evidence file.

## Setup

1. Use this branch in a private Plutonium Zombies match.
2. Run the Python Origins AI Watcher package supplied with this change.
3. Set its project folder to the BO22 checkout and its log folder to the folder receiving Plutonium GSC log lines.
4. Audit the scripts, start a live watch, then run one controlled Origins test at a time.

The typical local T6 storage root is `%localappdata%\Plutonium\storage\t6`. Depending on configuration, log files can be under `logs`, `main`, or a mod's `fs_game` directory.

## Safety and validation

- This branch is separate from `main`; it does not merge or overwrite the default branch.
- The added telemetry calls are intended to be observational only and do not issue movement, weapon, or objective commands.
- `fire_active` reports that the bot's GSC firing timer is active; it is not proof that a projectile hit.
- The Python static scanner is heuristic. It preserves GSC string literals for evidence discovery, and only reports duplicate function definitions repeated within the same file (same-named entrypoints in separate script files are treated as separate namespaces). It does not compile GSC.
- This change has **not** been compiled or live-tested in a Plutonium match. Run a private match and verify the log records arrive before relying on its diagnostics.
- The tank / Electric Staff jump controller is not added by this telemetry change. The source audit checks for player-side tank signals such as `trig_use_tank`, `entity_on_tank`, `b_already_on_tank`, and `vol_on_tank_watch`; it does not treat the mod-menu tank status/call buttons or zombie `tank_jump_up/down` animations as proof that bot riding works. The upstream stock tank implementation is [here](https://github.com/plutoniummod/t6-scripts/blob/main/ZM/Maps/Origins/maps/mp/zm_tomb_tank.gsc).

## One-click Windows launcher

The matching Python desktop app is stored at the repository root:

- `origins_ai_watcher.py` — watcher application
- `launch_origins_ai_watcher.bat` — Windows launcher
- `origins_ai_watcher_requirements.txt` — Python dependencies

To launch:

1. Check out this branch and open the BO22 repository folder in Windows Explorer, or extract the watcher deployment package into its own folder.
2. Double-click `launch_origins_ai_watcher.bat`.
3. On first launch, it creates a local `.venv` folder and installs the listed Python dependencies.
4. The launcher canonicalizes its own folder path **without a trailing backslash** before passing it to Python. This avoids Windows command-line parsing treating the closing quote as escaped.
5. If the watcher was extracted separately from your BO22 checkout, click **Browse** beside the BO22 project folder and select the actual repository root containing `zm_bo2_bots.gsc`.
6. It looks for Plutonium logs under `%LOCALAPPDATA%\\Plutonium\\storage\\t6\\logs`, then `main`, then the T6 storage root. If your log location is different, select it in the app.

Python 3.10+ is required. Screen capture uses `mss`; OCR additionally needs Tesseract installed on Windows and available on PATH. OCR is optional.

