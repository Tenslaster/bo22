<!-- BO22 project documentation -->

<div align="center">

# BO22
## Black Ops II Zombies — Bots, Map Objectives & Mod Menu

A modular **GSC scripting project for Call of Duty: Black Ops II Zombies on Plutonium T6**.

[![Game](https://img.shields.io/badge/Game-Black%20Ops%20II-222222?style=for-the-badge)](https://www.callofduty.com/)
[![Platform](https://img.shields.io/badge/Platform-Plutonium%20T6-blue?style=for-the-badge)](https://plutonium.pw/)
[![Language](https://img.shields.io/badge/Language-GSC-orange?style=for-the-badge)](https://github.com/Tenslaster/bo22)

**Six Zombies maps · Scripted bots · Map-specific objectives · In-game mod menu**

[Features](#features) · [Maps](#map-by-map-guide) · [Installation](#installation) · [Controls](#controls) · [Menu Guide](#in-game-mod-menu) · [Troubleshooting](#troubleshooting)

</div>

---

## Contents

- [What is BO22?](#what-is-bo22)
- [Features](#features)
- [How the bot system works](#how-the-bot-system-works)
- [Map-by-map guide](#map-by-map-guide)
  - [Origins](#1-origins)
  - [Mob of the Dead](#2-mob-of-the-dead)
  - [TranZit](#3-tranzit)
  - [Die Rise](#4-die-rise)
  - [Buried](#5-buried)
  - [Nuketown Zombies](#6-nuketown-zombies)
- [In-game mod menu](#in-game-mod-menu)
- [Controls](#controls)
- [Installation](#installation)
- [Configuration](#configuration)
- [Repository files](#repository-files)
- [Validation status and known limitations](#validation-status-and-known-limitations)
- [Troubleshooting](#troubleshooting)
- [Reporting a bug](#reporting-a-bug)

---

## What is BO22?

BO22 is a collection of GSC scripts that adds a team of AI-controlled players to Black Ops II Zombies and gives the host an optional in-game utility menu.

It is split into three main parts:

1. **Shared bot framework** — spawns the bots and manages their movement, target selection, weapons, survival, revives, purchases, and general interactions.
2. **Map modules** — add objective logic for the map that is currently being played. Origins, Mob of the Dead, TranZit, Die Rise, Buried, and Nuketown each have their own module.
3. **Mod menu** — provides player, weapon, lobby, zombie, ESP, and map-specific actions from inside the match.

BO22 is intended for a Zombies match in which the scripts are loaded and you have permission to run them. It is **not** a standalone .exe, a Plutonium server plugin, or a client-only tool that can control a server you do not own.

> **Important:** Objective automation is state-dependent. Bots check real map entities, inventory, triggers, and stock game conditions. A feature being implemented does not mean every quest or Easter Egg is guaranteed to finish unattended in every match.

## Features

### AI bot team

- Creates **7 bots by default**.
- The number of bots can be changed with the `zm_bots` DVAR before the bot system initializes.
- Bots respawn their bot logic after being spawned/revived.
- Bots have four team command modes: **Stay**, **Wander**, **Wander Further**, and **Follow**.
- Bots can navigate toward objectives and interact with map objects rather than only walking around the map.
- The bot framework keeps separate workers for combat, weapon management, reviving, buildables, craftables, and map objectives.

### Combat and survival

The shared combat code is responsible for finding threats, deciding what to attack, aiming, firing, and deciding when the bot should move away from danger.

It includes:

- Enemy scanning and target prioritisation.
- Aim updates, target leading, and head/body targeting.
- Weapon selection based on the weapon available and target distance.
- Melee behaviour when an enemy gets too close.
- Grenade use and explosive-weapon safety checks.
- Reload and weapon-switch safeguards.
- Danger tracking and retreat/repositioning when the bot is under pressure.
- Special-enemy recognition, including **Brutus** on Mob of the Dead and the **Panzer Soldat** on Origins.
- Boss-specific target priorities and weapon preferences.

### Team support and match progression

The shared bot framework also includes:

- Reviving teammates when the game state allows it.
- Mob of the Dead Afterlife self-revive handling.
- Wall-buy purchases and weapon upgrades.
- Mystery Box interaction, including checking whether a weapon is worth taking.
- Perk-machine purchases.
- Pack-a-Punch support.
- Power-up collection.
- Opening available doors and clearing debris.
- Buildable/craftable part collection and station interaction.
- Map shield support on maps that use a shield.

The bot worker reapplies four perk identifiers after spawn/revival: `specialty_rof`, `specialty_deadshot`, `specialty_fastreload`, and `specialty_flakjacket`. Their exact in-game presentation depends on the game's perk definitions.

### Map-aware task system

The map modules are not all equally large. Origins and Mob of the Dead contain more involved objective logic than Nuketown. The map sections below describe what is actually present in the current scripts, not a promise that the entire Easter Egg is automatic.

---

## How the bot system works

### Bot lifecycle

When the bot script initializes, it reads `zm_bots`, creates that many test clients, marks them as bots, and starts the bot workers. Each bot runs its shared systems and the map-specific objective worker for the current map.

The main worker does not permanently lock a bot into one activity. It checks which tasks are currently available, pauses normal wandering while the bot is buying, reviving, building, crafting, or interacting with an objective, and returns to the normal loop when the task is finished or no longer valid.

### Objective priority

Map objectives are checked against live game state. For example, a bot should not attempt an Afterlife electrical panel if the panel does not exist yet, should not use an objective weapon it does not own, and should not continue holding a generator after the capture state has ended.

Some objectives require the host or a player to perform an earlier step first. The bot may wait until the relevant trigger, part, weapon, or quest stage becomes available.

### Bot command modes

| Mode | What the bots do |
|---|---|
| **Stay** | Keep their assigned position instead of deliberately roaming away. They still fight and can perform higher-priority objective, revive, purchase, or survival actions. |
| **Wander** | Move around nearby reachable areas while continuing their normal combat and support logic. |
| **Wander Further** | Use a wider roaming behaviour to explore farther from their starting position. |
| **Follow** | Use the player who issued the command as the team leader and move toward that player. |

The bot mode is shared by the bot group. When switching back to **Stay**, each bot records a new position for its stay behaviour.

---

# Map-by-map guide

Each map has its own script file. The map module is loaded alongside the shared bot scripts and checks the current map before running its map-specific logic.

## 1. Origins

<details>
<summary><strong>Origins — generators, shovel, staffs, Crazy Place, robot, Maxis Drone and shield</strong></summary>

**Game script:** `zm_tomb`  
**Module:** [`zm_bo2_bots_map_origins.gsc`](./zm_bo2_bots_map_origins.gsc)

Origins has one of the largest map modules in BO22. Its objective worker handles several parts of the map's progression and uses the map's native entities and triggers wherever possible.

### Shovel and dig sites

- Bots can check for a shovel and pursue an available shovel pickup.
- If all normal shovel pickups have already been taken, the Origins helper can create a private stock-style shovel pickup for a bot.
- Bots with a shovel can search available dig spots for Ice Staff parts when the snow-weather condition is active.
- The dig worker checks the dig spot's zone against the map's Ice Staff part data, so it does not simply dig every mound at random.
- Digging uses the map's normal interaction path so the game's own part counters and pickup state are updated.

The Golden Shovel, Golden Helmet, and Dig Site ESP are also available as separate mod-menu tools.

### Generator activation and capture

- Bots check which generators still need to be captured.
- They choose a reachable generator and use its real capture-start interaction.
- When a generator is contested or being captured, bots move into the generator's capture area and stay there.
- Generator defenders continue fighting zombies; the objective hold does not intentionally disable their combat worker.
- The worker recognises when a generator has become player-controlled and releases its objective claim.

The Origins module includes a capture-zone compatibility hook so living scripted bots are counted by the capture-progress logic.

### Staff parts, assembly and upgrades

The shared craftable system and Origins-specific objective code work together to handle staff progression.

- Bots can work on available map parts and staff-related pickups.
- The Origins objective worker can dig for Ice Staff pieces when the correct snow and staff-part conditions are present.
- Once a staff is assembled and held, bots can take it to its native charging trigger.
- The charging process relies on the game's normal nearby-zombie kill counter.
- Bots can collect an upgraded staff when its pickup trigger is available.
- When all upgraded staffs are ready, bots can place the correct staff into its matching robot-head plinth.

### Crazy Place and elemental staff puzzles

The Origins worker coordinates the shared gramophone and portal system, then selects the portal required by the unfinished staff objective. It uses the real portal pads and stock quest state rather than treating a successful use-button press as proof that the bot has arrived.

The supported staff puzzle interactions are:

| Staff | Puzzle work handled by the bot |
|---|---|
| **Wind** | Rotate each ceiling ring to its live target orientation and aim the staff through the smoke detectors toward the destination marker. |
| **Ice** | Read the current gem value, shoot the matching ceiling tile, then freeze each stone with the Water Staff and shatter it with a normal bullet weapon. |
| **Lightning** | Play the three piano chords in the stock order, then rotate the relay switches according to the live connection graph. |
| **Fire** | Keep the chamber sacrifice areas occupied while normal zombie kills feed the stock counter; ignite the correct church torches for the second puzzle. |

The crypt sequence is handled separately because its moving orb and rotating discs have their own stock state machine:

1. Shoot the gem with its matching elemental staff.
2. Rotate the outer discs until the live alignment requirement is satisfied.
3. Look at the correct exit-path start so the stock orb can leave the Crazy Place.
4. Find the orb model at its final crypt plinth and charge it with the same elemental staff.

The worker waits for the stock rotation lock and keeps a short-lived ownership claim while the orb sequence is running. It checks the real upgrade flag before releasing the puzzle.

### Giant robots and the Wind Staff part

The robot routine is deliberately conservative because a mistimed approach can put a bot beneath a moving foot.

1. It selects a walking robot whose hatch state is explicitly marked closed and whose matching left/right foot is valid.
2. It reserves that robot and its matching footprint so multiple bots do not all chase the same entry.
3. It stages outside the footprint, using a wider approach offset rather than standing directly beside the sole.
4. It aims at the live sole attached to the robot's actual hatch foot and uses a normal bullet weapon. It does not intentionally shoot the opposite foot or the robot body.
5. It watches the live hatch state. If the moving footprint gets too close, the bot cancels the approach and retreats.
6. Once the stock hatch opens, it follows the matching `trig_stomp_kill_<foot>_<robot>` trigger as it moves.
7. It only considers entry successful after the game reports that the bot has been teleported into that same robot head.

After entry, the stock in-head pickup/craftable logic remains responsible for collecting the Wind Staff part. The robot routine does not manually award the part or fake a quest flag.

**Timing note:** robot walking cycles, hatch state, trigger registration, navigation, and the live foot position all affect this task. The extra spacing and retreat check reduce avoidable stomps; they cannot guarantee survival in every robot cycle.

### Main Easter Egg progression

The main quest worker contains support for the later Little Lost Girl stages:

- **Robot-button stage:** use an actual fire-link button during the required three-robot round, then damage the floor target with the Beacon while its stock window is valid.
- **Zombie Blood plane:** wait until Zombie Blood is active, then shoot the moving biplane using its current position. The bot does not waste shots before the power-up condition is met.
- **Maxis Drone pickup:** approach the pilot's real quadrotor pickup and let the stock callback set the retrieved state.
- **Drone flight stages:** deploy only while the map has installed the relevant stock flight callback. The bot moves into the route's launch area before consuming the drone, and the stock drone AI follows the Panzer-hole or final-portal route.
- **One Inch Punch:** use the base punch against eligible Crazy Place zombies until the bot earns its own 20-soul count. Each player must collect their own stock tablet; the bot code no longer creates substitute tablets for teammates.
- **Portal souls:** keep the bot anchored inside the Crazy Place while the native step-7 kill callback counts the required zombie deaths. The chamber anchor pauses ordinary wandering and unrelated errands without intentionally turning off the combat worker.
- **Final release:** once the stock portal and drone conditions are complete, approach and activate the real final portal trigger.

These steps depend on each preceding stock quest stage. The bot worker does not directly set the main Easter Egg completion flags.

### Shield and map equipment

- The generic buildable/craftable workers handle available parts and crafting stations.
- The map module exposes the native `tomb_shield_zm` shield grant helper.
- The shared bot system also synchronises shield state and avoids interrupting another task while a bot is acquiring its shield.

### Origins mod-menu tools

The Origins menu currently includes:

- Give Shovel, Golden Shovel, and Golden Helmet.
- Dig Site ESP.
- Staff Progress Tracker.
- Maxis Drone recall/recovery.
- Basic, upgraded, and elemental One Inch Punch options.
- Robot Foot Warning.
- Tank status and tank call.
- Crazy Place teleport and return portals.
- Collect all shared parts and automatic shared-part collection.
- Force the four staff upgrades.
- Turn on all generators.
- Ignore mud slowdown.
- Host-only Little Lost Girl completion option. **This option can end the match.**

### Recent Origins reliability work

The latest source-level pass concentrated on progression failures that can look like successful actions but leave the stock quest unchanged:

- Explicitly check that a robot hatch is closed before selecting its foot.
- Refresh the matching moving-foot trigger while the robot walks, and verify the correct robot-head teleport.
- Use the orb's final plinth position for the crypt charge phase and wait for disc rotation to finish.
- Avoid repeatedly firing at a church torch that is already lit; retry after the stock flame window.
- Use an ordinary bullet weapon with available ammunition to break the frozen Ice Staff stones.
- Wait for the stock drone route callback and correct launch area before deploying the Maxis Drone.
- Remove the custom tablet-spawning workaround so each player must earn and pick up their own stock One Inch Punch tablet.
- Keep bots inside the Crazy Place during the portal-soul stage while their normal combat logic remains available.

**Important:** Origins is a multi-stage quest. Some steps require a specific staff, part, round, weather state, robot movement window, Zombie Blood, or stock trigger to be active. Treat the module as automated assistance for supported steps, not as a guarantee of a completely hands-free Easter Egg.

</details>

## 2. Mob of the Dead

<details>
<summary><strong>Mob of the Dead — Afterlife, Lightning Hands, soul catchers, Spoon, Warden and plane</strong></summary>

**Game script:** `zm_prison`  
**Module:** [`zm_bo2_bots_map_mob.gsc`](./zm_bo2_bots_map_mob.gsc)

Mob of the Dead has dedicated logic for the living world, Afterlife, the map's electrical interactions, side quests, and plane progression.

### Afterlife entry and return behaviour

The bot does not deliberately enter Afterlife just to immediately revive itself. The worker first checks whether a real, reachable Afterlife objective still needs to be completed.

- It searches for live Afterlife objectives and checks whether the bot can reach them.
- It uses the map's actual `zm_prison_afterlife_kill` unitrigger route to enter ghost mode.
- It allows the stock trigger manager and callback to handle the life consumption and Afterlife transition.
- It makes sure the bot has and equips **Lightning Hands** when needed.
- It keeps working on a valid electrical objective instead of returning to the body immediately.
- It only attempts to return/revive when there is no actionable Afterlife work left for that bot.

The logic also avoids having multiple bots repeatedly operate the same electrical panel or Nixie tube at once.

### Electrical panels and Afterlife objectives

The Afterlife worker checks and processes the map's real target types. Its dependency order includes:

- The introductory power interaction that opens the powered door.
- The active side of the Master Key pulley.
- The three generator panels.
- The Docks gate electrical interaction.
- The Laundry power switch and dryer progression.

The worker uses Lightning Hands to send the damage event expected by the stock Mob scripts. It does not rely on merely standing near a panel or pressing the ordinary use button when the stock objective requires an electrical hit.

### Soul catchers and Hell's Retriever

- Bots can spread across the three wolf-soul catcher volumes instead of all trying to charge the same one.
- Once the catchers are charged, a bot can move to the native Hell's Retriever pickup trigger.
- The Retriever is then used by later Mob sidequest logic.

### Spoon and Warden's Blundergat side quests

The module contains separate logic for the living world and Afterlife parts of the Spoon route.

- After the wolf catchers are charged, a living bot with the Retriever can attack the poster.
- In Afterlife, a bot with Lightning Hands can shock the Spoon target.
- A bot with the Retriever can then move to and interact with the Spoon pickup.
- For the Warden Blundergat prerequisite, an Afterlife bot can reveal the hidden skulls with Lightning Hands, allow the stock reveal cycle to run, and catch them with the real Retriever.

### Nixie tubes and audio logs

After the required sidequest prerequisites are complete:

- The bot can identify the valid three-digit Nixie code from the live quest data.
- It sends Lightning Hands pulses to the tubes that still need to rotate.
- It checks the live tube value between pulses to avoid over-rotating a tube.
- After the four codes are accepted, the bot follows the moving headphones through the six audio-log stop locations by walking into the stock touch volumes.

### Plane, bridge return and final fight

- Bots can board the plane when it is built, refuelled, and the map reports the required five fuel cans.
- Bots use the actual plane boarding trigger and reserve separate electric-chair triggers for the return route from the bridge.
- The Afterlife final-flight trigger is only attempted after the relevant quest prerequisites have been met.
- The final fight worker recognises the Arlington/Weasel team state, selects a valid opponent, chases when needed, and uses an available weapon or melee at close range.

Plane building and refuelling also use the shared craftable system. The Mod Menu has host-only shortcuts to build and refuel the plane without collecting every part/can.

### Mob of the Dead mod-menu tools

- Unlock Everything.
- Power all perk machines.
- Power the gondola.
- Open Afterlife doors.
- Send the gondola for free.
- Refill your Afterlife life; host can refill everyone's life.
- Afterlife Infinite Mana toggle.
- Spawn Brutus, spawn Brutus ignoring its normal limit, and kill Brutus.
- Give Spoon or Golden Spork.
- Host-only Build Plane and Refuel Plane shortcuts.

**Important:** Afterlife lives and mana are part of the objective's normal risk. The bot should enter only for an objective it can actually work on. Some later steps require previous sidequest items or the map's own progression flags.

</details>

## 3. TranZit

<details>
<summary><strong>TranZit — Maxis/Richtofen route, turbines, Jet Gun and EMP interactions</strong></summary>

**Game script:** `zm_transit`  
**Module:** [`zm_bo2_bots_map_tranzit.gsc`](./zm_bo2_bots_map_tranzit.gsc)

TranZit has route-aware quest assistance. Select the route with `zm_bot_quest_route`; when the DVAR is empty or unset, the module defaults to **Maxis**.

### Maxis route

The script supports the turbine/tower progression logic:

- When a bot has a turbine and the quest needs one, it can deploy the turbine at the tower volume.
- The first two turbine placements are handled as separate placements.
- Later, when the route reaches the Screecher-light stage, bots can deploy turbines in two different valid light zones.
- After both turbines have powered the tower stage, the worker can hold position at the tower volume to attract the Avogadro into the required area.
- The Maxis branch does not waste EMP grenades on the Avogadro step; that step is based on the powered turbines and the Avogadro touching the tower volume.

### Richtofen route

The Richtofen branch has separate logic:

- If the bot owns the Jet Gun and the tower-overheat stage is still incomplete, it moves to the correct tower volume and fires the Jet Gun until its heat reaches the required state or the task times out.
- During the tower-kill counter stage, bots can hold the required tower volume while their normal combat loop kills zombies.
- During the Screecher safety-light stage, bots with an EMP grenade can move to an unfinished light zone and throw the EMP so the native quest handler receives the event.

### Shield support

TranZit uses the stock `riotshield_zm` shield grant helper when a bot needs to acquire or replace its shield.

### TranZit mod-menu tools

The TranZit menu can use the stock buildable system to:

- Build and activate the Power Switch.
- Build the Turbine and Zombie Shield.
- Build the Jet Gun, Turret, and Electric Trap.
- Build Bus Cattle Catcher, Bus Hatch, Diner Hatch, and Bus Ladder.
- Build Pack-a-Punch.
- Build the Navcard Table.

The menu's buildable action calls the map's buildable helpers and removes the loose pieces through the stock buildable system. Power activation uses the map's native switch trigger.

</details>

## 4. Die Rise

<details>
<summary><strong>Die Rise — elevators, dragon puzzle, lion balls, Trample Steam and Sliquifier</strong></summary>

**Game script:** `zm_highrise`  
**Module:** [`zm_bo2_bots_map_die_rise.gsc`](./zm_bo2_bots_map_die_rise.gsc)

Die Rise contains dedicated support for parts of both the **Maxis** and **Richtofen** quest routes.

### Tower / Tazer Knuckles step

- The bot reads the live next-leg index from the map's wind-order array.
- It finds the exact next tower leg trigger.
- It equips Tazer Knuckles, upgraded Tazer Knuckles, or an already-equipped supported equivalent.
- It moves onto the required touch trigger and waits for the map's own quest index to advance.

This is a physical trigger step; simply pressing use would not activate the stock watcher.

### Above the Dragon: elevators

- The worker recognises that the four elevator triggers must be activated together.
- It attempts the compatibility helper for the four trigger positions.
- If that is not available on the current build, it assigns bot slots to the individual elevator triggers and holds them until the stock flags are active.

### Dragon-symbol puzzle

- The four trigger order is randomized by the map.
- The bot tests the possible trigger permutations.
- After each touch, it checks the live puzzle index to see whether the symbol was accepted.
- A failed sequence is abandoned and the next order is tried.

### Dragon / lion-ball stages

The map worker also contains logic for:

- Shooting the two dragon-tail balls with a supported sniper weapon when the SLB step requires real sniper damage.
- Picking up the lion balls through their stock pickup triggers and placing them through the map's placement triggers.
- Deploying Trample Steam / spring pads at the map's relevant lion or ghoul locations when the bot has the equipment.
- Using the Sliquifier on the Richtofen sphere stage.
- Holding bots in the Maxis corpse-room volume while normal combat produces the required corpse events.
- Using the upgraded Ballistic Knife on the corpse-room stage when the map reaches that step.

### Die Rise mod-menu tools

- Activate the Power Switch.
- Build Trample Steam.
- Build the Sliquifier.
- Build Escape Pod Keys.
- Build the Elevator Control Key.
- Build the Navcard Table.
- Call all elevators to their first stop.

</details>

## 5. Buried

<details>
<summary><strong>Buried — tower routes, Wisp, Time Bomb, lantern, maze/light board and fountain</strong></summary>

**Game script:** `zm_buried`  
**Module:** [`zm_bo2_bots_map_buried.gsc`](./zm_bo2_bots_map_buried.gsc)

Buried has a stage-aware quest worker. It reads the current quest stage and selects the action that belongs to that stage instead of trying to perform every interaction at once.

### Tunnel signs and tower route

- When the quest reaches the tunnel-sign step, bots choose the signs matching the tower route that has actually been built.
- The worker selects a supported melee weapon such as Tazer Knuckles or a Bowie Knife.
- It moves to the correct sign and performs the required melee hits so the stock watcher can record the activation.

### Mined Games amplifiers

- During the amplifier stage, bots search for unfinished amplifier entities.
- If they own the Slow Gun, they equip it and fire at the amplifier.
- The worker waits for the native amplifier state to change instead of forcing the quest-completion flag.

### Ghost lantern and oil-lamp charge

- Bots can move to the moving ghost lantern's real pickup trigger.
- When the oil lamp generator area is active and the lantern is not charged, bots can hold position in the generator area while fighting zombies. The map's normal kill events charge the lamp.

### Maxis Wisp and Time Bomb

The module includes Maxis-route support for the Wisp/Time Bomb stages:

- Follow the live Wisp during the relevant stage.
- Where the required Time Bomb is available, save the unfinished Wisp state with the Time Bomb.
- At the later Time Bomb stage, use the detonator to restore the saved state through the native callback.

### Richtofen Time Bomb stage

The Richtofen branch has a separate flow:

- Place a Time Bomb in the map's valid Time Bomb volume.
- Move the required players into that volume for the all-player check.
- When the stock state reports that the players are positioned, use the detonator.
- During the timed corpse search, move to distinct corpse unitriggers and search them until the native callback finds the item.

### Inverted Pyramid puzzle

- On Maxis, the worker interacts with the live light-board start and then the currently requested light button.
- On Richtofen, it finds the unflipped maze levers and activates them in the order exposed by the stock map data.

### Fountain target stage

- The worker starts the fountain through its real interaction.
- It finds the spawned target models and fires at them while the target window is active.
- The bot uses real weapon fire rather than marking the stage complete by writing a flag.

### Buried mod-menu tools

- Activate the Power Switch.
- Open Leroy's cell.
- Build Turbine, Trample Steam, Subwoofer, Head Chopper, and Cell Key.
- Build the Navcard Table.
- Build the Maxis Tower or Richtofen Tower.

</details>

## 6. Nuketown Zombies

<details>
<summary><strong>Nuketown Zombies — meteor counter, clock power-up and mannequin interactions</strong></summary>

**Game script:** `zm_nuked`  
**Module:** [`zm_bo2_bots_map_nuketown.gsc`](./zm_bo2_bots_map_nuketown.gsc)

Nuketown has a smaller, focused map module. It supports the meteor/mannequin progression interactions:

- The bot reads the map's meteor counter and targets the corresponding meteor/bear interaction location.
- It uses the map's real use interaction so the stock counter can advance.
- When the meteor count reaches three, the bot can shoot the destructible male mannequins while the map's music-override state allows it.
- During the relevant population-count state, the bot can move to the clock power-up location.

This module focuses on these map-specific tasks. It is not a full Nuketown Easter Egg automation system.

</details>

---

## In-game mod menu

The mod menu is optional and is loaded from `zm_modmenu.gsc`. The main menu contains general categories, plus a map-specific category when the current map supports one. The **Players Menu** is created for the host.

The menu currently displays **8 entries at once** and scrolls through longer lists. Each option uses a single text row; the footer shows the selected entry number and the menu's total number of entries.

### Personal Mods

Player-level options include:

- God Mode and Noclip.
- Spectator / Free Camera and a return-to-camera option.
- Jetpack, Super Jump, and Auto-Bhop.
- Vampire Mode (heal from points) and Super Health.
- Move-to-refill-ammo, Magic Bullets, and Max Movespeed.
- Zombies Ignore Me, Invisibility, and Third Person.
- FOV 120 or the default FOV.
- Add 100,000 Points and Infinite Points.
- Save Position, Load Position, Teleport to Crosshair, and Suicide.

These are personal player controls. They do not change how the bot objective worker is coded.

### Weapon Mods

Weapon options include:

- Infinite Ammo toggle.
- Pack-a-Punch the current weapon or all carried weapons.
- Refill the current weapon or all weapons.
- Give selected loaded weapons, equipment, and map-registered weapon variants.
- Give All Perks or Remove All Perks.
- Drop the current weapon.
- A More Guns (PaP) sub-menu for additional weapon choices.

The map-weapon list is filtered against the current map's registered weapons. A weapon that is not loaded by the current map should not be added as a menu option.

### Map Weapons

This category is built dynamically. It only appears when the current map has supported entries. It is not intended to show every weapon from every Zombies map in every match.

### Spawns & Lobby

Options include:

- Turn on power and open doors.
- Spawn available power-ups: Max Ammo, Insta-Kill, Double Points, Nuke, Carpenter, Fire Sale, Free Perk, Death Machine, and Zombie Blood.
- Skip one round or jump to rounds 10, 25, 50, and 100.
- Set game speed to slow motion, fast, or normal.
- Set low or normal gravity.
- Restart the map and end the game (host-only).

Some actions require that the relevant map system or power-up is available.

### Zombie Manipulation

Options include:

- Kill, explode, or burn all zombies.
- Teleport zombies to the player or to the crosshair.
- Zombie Magnet toggle.
- Send zombies to the moon or launch them upward.
- Freeze all zombies.
- Set zombie movement to sprint, run, walk, or default.
- Insta-Kill Aura toggle.
- Delete all zombies or add 24 zombies to the round.

These controls can significantly change the match. Use them carefully, especially during a quest stage that depends on specific zombies or normal spawn behaviour.

### Aimbot & ESP

Options include:

- Aimbot toggle.
- Choose Head or Chest as the aim target.
- Silent Aim toggle and narrow, wide, or 360-degree FOV settings.
- Zombie ESP dots.
- Parts ESP for supported map craftable/buildable part registries.
- ESP dot size and colour controls.

Parts ESP reads the live craftable/buildable registries and marks available spawned part models. It is a locator; it does not pick up parts by itself.

### Origins Tools

Only shown on Origins. See [Origins](#1-origins) for detailed descriptions. Tools include shovel and helmet grants, Dig Site ESP, staff progress, drone recovery, One Inch Punch options, robot warnings, tank status/call, Crazy Place and portal teleports, shared-part collection, staff upgrades, generator activation, and mud slowdown control.

The host-only **Complete Little Lost Girl** action requests the stock ending sequence and can end the match.

### Mob of the Dead Tools

Only shown on Mob of the Dead. Includes power and gondola controls, Afterlife doors/lives/mana, Brutus spawn/kill actions, Spoon/Golden Spork grants, and host-only plane build/refuel shortcuts.

### TranZit Tools

Only shown on TranZit. Uses the stock buildable system for the Power Switch, Turbine, Zombie Shield, Jet Gun, Turret, Electric Trap, bus attachments, Pack-a-Punch, and Navcard Table.

### Die Rise Tools

Only shown on Die Rise. Includes the power switch, Trample Steam, Sliquifier, Escape Pod Keys, Elevator Control Key, Navcard Table, and elevator dispatch.

### Buried Tools

Only shown on Buried. Includes the power switch, Leroy's cell, map buildables, Navcard Table, and Maxis/Richtofen tower buildables.

### Players Menu (host only)

The host can select a player and perform actions such as:

- Grant or revoke mod-menu access.
- Toggle God Mode for the selected player.
- Give all perks or 100,000 points.
- Revive, teleport to, or bring the selected player to the host.
- Freeze, launch, or kill a selected player.

Use player-management actions only in a session where you have permission to manage the other players.

---

## Controls

### Bot controls

These are the **number-row keys**, not F6/F7:

| Keyboard key | Action |
|---|---|
| **3** | Teleport the whole bot group to your position. |
| **4** | Cycle the bot command mode. |

**Key 3 — Teleport bots**

- Moves the bot group near your current position using small offsets so they do not all occupy exactly the same point.
- You must be standing on the ground when you press it.
- If you are airborne, the script prints a warning and does not teleport the group.

**Key 4 — Change bot mode**

Each press cycles through:

```text
Stay → Wander → Wander Further → Follow → Stay
```

The current mode is printed on screen. The mode applies to the bot group, not just one bot.

> The script listens for Action Slot 3 for teleport and Action Slot 4 for mode cycling. In the documented setup those are mapped to the keyboard number keys **3** and **4**. If your own key bindings have been changed, bind those Action Slot commands to the same number keys.

### Mod-menu controls

| Input | Action |
|---|---|
| **Aim + Melee together** | Open the menu. |
| **Action Slot 1** | Scroll up. |
| **Action Slot 2** | Scroll down. |
| **Jump** | Select the highlighted option. |
| **Melee** | Go back; from the main menu it closes the menu. |

The menu shows eight rows at once. Use the up/down controls to move the highlight through every option in longer menus.

### Spectator / Free Camera

Spectator Mode is also available under Personal Mods. The script comment includes an optional `bind g "+actionslot 3"` binding for entering/leaving spectator mode. Be aware that Action Slot 3 is also the bot-teleport command in the bot script; if that binding causes both actions to fire on your setup, use a different key/action binding for spectator mode.

---

## Installation

### Requirements

- Call of Duty: Black Ops II.
- Plutonium T6.
- A Zombies map supported by BO22.
- Access to the Plutonium T6 script storage folder.

### Step 1 — Open the script directory

Press **Win + R**, paste this path, and press Enter:

```text
%localappdata%\Plutonium\storage\t6\scripts\zm\
```

If the `scripts` or `zm` folder does not exist, create it.

### Step 2 — Download the repository

On GitHub, click **Code → Download ZIP** and extract the archive.

Repository: [github.com/Tenslaster/bo22](https://github.com/Tenslaster/bo22)

### Step 3 — Copy the eight core GSC files and optional menu

Copy the eight core bot files and optional menu shown below into the `scripts\zm` directory. Do not rename them.

```text
%localappdata%\
└── Plutonium\
    └── storage\
        └── t6\
            └── scripts\
                └── zm\
                    ├── zm_bo2_bots.gsc
                    ├── zm_bo2_bots_combat.gsc
                    ├── zm_bo2_bots_map_buried.gsc
                    ├── zm_bo2_bots_map_die_rise.gsc
                    ├── zm_bo2_bots_map_mob.gsc
                    ├── zm_bo2_bots_map_nuketown.gsc
                    ├── zm_bo2_bots_map_origins.gsc
                    ├── zm_bo2_bots_map_tranzit.gsc
                    └── zm_modmenu.gsc
```

**Do not install only `zm_bo2_bots.gsc`.** The main bot script depends on the combat file and all six map modules. Those eight core files must be in the same folder and should come from the same repository revision.

`zm_modmenu.gsc` is optional for bot-only use and required for the in-game menu.

### Step 4 — Start the game

1. Launch Plutonium T6.
2. Start Black Ops II Zombies.
3. Start one of the supported maps.
4. Wait for the map to finish loading and the bot script to initialize.
5. Check the console for a GSC compiler error if bots or the menu do not appear.

After replacing script files, restart the match so the game loads the updated files.

---

## Configuration

The current bot configuration uses these DVARs:

| DVAR | Purpose | Default |
|---|---|---|
| `zm_bots` | Number of bots created during initialization. | `7` |
| `zm_bot_quest_route` | Selects TranZit's bot quest branch. | `maxis` |

### Changing the bot count

Set `zm_bots` before the bot initialization runs. For example, to create four bots:

```text
set zm_bots 4
```

The script reads this value during initialization. Changing it after the bot group has already spawned does not automatically add or remove bots from the current match.

### Choosing the TranZit route

The TranZit module supports:

```text
set zm_bot_quest_route maxis
```

or:

```text
set zm_bot_quest_route richtofen
```

If the DVAR is empty or unset, the module uses the Maxis route.

---

## Repository files

| File | Responsibility |
|---|---|
| [`zm_bo2_bots.gsc`](./zm_bo2_bots.gsc) | Main bot framework: initialization, spawning, movement, purchases, revives, weapon management, shared objective helpers, buildable/craftable tasks, and bot command controls. |
| [`zm_bo2_bots_combat.gsc`](./zm_bo2_bots_combat.gsc) | Combat AI: threat awareness, target selection, aiming, shooting, melee, grenades, weapon safety, retreat, and special-enemy combat. |
| [`zm_bo2_bots_map_origins.gsc`](./zm_bo2_bots_map_origins.gsc) | Origins generators, shovel/dig tasks, staff puzzles, Crazy Place, crypt gems, robot Wind Staff part, Maxis Drone and main quest steps. |
| [`zm_bo2_bots_map_mob.gsc`](./zm_bo2_bots_map_mob.gsc) | Mob of the Dead Afterlife, Lightning Hands objectives, soul catchers, Retriever, Spoon/Warden side quests, Nixie/audio logs, plane boarding and final fight. |
| [`zm_bo2_bots_map_tranzit.gsc`](./zm_bo2_bots_map_tranzit.gsc) | TranZit Maxis/Richtofen branch-specific tower, turbine, Jet Gun and EMP tasks. |
| [`zm_bo2_bots_map_die_rise.gsc`](./zm_bo2_bots_map_die_rise.gsc) | Die Rise tower, Above the Dragon, elevator, dragon puzzle, lion-ball, spring-pad, Sliquifier and corpse-room tasks. |
| [`zm_bo2_bots_map_buried.gsc`](./zm_bo2_bots_map_buried.gsc) | Buried tunnel signs, amplifiers, lantern, Wisp/Time Bomb, TPO, Inverted Pyramid puzzle and Fountain target tasks. |
| [`zm_bo2_bots_map_nuketown.gsc`](./zm_bo2_bots_map_nuketown.gsc) | Nuketown meteor counter, clock power-up positioning and mannequin interactions. |
| [`zm_modmenu.gsc`](./zm_modmenu.gsc) | Optional in-game mod menu, general player/weapon/lobby/zombie tools, ESP and map-specific host utilities. |

---

## Validation status and known limitations

The latest Origins changes have received a source-level review against the stock Plutonium T6 Origins scripts and static structural checks. **They have not been confirmed by a Plutonium GSC compile or a complete live Origins match in this update.** Treat live testing as the final verification step.

- Map objectives are conditional. If a required weapon, item, part, trigger, round, weather condition, or quest stage is missing, the bot may wait or skip that objective.
- A bot may need a reachable navigation path. A task can fail if a player blocks the route, the bot is trapped, or the map geometry prevents pathfinding.
- Some Easter Egg stages require player-specific items or states. A shared squad can make progress, but not every step is automatically completed for every player.
- The host-only menu actions are intentionally unavailable to clients without host permissions.
- The menu's **Complete Little Lost Girl** option requests the ending sequence and can finish the match.
- The project uses stock game callbacks where possible. If a stock function is not available in the loaded Plutonium build or map, the compiler can report an unresolved external or the action can be unavailable.
- GSC gameplay and compilation have to be validated in the actual target game. Static checks can catch structural problems but cannot prove that every engine call, trigger, animation, or quest stage works at runtime.
- Origins tasks involving robot feet, moving drone routes, crypt orbs, and player-specific tablets are especially sensitive to live entity timing and should be tested in an actual match.
- A GitHub commit alone does not prove that a script compiles or that an objective works in every match.

---

## Troubleshooting

### Bots do not spawn

1. Confirm that `zm_bo2_bots.gsc` is in `storage\t6\scripts\zm\`.
2. Confirm that the combat file and all six map files are in the same folder; these eight core files are required.
3. Check that `zm_bots` is not set to `0`.
4. Restart the Zombies match after copying the files.
5. Check the Plutonium console for the first GSC error.

### Bots spawn but stand still

- Press **4** to cycle from Stay to Wander or Follow.
- Check whether a bot is already assigned to a revive, build, craft, generator, or map objective.
- Check whether the bot can find a navigation path to its current destination.
- On Origins, a generator defender may intentionally remain in the capture zone while fighting.

### Number keys 3 and 4 do nothing

- Confirm that your keyboard number-row **3** is bound to Action Slot 3 and **4** to Action Slot 4.
- Key 3 is the teleport command; key 4 changes the bot mode.
- Stand on the ground before using key 3.
- Avoid testing both keys while another menu or binding is intercepting the same action slot.

### The mod menu does not open

- Confirm that `zm_modmenu.gsc` is installed.
- Use Aim + Melee together to open it.
- The host is automatically granted access. If you are not the host, the host must grant menu access.
- Check the console for a script compilation error.

### I can only see part of the mod menu

The current menu is configured for **eight visible option rows**. Longer submenus still scroll. If the menu only renders fewer rows, confirm that you copied the latest `zm_modmenu.gsc` and restarted the match.

### Origins robot-foot or Wind Staff part does not progress

- Check that a giant robot is walking and has a closed hatch on the matching foot.
- Confirm that the bot has a normal bullet weapon with ammunition.
- Watch whether the bot reaches the outer staging area, shoots the sole, retreats, or follows the opened-foot trigger.
- If the hatch opens but the bot is not teleported into the robot head, capture the robot ID/foot and the bot's position when it misses the trigger.

### Origins crypt orb or staff puzzle does not progress

- Confirm that the corresponding staff is equipped and the correct puzzle stage has started.
- For crypt gems, report which element is being charged and whether the orb has reached its final plinth.
- For the Fire Staff torches, check whether the correct torch is already burning or has gone out before the retry.
- Include the current round and any visible stock quest flag/state if available.

### A map objective does not progress

- Check the map and quest stage.
- Verify the bot owns the required weapon or equipment.
- Check whether the target trigger or part has spawned.
- Some tasks require Zombie Blood, snow weather, a specific staff, a Time Bomb, a sniper weapon, or another stage-specific condition.
- Confirm the bot is not stuck behind debris, a closed door, or another player.
- Provide the exact objective name and what the bot does instead of guessing which quest state failed.

### Unresolved external / script compiler error

An error such as:

```text
Unresolved external: "function_name" with N parameters
```

means the target GSC compiler could not resolve a referenced function with that signature in the loaded script environment.

When reporting it, include:

- Full error text.
- Map name.
- Script file and line number.
- The complete function name and parameter count.
- Whether the error happens at map load or after using a menu/objective option.

Do not fix unresolved externals by randomly changing function names or parameter counts. Verify the function against the stock script for the exact map/runtime first.

---

## Development guidelines

To keep the project maintainable:

- Put shared bot systems in `zm_bo2_bots.gsc`.
- Put combat and threat logic in `zm_bo2_bots_combat.gsc`.
- Put map-only code in the matching `zm_bo2_bots_map_*.gsc` file.
- Keep map-specific function references behind runtime checks when the function's script is not loaded on every map.
- Prefer the stock trigger, callback, and interaction flow over manually setting quest-completion flags.
- Preserve the existing task workers when changing one objective; avoid broad text replacements that remove unrelated bot behaviour.
- Test each change on the map that loads the edited module.
- For Origins, test each stage independently: robot hatch/entry, all four staff puzzles, crypt orb charge, Maxis Drone route, individual punch tablet, chamber soul hold, and final portal.
- Record compiler output separately from runtime behaviour; a script that parses can still fail when a stock trigger or entity appears in a different state.

## Reporting a bug

A useful report should include:

1. The map and current quest stage.
2. Whether you are host.
3. How many bots are in the match.
4. The bot mode (Stay, Wander, Wander Further, or Follow).
5. The exact action you expected the bot to take.
6. What the bot actually did.
7. The full Plutonium compiler/console error, if one appeared.
8. The commit or date of the GSC files you installed.

For objective issues, a short video or screenshot of the bot, target, and quest state can help identify whether the problem is navigation, target detection, inventory, or the stock map trigger.

---

## Disclaimer

BO22 is an independent community scripting project. It is not affiliated with, sponsored by, or endorsed by Activision or Plutonium. Black Ops II, Zombies, and Plutonium are trademarks or property of their respective owners.

The scripts are provided as source code for custom/private Zombies sessions. Features may behave differently depending on the game build, map state, script load order, host authority, and available stock GSC functions.

---

<div align="center">

**BO22**  
Black Ops II Zombies · Plutonium T6 · GSC

[GitHub Repository](https://github.com/Tenslaster/bo22) · [Report an Issue](https://github.com/Tenslaster/bo22/issues)

</div>
