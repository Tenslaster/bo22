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
- The Python static scanner is heuristic. It does not compile GSC.
- This change has **not** been compiled or live-tested in a Plutonium match. Run a private match and verify the log records arrive before relying on its diagnostics.
- The tank / Electric Staff jump controller is not added by this telemetry change. The source audit still flags that missing route if no implementation exists elsewhere.
