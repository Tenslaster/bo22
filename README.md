<div align="center">

# BO22 — Black Ops II Zombies Bots & Mod Menu

**An advanced GSC bot framework and in-game utility menu for Call of Duty: Black Ops II Zombies on Plutonium T6.**

[![Game](https://img.shields.io/badge/Game-Black%20Ops%20II-202020?style=for-the-badge)](https://www.callofduty.com/)
[![Platform](https://img.shields.io/badge/Platform-Plutonium%20T6-blue?style=for-the-badge)](https://plutonium.pw/)
[![Language](https://img.shields.io/badge/Language-GSC-orange?style=for-the-badge)](https://github.com/Tenslaster/bo22)

[Features](#features) · [Supported Maps](#supported-maps) · [Installation](#installation) · [Controls](#controls) · [Configuration](#configuration) · [Troubleshooting](#troubleshooting)

</div>

---

## About

BO22 is a collection of **Call of Duty: Black Ops II Zombies GSC scripts** designed for Plutonium T6. It combines:

- A shared Zombies bot framework with movement, combat, weapon selection, survival, and team support.
- Dedicated map modules for map-specific objectives and buildables.
- An optional in-game mod menu for player, weapon, lobby, zombie, ESP, and map tools.

The project is built around the game's existing Zombies systems. Bots use map-aware task logic rather than relying only on generic movement and shooting routines.

> **Important:** BO22 is a source-script project. It is not a standalone executable, a server plugin, or a client-only cheat. The scripts must be loaded by a Plutonium T6 Zombies session where you have the required authority.

## Features

### Bot framework

- Spawns **7 bots by default**. The amount is controlled by the \`zm_bots\` DVAR.
- Shared bot movement, navigation, target selection, aiming, firing, melee, grenade, and weapon-switching logic.
- Threat awareness and evasive movement when surrounded or under pressure.
- Four bot command behaviours:
  - **Stay** — hold position and defend the area.
  - **Wander** — roam nearby areas.
  - **Wander Further** — explore a wider area.
  - **Follow** — stay near the player.
- Team support, including teammate revives and self-revive handling.
- Weapon and equipment logic for wall buys, perks, Mystery Box, Pack-a-Punch, and power-ups.
- Door opening, debris clearing, and interaction with common map objects.
- Shared buildable and craftable task handling, including collecting parts, carrying them, and using the correct build/craft stations.

### Combat AI

The combat system is kept in its own module and handles:

- Enemy acquisition and target prioritisation.
- Aim updates, headshot targeting, and firing control.
- Weapon selection based on target distance and weapon class.
- Safer weapon handling around explosive damage.
- Grenade use against groups of enemies.
- Retreat and repositioning when nearby threats become dangerous.
- Special-enemy awareness, including Brutus and the Origins Panzer.

### Map-aware objectives

Each supported map has its own module. The map scripts provide the extra logic needed for local objectives, interactables, buildables, and special mechanics.

#### Origins

Origins support includes map-specific task handling for:

- Shovel and dig-site related tasks.
- Generator activation and generator-area behaviour.
- Map parts and shared buildable components.
- Buildable equipment, including the Zombie Shield and Maxis Drone.
- Staff-related part and objective handling.
- Crazy Place and other map objective interactions.
- Robot-footprint and map traversal logic.
- Zombie Blood plane engagement for the relevant plane event.

Objective automation depends on the current game state, available parts, player/bot inventory, and the game's interaction conditions. It is not a guarantee that every Easter Egg step will complete automatically in every match.

#### Mob of the Dead

Mob of the Dead support includes dedicated Afterlife-related logic, target discovery, electrical interaction handling, and map equipment support. Bots should only attempt Afterlife objectives when there is a relevant task to perform; objective interactions are handled separately from ordinary combat and movement.

#### Other supported maps

TranZit, Nuketown Zombies, Die Rise, and Buried have their own map modules for supported map-specific tasks and interactions.

### In-game mod menu

The optional menu is divided into categories so that general controls and map-specific tools stay organised.

| Category | Purpose |
|---|---|
| **Personal Mods** | Player movement, survival, health, and personal utility toggles. |
| **Weapon Mods** | Weapon grants, ammunition, upgrades, and weapon-related options. |
| **Map Weapons** | Map-registered weapons that are available on the current map. |
| **Spawns & Lobby** | Match controls, doors, power, power-ups, round/game controls, and lobby utilities. |
| **Zombie Manipulation** | Zombie targeting and other enemy manipulation options. |
| **Aimbot & ESP** | Aiming assistance and visual enemy/map information. |
| **Origins Tools** | Origins-specific tools and objective utilities. |
| **Mob of the Dead Tools** | Mob-specific utilities when playing Mob of the Dead. |
| **TranZit / Die Rise / Buried Tools** | Map-specific sections when supported by the current map. |
| **Players Menu** | Host-side player management options. |

Only categories supported by the current map and session are shown. Some host actions require host authority. Use destructive match controls carefully.

## Supported Maps

| Map | Internal script name | Module |
|---|---|---|
| TranZit | \`zm_transit\` | [zm_bo2_bots_map_tranzit.gsc](./zm_bo2_bots_map_tranzit.gsc) |
| Nuketown Zombies | \`zm_nuked\` | [zm_bo2_bots_map_nuketown.gsc](./zm_bo2_bots_map_nuketown.gsc) |
| Die Rise | \`zm_highrise\` | [zm_bo2_bots_map_die_rise.gsc](./zm_bo2_bots_map_die_rise.gsc) |
| Mob of the Dead | \`zm_prison\` | [zm_bo2_bots_map_mob.gsc](./zm_bo2_bots_map_mob.gsc) |
| Buried | \`zm_buried\` | [zm_bo2_bots_map_buried.gsc](./zm_bo2_bots_map_buried.gsc) |
| Origins | \`zm_tomb\` | [zm_bo2_bots_map_origins.gsc](./zm_bo2_bots_map_origins.gsc) |

## Installation

### 1. Locate the Plutonium T6 scripts folder

Press \`Win + R\`, paste the following path, and press Enter:

\`\`\`text
%localappdata%\\Plutonium\\storage\\t6\\scripts\\zm\\
\`\`\`

Create the \`scripts\\zm\` folders if they do not already exist.

### 2. Download the scripts

Download the repository using **Code → Download ZIP**, then extract the archive.

Alternatively, download the individual files listed in [Repository Files](#repository-files).

### 3. Copy every GSC file

Copy all nine GSC files into:

\`\`\`text
%localappdata%\\Plutonium\\storage\\t6\\scripts\\zm\\
\`\`\`

Your folder should look like this:

\`\`\`text
Plutonium/
└── storage/
    └── t6/
        └── scripts/
            └── zm/
                ├── zm_bo2_bots.gsc
                ├── zm_bo2_bots_combat.gsc
                ├── zm_bo2_bots_map_buried.gsc
                ├── zm_bo2_bots_map_die_rise.gsc
                ├── zm_bo2_bots_map_mob.gsc
                ├── zm_bo2_bots_map_nuketown.gsc
                ├── zm_bo2_bots_map_origins.gsc
                ├── zm_bo2_bots_map_tranzit.gsc
                └── zm_modmenu.gsc
\`\`\`

**Keep the filenames unchanged.** The main bot script relies on its companion combat and map modules. Install the mod-menu script too if you want the in-game menu.

### 4. Launch a Zombies match

1. Start Plutonium T6.
2. Launch Black Ops II Zombies.
3. Start a supported Zombies map.
4. Confirm that the scripts load without a GSC compiler error.

If you replace scripts while the game is running, restart the match or game so the updated scripts are loaded.

## Controls

### Bot commands

| Key | Action |
|---|---|
| **F6** | Cycle bot command mode |
| **F7** | Teleport the bot group to your position |

F6 cycles through:

\`\`\`text
Stay → Wander → Wander Further → Follow → Stay
\`\`\`

F7 moves the bot group near your position using small offsets. Stand on the ground before using it.

**Binding note:** These controls are tied to the game's Action Slot commands, not hard-coded keyboard scancodes. F6 is associated with Action Slot 4 and F7 with Action Slot 3 in the documented setup. If your keyboard bindings differ, bind the corresponding Action Slot commands in the game controls.

### Mod menu

| Input | Action |
|---|---|
| **Aim + Melee together** | Open the menu |
| **Action Slot 1** | Scroll up |
| **Action Slot 2** | Scroll down |
| **Jump** | Select the highlighted option |
| **Melee** | Go back; close the menu from the main page |

The menu displays a scrolling list. On the current layout, **four entries are visible at a time**; use Action Slot 1 and 2 to reach the remaining entries. The footer shows the current selection and total number of entries.

### Spectator / free camera

The menu script includes a spectator/free-camera option. Its hotkey setup uses Action Slot 3; the script comment documents this console binding:

\`\`\`text
bind g "+actionslot 3"
\`\`\`

Use the in-menu spectator controls and exit option to return to normal play.

## Configuration

| DVAR | Description | Default |
|---|---|---|
| \`zm_bots\` | Number of bots created during bot initialization. | \`7\` |
| \`zm_bot_quest_route\` | TranZit quest route selection. | \`maxis\` |

Set DVARs before the relevant bot/map initialization runs. Changing a value after the bots have initialized may not change the already-created bot group.

## Repository Files

All nine source files are required for the complete installation.

| File | Description |
|---|---|
| [\`zm_bo2_bots.gsc\`](./zm_bo2_bots.gsc) | Main bot framework, spawning, movement, purchases, revives, buildables, craftables, and shared objective helpers. |
| [\`zm_bo2_bots_combat.gsc\`](./zm_bo2_bots_combat.gsc) | Combat AI, target selection, aiming, weapon handling, grenades, threat detection, and retreat behaviour. |
| [\`zm_bo2_bots_map_tranzit.gsc\`](./zm_bo2_bots_map_tranzit.gsc) | TranZit-specific bot tasks and objective logic. |
| [\`zm_bo2_bots_map_nuketown.gsc\`](./zm_bo2_bots_map_nuketown.gsc) | Nuketown Zombies-specific logic. |
| [\`zm_bo2_bots_map_die_rise.gsc\`](./zm_bo2_bots_map_die_rise.gsc) | Die Rise-specific bot tasks and interactions. |
| [\`zm_bo2_bots_map_mob.gsc\`](./zm_bo2_bots_map_mob.gsc) | Mob of the Dead tasks, Afterlife interaction helpers, and map equipment support. |
| [\`zm_bo2_bots_map_buried.gsc\`](./zm_bo2_bots_map_buried.gsc) | Buried-specific bot tasks and interactions. |
| [\`zm_bo2_bots_map_origins.gsc\`](./zm_bo2_bots_map_origins.gsc) | Origins generators, parts, buildables, staffs, robot, and objective helpers. |
| [\`zm_modmenu.gsc\`](./zm_modmenu.gsc) | Optional in-game Zombies mod menu and map tools. |

## Troubleshooting

### Bots do not spawn

- Confirm that \`zm_bo2_bots.gsc\` is installed.
- Confirm that the combat module and all map modules are in the same \`scripts\\zm\` folder.
- Check that \`zm_bots\` is not set to \`0\`.
- Restart the match after installing or replacing files.

### The mod menu does not open

- Confirm that \`zm_modmenu.gsc\` is installed in the correct folder.
- Try the documented **Aim + Melee** open gesture.
- Make sure the host has granted menu access if you are not the host.
- Confirm that your controls are bound to the expected Action Slot inputs.

### I can only see part of the menu

The menu uses a four-entry scrolling viewport. Use **Action Slot 1** and **Action Slot 2** to move through the complete list. The footer indicates your current position, for example \`3 / 8\`.

### A bot does not complete a map objective

- Check whether the required part, item, weapon, or game-state condition is available.
- Make sure the bot can reach the objective and that another task is not blocking it.
- Some map interactions require a specific player state or host-side game event.
- Objective automation is still map- and state-dependent; not every quest sequence is guaranteed to run unattended.

### A GSC compile error appears

- Copy the complete set of files from the same repository revision.
- Check for old duplicate copies in other script folders.
- Verify the exact filename and path shown in the error.
- Keep the full compiler output, including the unresolved function name, parameter count, map, and line number.

An **Unresolved external** error usually means the script references a function that is not available in the loaded map/runtime or has a different signature. Do not randomly rename the function; verify it against the stock map scripts and the target runtime.

## Development Guidelines

To keep the project maintainable:

- Put shared bot behaviour in \`zm_bo2_bots.gsc\`.
- Keep combat-specific logic in \`zm_bo2_bots_combat.gsc\`.
- Keep map-only interactions in the corresponding \`zm_bo2_bots_map_*.gsc\` file.
- Preserve existing menu categories and map tools when changing the menu.
- Prefer stock map functions and interaction flows over forcing quest-completion flags.
- Avoid adding unverified external GSC calls; check the stock script implementation and function signature first.

## Bug Reports

When reporting an issue, include:

1. The map you were playing.
2. Whether you were host.
3. The number of bots and the bot command mode.
4. What you expected to happen and what happened instead.
5. The complete Plutonium console/compiler error, if one appeared.
6. The repository revision or date of the files you installed.

## Disclaimer

BO22 is a community GSC scripting project for private/custom Zombies sessions. It is not affiliated with or endorsed by Activision or Plutonium. Features may behave differently depending on the game build, map state, host authority, and available stock script functions.

---

<div align="center">

**BO22** · Black Ops II Zombies · Plutonium T6 · GSC

[Repository](https://github.com/Tenslaster/bo22) · [Issues](https://github.com/Tenslaster/bo22/issues)

</div>
