# BO22 - Black Ops II Zombies Bots & Mod Menu

BO22 is a **GSC script collection for Call of Duty: Black Ops II Zombies on Plutonium T6**. It combines a bot system with an optional in-game Zombies mod menu.

The bot system creates scripted bot clients, handles combat and movement, helps with common Zombies tasks, and contains separate objective logic for supported maps. The mod menu provides player, weapon, lobby, zombie, and ESP controls.

> **Important:** This repository contains source GSC files, not a standalone program or installer. Install the scripts into Plutonium's T6 script directory using the filenames shown below.

## Features

### Zombies bot system

- Spawns **7 bots by default**. The amount is read from **zm_bots** when the bot system initializes.
- Combat logic for target selection, aiming, melee, grenades, and retreating from nearby threats.
- Four command modes: **Stay**, **Wander**, **Wander Further**, and **Follow**.
- Bot support for common match activities, including reviving teammates, buying weapons and perks, using the Mystery Box, collecting power-ups, opening doors, clearing debris, and using Pack-a-Punch.
- Additional logic for shields, buildables, craftables, and map objectives.
- Separate map modules keep map-specific behaviour out of the shared bot code.

The bot routines work with the game's existing Zombies systems. Objective handling is map- and game-state-dependent; it is not a guarantee that every quest step will complete in every situation.

### Supported Zombies maps

The repository contains dedicated bot modules for:

| Map | Game script | Module |
|---|---|---|
| TranZit | zm_transit | [zm_bo2_bots_map_tranzit.gsc](./zm_bo2_bots_map_tranzit.gsc) |
| Nuketown Zombies | zm_nuked | [zm_bo2_bots_map_nuketown.gsc](./zm_bo2_bots_map_nuketown.gsc) |
| Die Rise | zm_highrise | [zm_bo2_bots_map_die_rise.gsc](./zm_bo2_bots_map_die_rise.gsc) |
| Mob of the Dead | zm_prison | [zm_bo2_bots_map_mob.gsc](./zm_bo2_bots_map_mob.gsc) |
| Buried | zm_buried | [zm_bo2_bots_map_buried.gsc](./zm_bo2_bots_map_buried.gsc) |
| Origins | zm_tomb | [zm_bo2_bots_map_origins.gsc](./zm_bo2_bots_map_origins.gsc) |

### Zombies mod menu

The optional menu is organised into sections:

- **Personal Mods:** God Mode, Noclip, Jetpack, Super Jump, Auto-Bhop, health and speed options, invisibility, third person, points, and position saving.
- **Weapon Mods:** Infinite Ammo, ammunition refill, Pack-a-Punch, weapon drops, and perks.
- **Map Weapons:** Map-specific weapons are listed when the current map has supported entries.
- **Spawns & Lobby:** Power, doors, power-up drops, round controls, game speed, gravity, restart, and end-game options.
- **Zombie Manipulation:** Kill, freeze, move, launch, or change the speed of zombies, plus other controls.
- **Aimbot & ESP:** Zombie targeting options, zombie ESP dots, map-parts ESP, and ESP size/colour settings.
- **Origins Tools:** Origins-only shared-part collection, staff-upgrade controls, mud slowdown control, and a Little Lost Girl completion option.
- **Players Menu:** Host-only player management actions, including granting or revoking menu access.

The **Complete Little Lost Girl** Origins option can end the current match. Use it deliberately.

## Installation

1. Close Black Ops II and Plutonium.
2. Open your Plutonium T6 storage directory:

   ~~~text
   %localappdata%\Plutonium\storage\t6\scripts\zm\
   ~~~

3. Create the scripts\zm folders if they do not already exist.
4. Copy **all nine GSC files** from this repository into that folder. Keep every filename unchanged.
5. Start Plutonium, launch Black Ops II, and start a Zombies match.

Your installed folder should contain:

~~~text
%localappdata%\
+-- Plutonium\
    +-- storage\
        +-- t6\
            +-- scripts\
                +-- zm\
                    +-- zm_bo2_bots.gsc
                    +-- zm_bo2_bots_combat.gsc
                    +-- zm_bo2_bots_map_buried.gsc
                    +-- zm_bo2_bots_map_die_rise.gsc
                    +-- zm_bo2_bots_map_mob.gsc
                    +-- zm_bo2_bots_map_nuketown.gsc
                    +-- zm_bo2_bots_map_origins.gsc
                    +-- zm_bo2_bots_map_tranzit.gsc
                    +-- zm_modmenu.gsc
~~~

**Do not install only the main bot file.** The main bot script includes the combat and map modules, so those companion files must be present as well. The mod menu is a separate script and must also be copied if you want to use it.

## Controls

### Bot commands

The bot system starts in **Stay** mode.

| Control | Action |
|---|---|
| **F6** | Cycle the bot command mode |
| **F7** | Teleport the bot group to your position |

F6 cycles through this sequence:

~~~text
Stay -> Wander -> Wander Further -> Follow -> Stay
~~~

F7 teleports the bots around your position with small offsets. **You must be standing on the ground** when you use it.

### Mod menu

| Control | Action |
|---|---|
| Aim + Melee together | Open the menu |
| Action Slot 1 | Scroll up |
| Action Slot 2 | Scroll down |
| Jump | Select an option |
| Melee | Go back or close the menu |

**Key-binding note:** The bot controls use the game's Action Slot commands: F6 is associated with **Action Slot 4**, and F7 with **Action Slot 3**. The menu uses Action Slots 1 and 2. These are game input bindings, not hard-coded keyboard scancodes. If your keys differ, bind the corresponding Action Slot actions in your game controls.

## Host and player access

- The host is automatically granted mod-menu access.
- The Players Menu is only built for the host.
- The host can use the Players Menu to grant or revoke menu access for other players.
- Some actions, especially map-wide or quest-related actions, check for host authority before running.

This project is intended for a Zombies session in which the custom scripts are loaded and you have the authority to run them. It is not a client-only tool that can force bots or change a server you do not control.

## Configuration

| DVAR | Purpose | Default |
|---|---|---|
| zm_bots | Number of bots spawned during initialization | 7 |
| zm_bot_quest_route | Selects the TranZit bot quest route | maxis |

The bot count is read when the bot system initializes. Set the DVAR before the map's bot initialization runs if you want a different count. The TranZit route setting is read by the TranZit quest logic; when it is unset or empty, the script uses maxis.

## Repository files

| File | Purpose |
|---|---|
| [zm_bo2_bots.gsc](./zm_bo2_bots.gsc) | Main bot system, spawning, movement, purchases, revives, and shared objective helpers |
| [zm_bo2_bots_combat.gsc](./zm_bo2_bots_combat.gsc) | Bot combat, threat handling, aiming, melee, grenades, and retreat logic |
| [zm_bo2_bots_map_tranzit.gsc](./zm_bo2_bots_map_tranzit.gsc) | TranZit-specific objectives |
| [zm_bo2_bots_map_nuketown.gsc](./zm_bo2_bots_map_nuketown.gsc) | Nuketown Zombies-specific objectives |
| [zm_bo2_bots_map_die_rise.gsc](./zm_bo2_bots_map_die_rise.gsc) | Die Rise-specific objectives |
| [zm_bo2_bots_map_mob.gsc](./zm_bo2_bots_map_mob.gsc) | Mob of the Dead-specific objectives |
| [zm_bo2_bots_map_buried.gsc](./zm_bo2_bots_map_buried.gsc) | Buried-specific objectives |
| [zm_bo2_bots_map_origins.gsc](./zm_bo2_bots_map_origins.gsc) | Origins-specific objectives |
| [zm_modmenu.gsc](./zm_modmenu.gsc) | Optional in-game Zombies mod menu |

## Troubleshooting

### The mod menu does not appear

- Confirm that zm_modmenu.gsc is in storage\t6\scripts\zm\.
- Confirm that you are the host, or that the host has granted your player menu access.
- Check that the menu controls are bound as described above.
- Restart the game and start a fresh Zombies match after changing script files.

### The bots do not spawn

- Confirm that zm_bo2_bots.gsc and every included companion module are in the same scripts\zm folder.
- Check that the zm_bots DVAR is not set to 0.
- Make sure the custom GSC scripts are being loaded by your Plutonium T6 setup.

### F6 or F7 does nothing

The scripts listen for Action Slot 4 and Action Slot 3 respectively. Check those bindings in the game controls rather than relying only on the physical F6/F7 keys.

### A map-specific option is missing

Some options only exist on the map they were written for. For example, Origins Tools is only added on Origins, and the Map Weapons section only appears when the current map has weapon entries supported by the menu.

### A script compile error appears

Check that all repository GSC files were copied with their original names and that no older copy is being loaded from another script directory. An **Unresolved external** error can also indicate that a referenced game function is not present in the loaded map/runtime. Keep the full error text, including the map name and function signature, when investigating compatibility issues.

## Contributing and bug reports

Bug reports are most useful when they include:

- The map being played.
- Whether you are the host.
- The exact steps that trigger the problem.
- The complete Plutonium script error or console log.
- Which repository revision or script files you installed.

When changing the bot system, keep shared behaviour in zm_bo2_bots.gsc and combat behaviour in zm_bo2_bots_combat.gsc. Keep map-only logic in its corresponding zm_bo2_bots_map_*.gsc module.

---

**Project:** [Tenslaster/bo22](https://github.com/Tenslaster/bo22)  
**Game:** Call of Duty: Black Ops II - Zombies  
**Platform:** Plutonium T6  
**Language:** GSC