// ============================================================================
//  ULTIMATE ZM MOD MENU  -  Plutonium T6 (Black Ops II Zombies)  -  v4.0
//  Install: %localappdata%\Plutonium\storage\t6\scripts\zm\zm_modmenu.gsc
//
//  Controls (menu closed):  AIM + MELEE ............ open menu
//  Controls (menu open)  :  Action Slot 1 / 2 ...... scroll up / down
//                           JUMP .................... select
//                           MELEE ................... back / close
//  Free-roam: the boundary toggle stops the stock player-volume / kill-brush monitor.
//  Noclip: Attack forward, ADS backward, Frag up, Tactical down.
//
//  Maps: TranZit / Nuketown / Die Rise / Mob of the Dead / Buried / Origins
//  Perk actions include physical vending machines and each map's registered
//  random-perk pool (including Origins Wunderfizz-only perks).
// ============================================================================

#include maps\mp\_utility;
#include common_scripts\utility;
#include maps\mp\zombies\_zm_utility;

init()
{
    level.mmFrozen = false;
    level thread MM_OnPlayerConnect();
}

MM_OnPlayerConnect()
{
    level endon("end_game");
    for(;;)
    {
        level waittill("connected", player);
        player thread MM_OnPlayerSpawned();
    }
}

MM_OnPlayerSpawned()
{
    self endon("disconnect");
    level endon("end_game");

    self waittill("spawned_player");

    if(level.script == "zm_tomb" && !isDefined(level.mmOriginsPianoTrackerStarted))
    {
        level.mmOriginsPianoTrackerStarted = true;
        level thread MM_OriginsPianoChordTracker();
    }

    if(self isHost())
        self.hasMenu = true;

    firstSpawn = true;
    for(;;)
    {
        if(isDefined(self.hasMenu) && self.hasMenu)
        {
            self MM_GrantMenu();
            self MM_ApplySpawnSettings();
            if(firstSpawn)
            {
                self iprintlnbold("^2ULTIMATE ZM MENU v4.0 LOADED");
                self iprintln("^7Aim + Melee: open | Slot 1/2: scroll | Jump: select | Melee: back");
                firstSpawn = false;
            }
        }
        self waittill("spawned_player");
    }
}

// ============================================================================
//  MENU ACCESS
// ============================================================================

MM_GrantMenu()
{
    self.hasMenu = true;
    if(isDefined(self.menuSetup) && self.menuSetup)
        return;

    self.menuSetup = true;
    self SetupMenu();
    self thread MenuInput();
}

MM_RevokeMenu()
{
    self.hasMenu = false;
    self.menuSetup = false;
    self.menuOpen = false;
    self notify("stop_menu_input");
    self MM_DestroyMenuHud();
}

// ============================================================================
//  MENU FRAMEWORK
// ============================================================================

SetupMenu()
{
    self MM_DestroyMenuHud();

    self.menuOpts = [];
    self.menuParents = [];
    self.menuCursors = [];
    self.menuOpen = false;
    self.menuCursor = 0;
    self.currentMenu = "main";
    self.selectedPlayer = undefined;
    if(!isDefined(self.mmToggle))
        self.mmToggle = [];

    self BuildMenuStructure();
}

// HUD elements only exist while the menu is open (ZM already uses many HUD
// elements per player, so this avoids hitting the engine limit).
MM_CreateMenuHud()
{
    self MM_DestroyMenuHud();

    self.mmRowText = [];
    self.mmTitleText = undefined;
    self.mmFooterText = undefined;

    self.menuBg = newClientHudElem(self);
    self.menuBg.horzAlign = "left";
    self.menuBg.vertAlign = "top";
    self.menuBg.alignX = "left";
    self.menuBg.alignY = "top";
    self.menuBg.x = 12;
    self.menuBg.y = 80;
    self.menuBg.sort = 1000;
    self.menuBg.foreground = true;
    self.menuBg.hideWhenInMenu = true;
    self.menuBg.alpha = 0.6;
    self.menuBg.color = (0, 0, 0);
    self.menuBg setShader("white", 320, 235);

    self.menuTitle = self MM_NewText(22, 86, 1.3);
    self.menuFooter = self MM_NewText(22, 292, 1.1);

    // Keep the HUD pool small and predictable. Some Plutonium HUD layouts
    // only render the first few client text elements reliably; the menu uses
    // an eight-row viewport and scrolls through every option.
    self.menuRows = [];
    for(i = 0; i < 8; i++)
        self.menuRows[i] = self MM_NewText(22, 112 + (i * 19), 1.25);
}

MM_NewText(px, py, scale)
{
    h = newClientHudElem(self);
    h.horzAlign = "left";
    h.vertAlign = "top";
    h.alignX = "left";
    h.alignY = "top";
    h.x = px;
    h.y = py;
    h.font = "objective";
    h.fontScale = scale;
    h.sort = 1001;
    h.foreground = true;
    h.hideWhenInMenu = true;
    h.alpha = 1;
    h.color = (1, 1, 1);
    return h;
}

MM_DestroyMenuHud()
{
    if(isDefined(self.menuBg))
        self.menuBg destroy();
    if(isDefined(self.menuTitle))
        self.menuTitle destroy();
    if(isDefined(self.menuFooter))
        self.menuFooter destroy();
    if(isDefined(self.menuRows))
    {
        rows = self.menuRows;
        foreach(row in rows)
        {
            if(isDefined(row))
                row destroy();
        }
    }
    self.menuBg = undefined;
    self.menuTitle = undefined;
    self.menuFooter = undefined;
    self.menuRows = undefined;
}

addMenuOpt(menuName, text, func, arg, arg2)
{
    if(!isDefined(self.menuOpts[menuName]))
        self.menuOpts[menuName] = [];

    index = self.menuOpts[menuName].size;
    opt = spawnStruct();
    opt.text = text;
    opt.func = func;
    opt.arg = arg;
    opt.arg2 = arg2;
    opt.key = undefined;
    self.menuOpts[menuName][index] = opt;
}

// Menu entry that opens a sub menu and remembers its parent for "back".
addSubMenu(parent, text, child)
{
    self addMenuOpt(parent, text, ::SwitchMenu, child);
    self.menuParents[child] = parent;
}

// Menu entry that shows an [ON]/[OFF] tag. "key" must match the key used by the toggle function.
addToggleOpt(menuName, text, func, key)
{
    self addMenuOpt(menuName, text, func);
    last = self.menuOpts[menuName].size - 1;
    self.menuOpts[menuName][last].key = key;
}

// Only adds a weapon if the map actually has it registered.
MM_AddWeaponOpt(menuName, text, weap)
{
    if(MM_WeaponKnown(weap))
        self addMenuOpt(menuName, text, ::GiveWeap, weap);
}

MM_AddDropOpt(text, type)
{
    if(isDefined(level.zombie_powerups) && isDefined(level.zombie_powerups[type]))
        self addMenuOpt("lobby", text, ::SpawnDrop, type);
}

SwitchMenu(menuName)
{
    self MM_GoTo(menuName, false);
}

MM_GoTo(menuName, restoreCursor)
{
    self.menuCursors[self.currentMenu] = self.menuCursor;
    self.currentMenu = menuName;

    if(menuName == "players" && self isHost())
        self MM_BuildPlayersList();

    self.menuCursor = 0;
    if(restoreCursor && isDefined(self.menuCursors[menuName]))
        self.menuCursor = self.menuCursors[menuName];

    self MM_ClampCursor();
    self UpdateMenuUI();
}

MM_ClampCursor()
{
    total = 0;
    if(isDefined(self.menuOpts[self.currentMenu]))
        total = self.menuOpts[self.currentMenu].size;

    if(self.menuCursor >= total)
        self.menuCursor = total - 1;
    if(self.menuCursor < 0)
        self.menuCursor = 0;
}

MenuBack()
{
    if(self.currentMenu == "main")
    {
        self MM_CloseMenu();
        return;
    }
    parent = self.menuParents[self.currentMenu];
    if(!isDefined(parent))
        parent = "main";
    self MM_GoTo(parent, true);
}

MM_OpenMenu()
{
    self.menuOpen = true;

    // The open gesture (Aim + Melee) must not also count as "back" / "select".
    t = getTime();
    if(!isDefined(self.mmGate))
        self.mmGate = [];
    self.mmGate["back"] = t;
    self.mmGate["sel"] = t;
    self.mmBackArmed = false;

    self MM_CreateMenuHud();
    self UpdateMenuUI();
}

MM_CloseMenu()
{
    self.menuOpen = false;
    self MM_DestroyMenuHud();
}

MenuScroll(dir)
{
    total = 0;
    if(isDefined(self.menuOpts[self.currentMenu]))
        total = self.menuOpts[self.currentMenu].size;
    if(total < 1)
        return;

    self.menuCursor += dir;
    if(self.menuCursor < 0)
        self.menuCursor = total - 1;
    if(self.menuCursor >= total)
        self.menuCursor = 0;
    self UpdateMenuUI();
}

MenuSelect()
{
    if(!isDefined(self.menuOpts[self.currentMenu]))
        return;
    opt = self.menuOpts[self.currentMenu][self.menuCursor];
    if(!isDefined(opt))
        return;

    if(isDefined(opt.arg2))
        self thread [[opt.func]](opt.arg, opt.arg2);
    else if(isDefined(opt.arg))
        self thread [[opt.func]](opt.arg);
    else
        self thread [[opt.func]]();

    // Give toggles a moment to flip, then refresh the [ON]/[OFF] tags.
    self thread MM_DelayedRefresh();
}

MM_DelayedRefresh()
{
    self endon("disconnect");
    wait 0.1;
    if(isDefined(self.menuOpen) && self.menuOpen)
        self UpdateMenuUI();
}

MM_WaitRelease()
{
    timeout = 0;
    while((self meleeButtonPressed() || self adsButtonPressed()) && timeout < 40)
    {
        wait 0.025;
        timeout++;
    }
}

// Debounce shared by the event path and the polling path, so one press can
// never trigger an action twice.
MM_Gate(key, ms)
{
    if(!isDefined(self.mmGate))
        self.mmGate = [];

    now = getTime();
    if(isDefined(self.mmGate[key]) && (now - self.mmGate[key]) < ms)
        return false;

    self.mmGate[key] = now;
    return true;
}

MM_InputUp(ms)
{
    if(self MM_Gate("up", ms))
        self MenuScroll(-1);
}

MM_InputDown(ms)
{
    if(self MM_Gate("down", ms))
        self MenuScroll(1);
}

MM_InputSelect(ms)
{
    if(self MM_Gate("sel", ms))
    {
        self MenuSelect();
    }
}

MM_InputBack(ms)
{
    if(self MM_Gate("back", ms))
    {
        self.mmBackArmed = false;
        self MenuBack();
    }
}

// Button EVENTS never miss a quick tap. Polling a button state only sees the
// button if it is still down when the server runs its next frame, which is
// why a fast tap on 1 or 2 used to do nothing.
MM_InputListener(cmd, action)
{
    self endon("disconnect");
    self endon("stop_menu_input");

    for(;;)
    {
        self waittill(cmd);

        if(!isDefined(self.menuOpen) || !self.menuOpen)
            continue;

        if(action == "up")
            self MM_InputUp(40);
        else if(action == "down")
            self MM_InputDown(40);
        else if(action == "select")
            self MM_InputSelect(150);
        else if(action == "back")
            self MM_InputBack(300);
    }
}

MenuInput()
{
    self endon("disconnect");
    self endon("stop_menu_input");

    self.mmGate = [];
    self.mmBackArmed = true;

    self notifyOnPlayerCommand("mm_up", "+actionslot 1");
    self notifyOnPlayerCommand("mm_down", "+actionslot 2");
    self notifyOnPlayerCommand("mm_select", "+gostand");
    self notifyOnPlayerCommand("mm_back", "+melee");

    self thread MM_InputListener("mm_up", "up");
    self thread MM_InputListener("mm_down", "down");
    self thread MM_InputListener("mm_select", "select");
    self thread MM_InputListener("mm_back", "back");

    // The loop below is the fallback (and handles hold-to-repeat scrolling).
    upSince = 0;
    downSince = 0;

    for(;;)
    {
        wait 0.05;
        now = getTime();

        if(!self.menuOpen)
        {
            upSince = 0;
            downSince = 0;
            if(self adsButtonPressed() && self meleeButtonPressed())
            {
                if(!(self maps\mp\zombies\_zm_laststand::player_is_in_laststand()))
                    self MM_OpenMenu();
            }
            continue;
        }

        if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
        {
            self MM_CloseMenu();
            continue;
        }

        // Scroll: instant on press, then fast repeat after a short hold.
        if(self actionSlotOneButtonPressed())
        {
            if(upSince == 0)
                upSince = now;
            gap = 350;
            if((now - upSince) > 350)
                gap = 60;
            self MM_InputUp(gap);
        }
        else
            upSince = 0;

        if(self actionSlotTwoButtonPressed())
        {
            if(downSince == 0)
                downSince = now;
            gap = 350;
            if((now - downSince) > 350)
                gap = 60;
            self MM_InputDown(gap);
        }
        else
            downSince = 0;

        if(self jumpButtonPressed())
            self MM_InputSelect(500);

        // Back only fires after melee was released once (stops the open
        // gesture from instantly closing the menu again).
        if(self meleeButtonPressed())
        {
            if(self.mmBackArmed)
                self MM_InputBack(300);
        }
        else
            self.mmBackArmed = true;
    }
}

MM_MenuTitle(name)
{
    switch(name)
    {
        case "main":           return "MAIN MENU";
        case "freeroam":       return "FREE ROAM / NO DEATH BARRIERS";
        case "roamspots":      return "SAVED FREE-ROAM POSITIONS";
        case "movement":       return "MOVEMENT & FLIGHT";
        case "teleport":       return "TELEPORT & SAVED LOCATIONS";
        case "teleportslots":  return "THREE SAVED LOCATIONS";
        case "world":          return "WORLD & GAME CONTROL";
        case "allguns":        return "ALL REGISTERED MAP WEAPONS";
        case "powerups":       return "ALL REGISTERED POWERUPS";
        case "personal":       return "PERSONAL MODS";
        case "permaperks":     return "PERSISTENT UPGRADES / PERMA-PERKS";
        case "survival":       return "SURVIVAL & AUTOMATION";
        case "weapons":        return "WEAPON MODS";
        case "heavyweapons":   return "HEAVY / EXPLOSIVE ARSENAL";
        case "wonderweapons":  return "WONDER WEAPONS";
        case "mapweapons":     return "MAP WEAPONS";
        case "guns":           return "MORE GUNS";
        case "lobby":          return "SPAWNS & LOBBY";
        case "zombies":        return "ZOMBIE MANIPULATION";
        case "zspawn":         return "SPAWN ZOMBIE TYPES";
        case "zai":            return "ZOMBIE AI & HEALTH";
        case "zboss":          return "BOSSES & SPECIAL ENEMIES";
        case "zeffects":       return "ZOMBIE EFFECTS & CROWD TOOLS";
        case "vision":         return "AIMBOT & ESP";
        case "origins":        return "ORIGINS TOOLS";
        case "prison":         return "MOB OF THE DEAD TOOLS";
        case "transit":        return "TRANZIT TOOLS";
        case "highrise":       return "DIE RISE TOOLS";
        case "buried":         return "BURIED TOOLS";
        case "eetracker":      return "EASTER EGG TRACKER";
        case "players":        return "PLAYERS";
        case "player_actions": return "PLAYER ACTIONS";
    }
    return name;
}

UpdateMenuUI()
{
    if(!isDefined(self.menuOpen) || !self.menuOpen)
        return;
    if(!isDefined(self.menuRows) || !isDefined(self.menuTitle))
        return;

    opts = self.menuOpts[self.currentMenu];
    total = 0;
    if(isDefined(opts))
        total = opts.size;

    maxRows = 8;
    first = 0;
    if(total > maxRows)
    {
        first = self.menuCursor - 1;
        if(first < 0)
            first = 0;
        if(first > total - maxRows)
            first = total - maxRows;
    }

    title = "^2>> ^7" + MM_MenuTitle(self.currentMenu) + " ^2<<";
    if(self.currentMenu == "player_actions" && isDefined(self.selectedPlayer))
        title = "^2>> ^7" + self.selectedPlayer.name + " ^2<<";
    if(!isDefined(self.mmTitleText) || self.mmTitleText != title)
    {
        self.menuTitle setText(title);
        self.mmTitleText = title;
    }

    for(i = 0; i < maxRows; i++)
    {
        row = self.menuRows[i];
        idx = first + i;

        if(idx >= total)
        {
            row.alpha = 0;
            continue;
        }

        opt = opts[idx];
        label = opt.text;
        if(isDefined(opt.key))
        {
            if(self MM_IsOn(opt.key))
                label = label + " ^2[ON]";
            else
                label = label + " ^1[OFF]";
        }

        if(!isDefined(self.mmRowText[i]) || self.mmRowText[i] != label)
        {
            row setText(label);
            self.mmRowText[i] = label;
        }
        row.alpha = 1;
        if(idx == self.menuCursor)
            row.color = (0.2, 1, 0.2);
        else
            row.color = (1, 1, 1);
    }

    footer = "^1(empty)   ^7Melee: back";
    if(total > 0)
        footer = "^3" + (self.menuCursor + 1) + " / " + total + "   ^7Melee: back";

    if(!isDefined(self.mmFooterText) || self.mmFooterText != footer)
    {
        self.menuFooter setText(footer);
        self.mmFooterText = footer;
    }
}

// ============================================================================
//  MENU CONTENT
// ============================================================================

BuildMenuStructure()
{
    hasMapWeapons = self MM_BuildMapWeapons();

    // --- MAIN ---
    self addSubMenu("main", "Free Roam / No Death Barriers", "freeroam");
    self addSubMenu("main", "Movement & Flight", "movement");
    self addSubMenu("main", "Teleport & Saved Locations", "teleport");
    self addSubMenu("main", "World & Game Control", "world");
    self addSubMenu("main", "Personal Mods", "personal");
    self addSubMenu("main", "Persistent Upgrades / Perma-Perks", "permaperks");
    self addSubMenu("main", "Survival & Automation", "survival");
    self addSubMenu("main", "Weapon Mods", "weapons");
    if(hasMapWeapons)
        self addSubMenu("main", "Map Weapons (" + MM_MapName() + ")", "mapweapons");
    self addSubMenu("main", "Spawns & Lobby", "lobby");
    self addSubMenu("main", "Zombie Manipulation", "zombies");
    self addSubMenu("main", "Aimbot & ESP", "vision");
    if(level.script == "zm_tomb")
        self addSubMenu("main", "Origins Tools", "origins");
    if(level.script == "zm_prison")
        self addSubMenu("main", "Mob of the Dead Tools", "prison");
    if(level.script == "zm_transit")
        self addSubMenu("main", "TranZit Tools", "transit");
    if(level.script == "zm_highrise")
        self addSubMenu("main", "Die Rise Tools", "highrise");
    if(level.script == "zm_buried")
        self addSubMenu("main", "Buried Tools", "buried");
    if(self MM_EETrackerAvailable())
        self addSubMenu("main", "Easter Egg Tracker", "eetracker");
    if(self isHost())
        self addSubMenu("main", "Players Menu", "players");

    if(self MM_EETrackerAvailable())
    {
        self addToggleOpt("eetracker", "Show Live Progress HUD", ::MM_ToggleEETracker, "eetracker");
        self addToggleOpt("eetracker", "Quest Guide ESP (Steps + Object Markers)", ::MM_ToggleEETrackerESP, "eetargets");
    }

    // --- FREE ROAM / MAP BOUNDARIES ---
    self addToggleOpt("freeroam", "Disable Out-of-Map Death Monitor", ::ToggleNoDeathBarrier, "noboundary");
    self addToggleOpt("freeroam", "Auto Recover From Falling Out", ::ToggleVoidRecovery, "voidrecover");
    self addMenuOpt("freeroam", "Emergency Return to Active Map Area", ::MM_TeleportToNearestActiveVolume);
    self addMenuOpt("freeroam", "Teleport to Crosshair", ::TeleportToCrosshair);
    self addMenuOpt("freeroam", "Teleport Forward 128", ::MM_TeleportForward, 128);
    self addMenuOpt("freeroam", "Teleport Forward 256", ::MM_TeleportForward, 256);
    self addMenuOpt("freeroam", "Teleport Forward 512", ::MM_TeleportForward, 512);
    self addMenuOpt("freeroam", "Teleport Up 128", ::MM_TeleportVertical, 128);
    self addMenuOpt("freeroam", "Teleport Down 128", ::MM_TeleportVertical, -128);
    self addSubMenu("freeroam", "Saved Free-Roam Positions", "roamspots");
    self addMenuOpt("roamspots", "Save Position 1", ::MM_SaveRoamPosition, 0);
    self addMenuOpt("roamspots", "Load Position 1", ::MM_LoadRoamPosition, 0);
    self addMenuOpt("roamspots", "Save Position 2", ::MM_SaveRoamPosition, 1);
    self addMenuOpt("roamspots", "Load Position 2", ::MM_LoadRoamPosition, 1);
    self addMenuOpt("roamspots", "Save Position 3", ::MM_SaveRoamPosition, 2);
    self addMenuOpt("roamspots", "Load Position 3", ::MM_LoadRoamPosition, 2);

    // --- MOVEMENT / FLIGHT ---
    self addToggleOpt("movement", "Noclip", ::ToggleNoclip, "noclip");
    self addToggleOpt("movement", "Jetpack (Hold Jump)", ::ToggleJetpack, "jetpack");
    self addToggleOpt("movement", "Super Jump", ::ToggleSuperJump, "superjump");
    self addToggleOpt("movement", "Auto-Bhop", ::ToggleBhop, "bhop");
    self addToggleOpt("movement", "Unlimited Sprint", ::ToggleInfiniteSprint, "infsprint");
    self addMenuOpt("movement", "Walk Speed: Normal", ::MM_SetMovementSpeed, 1.0);
    self addMenuOpt("movement", "Walk Speed: 1.5x", ::MM_SetMovementSpeed, 1.5);
    self addMenuOpt("movement", "Walk Speed: 2x", ::MM_SetMovementSpeed, 2.0);
    self addMenuOpt("movement", "Walk Speed: 3x", ::MM_SetMovementSpeed, 3.0);
    self addMenuOpt("movement", "Walk Speed: 4x", ::MM_SetMovementSpeed, 4.0);
    self addMenuOpt("movement", "Noclip Speed: Slow", ::MM_SetNoclipSpeed, 15);
    self addMenuOpt("movement", "Noclip Speed: Normal", ::MM_SetNoclipSpeed, 40);
    self addMenuOpt("movement", "Noclip Speed: Fast", ::MM_SetNoclipSpeed, 80);
    self addMenuOpt("movement", "Noclip Speed: Very Fast", ::MM_SetNoclipSpeed, 150);

    // --- TELEPORT / SAVED POSITIONS ---
    self addMenuOpt("teleport", "Teleport to Crosshair", ::TeleportToCrosshair);
    self addMenuOpt("teleport", "Teleport Forward 128", ::MM_TeleportForward, 128);
    self addMenuOpt("teleport", "Teleport Forward 256", ::MM_TeleportForward, 256);
    self addMenuOpt("teleport", "Teleport Forward 512", ::MM_TeleportForward, 512);
    self addMenuOpt("teleport", "Teleport Up 128", ::MM_TeleportVertical, 128);
    self addMenuOpt("teleport", "Teleport Down 128", ::MM_TeleportVertical, -128);
    self addMenuOpt("teleport", "Return to Nearest Active Map Area", ::MM_TeleportToNearestActiveVolume);
    self addSubMenu("teleport", "Three Saved Locations", "teleportslots");
    self addMenuOpt("teleportslots", "Save Slot 1", ::MM_SaveRoamPosition, 0);
    self addMenuOpt("teleportslots", "Load Slot 1", ::MM_LoadRoamPosition, 0);
    self addMenuOpt("teleportslots", "Save Slot 2", ::MM_SaveRoamPosition, 1);
    self addMenuOpt("teleportslots", "Load Slot 2", ::MM_LoadRoamPosition, 1);
    self addMenuOpt("teleportslots", "Save Slot 3", ::MM_SaveRoamPosition, 2);
    self addMenuOpt("teleportslots", "Load Slot 3", ::MM_LoadRoamPosition, 2);

    // --- WORLD / GAME CONTROL ---
    self addMenuOpt("world", "Gravity: Very Low", ::MM_SetGravity, 50);
    self addMenuOpt("world", "Gravity: Low", ::MM_SetGravity, 150);
    self addMenuOpt("world", "Gravity: Medium", ::MM_SetGravity, 300);
    self addMenuOpt("world", "Gravity: Normal", ::MM_SetGravity, 800);
    self addMenuOpt("world", "Game Speed: 0.25x", ::SetTimeScale, 0.25);
    self addMenuOpt("world", "Game Speed: 0.5x", ::SetTimeScale, 0.5);
    self addMenuOpt("world", "Game Speed: Normal", ::SetTimeScale, 1.0);
    self addMenuOpt("world", "Game Speed: 2x", ::SetTimeScale, 2.0);
    self addMenuOpt("world", "Game Speed: 4x", ::SetTimeScale, 4.0);
    self addMenuOpt("world", "Round 5", ::SetRound, 5);
    self addMenuOpt("world", "Round 25", ::SetRound, 25);
    self addMenuOpt("world", "Round 50", ::SetRound, 50);
    self addMenuOpt("world", "Round 75", ::SetRound, 75);
    self addMenuOpt("world", "Round 99", ::SetRound, 99);
    self addMenuOpt("world", "Round 150", ::SetRound, 150);
    self addMenuOpt("world", "Round 250", ::SetRound, 250);
    self addMenuOpt("world", "Advance 1 Round", ::MM_AdvanceRound, 1);
    self addMenuOpt("world", "Advance 5 Rounds", ::MM_AdvanceRound, 5);
    self addMenuOpt("world", "Advance 10 Rounds", ::MM_AdvanceRound, 10);
    self addMenuOpt("world", "Reset World (Gravity + Speed)", ::MM_ResetWorld);

    // --- PERSISTENT UPGRADES / PERMA-PERKS ---
    self addMenuOpt("permaperks", "Unlock ALL Available Perma-Perks", ::MM_GiveAllPersistentUpgrades);

    // --- PERSONAL ---
    self addToggleOpt("personal", "God Mode", ::ToggleGodMode, "god");
    self addToggleOpt("personal", "Noclip", ::ToggleNoclip, "noclip");
    self addToggleOpt("personal", "Jetpack (Hold Jump)", ::ToggleJetpack, "jetpack");
    self addToggleOpt("personal", "Super Jump", ::ToggleSuperJump, "superjump");
    self addToggleOpt("personal", "Auto-Bhop", ::ToggleBhop, "bhop");
    self addToggleOpt("personal", "Vampire Mode (Heal on Points)", ::ToggleVampire, "vampire");
    self addToggleOpt("personal", "Move = Refill Ammo", ::ToggleMovementAmmo, "moveammo");
    self addToggleOpt("personal", "Magic Bullets (Ray Gun)", ::ToggleMagicBullets, "magic");
    self addToggleOpt("personal", "Super Health", ::ToggleHealth, "health");
    self addToggleOpt("personal", "Zombies Ignore Me", ::ToggleIgnoreMe, "ignore");
    self addToggleOpt("personal", "Max Movespeed", ::ToggleSpeed, "speed");
    self addToggleOpt("personal", "Invisibility", ::ToggleInvis, "invis");
    self addToggleOpt("personal", "Third Person", ::ToggleThirdPerson, "thirdp");
    self addMenuOpt("personal", "FOV 120", ::SetFOV, "120");
    self addMenuOpt("personal", "FOV Default (65)", ::SetFOV, "65");
    self addMenuOpt("personal", "+1,000 Points", ::MM_GiveScore, 1000);
    self addMenuOpt("personal", "+10,000 Points", ::MM_GiveScore, 10000);
    self addMenuOpt("personal", "+50,000 Points", ::MM_GiveScore, 50000);
    self addMenuOpt("personal", "+100,000 Points", ::GivePoints);
    self addToggleOpt("personal", "Infinite Points", ::ToggleInfPoints, "infpoints");
    self addMenuOpt("personal", "Save Position", ::SavePosition);
    self addMenuOpt("personal", "Load Position", ::LoadPosition);
    self addMenuOpt("personal", "Teleport To Crosshair", ::TeleportToCrosshair);
    self addMenuOpt("personal", "Suicide", ::DoSuicide);

    // --- SURVIVAL / AUTOMATION ---
    self addToggleOpt("survival", "Auto Revive (Self)", ::MM_ToggleAutoRevive, "autorevive");
    self addToggleOpt("survival", "Auto Rebuy All Map Perks", ::MM_ToggleAutoPerks, "autoperks");
    self addToggleOpt("survival", "Live Match HUD (Round / Points / Health)", ::MM_ToggleStatusHUD, "statushud");
    self addMenuOpt("survival", "Restore Default Movement", ::MM_ResetMovement);
    self addMenuOpt("survival", "Refill Health Now", ::MM_RefillHealth);

    // --- WEAPONS ---
    self addToggleOpt("weapons", "Infinite Ammo (Current Weapon)", ::ToggleInfAmmo, "infammo");
    self addToggleOpt("weapons", "Infinite Ammo (All Weapons)", ::MM_ToggleInfAmmoAll, "infammoall");
    self addMenuOpt("weapons", "Pack-A-Punch Current", ::PapCurrentWeapon);
    self addMenuOpt("weapons", "Pack-A-Punch ALL Guns", ::PapAllWeapons);
    self addMenuOpt("weapons", "Max Ammo Current", ::FillCurrentAmmo);
    self addMenuOpt("weapons", "Max Ammo ALL", ::FillAllAmmo);
    self addSubMenu("weapons", "Heavy / Explosive Arsenal", "heavyweapons");
    self addSubMenu("weapons", "Wonder Weapons", "wonderweapons");
    self addSubMenu("weapons", "More Guns (PaP)", "guns");
    self addSubMenu("weapons", "All Registered Weapons (This Map)", "allguns");

    // Heavy weapons are only displayed when the active map registers them.
    self MM_AddWeaponOpt("heavyweapons", "RPG-7 / Rocket Launcher", "usrpg_zm");
    self MM_AddWeaponOpt("heavyweapons", "RPG-7 (Pack-A-Punched)", "usrpg_upgraded_zm");
    self MM_AddWeaponOpt("heavyweapons", "War Machine Grenade Launcher", "m32_zm");
    self MM_AddWeaponOpt("heavyweapons", "War Machine (Pack-A-Punched)", "m32_upgraded_zm");
    self MM_AddWeaponOpt("heavyweapons", "Monkey Bombs", "cymbal_monkey_zm");
    self MM_AddWeaponOpt("heavyweapons", "Semtex Grenades", "sticky_grenade_zm");
    self MM_AddWeaponOpt("heavyweapons", "Claymores", "claymore_zm");
    self addMenuOpt("heavyweapons", "Give RPG + War Machine Loadout", ::MM_GiveRocketLoadout);

    // Wonder weapons are map-aware; unavailable weapons are omitted.
    self MM_AddWeaponOpt("wonderweapons", "Ray Gun", "ray_gun_zm");
    self MM_AddWeaponOpt("wonderweapons", "Ray Gun (Pack-A-Punched)", "ray_gun_upgraded_zm");
    self MM_AddWeaponOpt("wonderweapons", "Ray Gun Mark II", "raygun_mark2_zm");
    self MM_AddWeaponOpt("wonderweapons", "Ray Gun Mark II (Pack-A-Punched)", "raygun_mark2_upgraded_zm");
    self MM_AddWeaponOpt("wonderweapons", "Jet Gun (TranZit)", "jetgun_zm");
    self MM_AddWeaponOpt("wonderweapons", "Blundergat (Mob of the Dead)", "blundergat_zm");
    self MM_AddWeaponOpt("wonderweapons", "Acid Gat / Vitriolic Withering", "blundergat_upgraded_zm");

    self MM_BuildRegisteredWeaponList();
    // Each entry only appears if the current map actually has that weapon loaded.
    self MM_AddWeaponOpt("guns", "HAMR (PaP)", "hamr_upgraded_zm");
    self MM_AddWeaponOpt("guns", "LSAT (PaP)", "lsat_upgraded_zm");
    self MM_AddWeaponOpt("guns", "War Machine (PaP)", "m32_upgraded_zm");
    self MM_AddWeaponOpt("guns", "AN-94 (PaP)", "an94_upgraded_zm");
    self MM_AddWeaponOpt("guns", "M27 (PaP)", "hk416_upgraded_zm");
    self MM_AddWeaponOpt("guns", "Type 25 (PaP)", "type95_upgraded_zm");
    self MM_AddWeaponOpt("guns", "SCAR-H (PaP)", "scar_upgraded_zm");
    self MM_AddWeaponOpt("guns", "FAL (PaP)", "fnfal_upgraded_zm");
    self MM_AddWeaponOpt("guns", "M14 (PaP)", "m14_upgraded_zm");
    self MM_AddWeaponOpt("guns", "STG-44 (PaP)", "mp44_upgraded_zm");
    self MM_AddWeaponOpt("guns", "M16 (PaP)", "m16_gl_upgraded_zm");
    self MM_AddWeaponOpt("guns", "MTAR (PaP)", "tar21_upgraded_zm");
    self MM_AddWeaponOpt("guns", "XM8 (PaP)", "xm8_upgraded_zm");
    self MM_AddWeaponOpt("guns", "RPD (PaP)", "rpd_upgraded_zm");
    self MM_AddWeaponOpt("guns", "Chicom CQB (PaP)", "qcw05_upgraded_zm");
    self MM_AddWeaponOpt("guns", "AK74u (PaP)", "ak74u_upgraded_zm");
    self MM_AddWeaponOpt("guns", "MP5 (PaP)", "mp5k_upgraded_zm");
    self MM_AddWeaponOpt("guns", "Skorpion EVO (PaP)", "evoskorpion_upgraded_zm");
    self MM_AddWeaponOpt("guns", "KAP-40 (PaP)", "kard_upgraded_zm");
    self MM_AddWeaponOpt("guns", "Python (PaP)", "python_upgraded_zm");
    self MM_AddWeaponOpt("guns", "Five-seven Dual Wield (PaP)", "fivesevendw_upgraded_zm");
    self MM_AddWeaponOpt("guns", "Executioner (PaP)", "judge_upgraded_zm");
    self MM_AddWeaponOpt("guns", "S12 (PaP)", "saiga12_upgraded_zm");
    self MM_AddWeaponOpt("guns", "KSG (PaP)", "ksg_upgraded_zm");
    self MM_AddWeaponOpt("guns", "M1216 (PaP)", "srm1216_upgraded_zm");
    self MM_AddWeaponOpt("guns", "Olympia (PaP)", "rottweil72_upgraded_zm");
    self MM_AddWeaponOpt("guns", "SVU-AS (PaP)", "svu_upgraded_zm");
    self MM_AddWeaponOpt("guns", "DSR 50 (PaP)", "dsr50_upgraded_zm");
    self MM_AddWeaponOpt("guns", "Barrett M82A1 (PaP)", "barretm82_upgraded_zm");
    self MM_AddWeaponOpt("guns", "Ballista (PaP)", "ballista_upgraded_zm");
    self MM_AddWeaponOpt("guns", "Ballistic Knife (PaP)", "knife_ballistic_upgraded_zm");
    self MM_AddWeaponOpt("guns", "Semtex", "sticky_grenade_zm");
    self MM_AddWeaponOpt("guns", "Claymores", "claymore_zm");
    self MM_AddWeaponOpt("weapons", "Ray Gun Mark II (PaP)", "raygun_mark2_upgraded_zm");
    self MM_AddWeaponOpt("weapons", "Ray Gun (PaP)", "ray_gun_upgraded_zm");
    self MM_AddWeaponOpt("weapons", "RPG (PaP)", "usrpg_upgraded_zm");
    self MM_AddWeaponOpt("weapons", "Galil (PaP)", "galil_upgraded_zm");
    self MM_AddWeaponOpt("weapons", "PDW-57 (PaP)", "pdw57_upgraded_zm");
    self MM_AddWeaponOpt("weapons", "Mustang & Sally / M1911 (PaP)", "m1911_upgraded_zm");
    self MM_AddWeaponOpt("weapons", "Monkey Bombs", "cymbal_monkey_zm");
    self MM_AddWeaponOpt("weapons", "EMP Grenades", "emp_grenade_zm");
    self MM_AddWeaponOpt("weapons", "Zombie Shield", "riotshield_zm");
    self MM_AddWeaponOpt("weapons", "Galvaknuckles", "tazer_knuckles_zm");
    self addMenuOpt("weapons", "Give All Available Perks", ::GiveAllPerks);
    self addMenuOpt("weapons", "Remove All Available Perks", ::RemoveAllPerks);
    self addMenuOpt("weapons", "Drop Current Weapon", ::DropWeapon);

    // --- LOBBY ---
    self addMenuOpt("lobby", "Turn On Power", ::TurnOnPower);
    self addMenuOpt("lobby", "Open All Doors", ::OpenAllDoors);
    self MM_AddDropOpt("Spawn Max Ammo", "full_ammo");
    self MM_AddDropOpt("Spawn Insta-Kill", "insta_kill");
    self MM_AddDropOpt("Spawn Double Points", "double_points");
    self MM_AddDropOpt("Spawn Nuke", "nuke");
    self MM_AddDropOpt("Spawn Carpenter", "carpenter");
    self MM_AddDropOpt("Spawn Fire Sale", "fire_sale");
    self MM_AddDropOpt("Spawn Free Perk", "free_perk");
    self MM_AddDropOpt("Spawn Death Machine", "minigun");
    self MM_AddDropOpt("Spawn Zombie Blood", "zombie_blood");
    self addSubMenu("lobby", "All Registered Powerups", "powerups");
    self MM_BuildRegisteredPowerupList();
    self addMenuOpt("lobby", "Skip Round (+1)", ::SkipRound);
    self addMenuOpt("lobby", "Jump to Round 10", ::SetRound, 10);
    self addMenuOpt("lobby", "Jump to Round 25", ::SetRound, 25);
    self addMenuOpt("lobby", "Jump to Round 50", ::SetRound, 50);
    self addMenuOpt("lobby", "Jump to Round 100", ::SetRound, 100);
    self addMenuOpt("lobby", "Game Speed: Slomo", ::SetTimeScale, 0.5);
    self addMenuOpt("lobby", "Game Speed: Fast", ::SetTimeScale, 2.0);
    self addMenuOpt("lobby", "Game Speed: Normal", ::SetTimeScale, 1.0);
    // Use unique, zero-argument handlers here. SetGravity is also a native
    // BO2 GSC function name, so using it as a custom callback can collide.
    self addMenuOpt("lobby", "Low Gravity", ::MM_SetLowGravity);
    self addMenuOpt("lobby", "Normal Gravity", ::MM_SetNormalGravity);
    if(self isHost())
    {
        self addMenuOpt("lobby", "Restart Map", ::RestartMap);
        self addMenuOpt("lobby", "End Game", ::EndGame);
    }

    // --- ZOMBIES ---
    self addMenuOpt("zombies", "Kill All Enemies", ::KillAllZombies);
    self addMenuOpt("zombies", "Clear Regular Zombies (Keep Bosses)", ::MM_ClearRegularZombies);
    self addMenuOpt("zombies", "Explode All Zombies", ::ExplodeZombies);
    self addMenuOpt("zombies", "Burn All Zombies", ::BurnZombies);
    self addMenuOpt("zombies", "Teleport All To Me", ::TeleportZombies);
    self addMenuOpt("zombies", "Teleport All To Crosshair", ::TeleportZombiesCrosshair);
    self addToggleOpt("zombies", "Zombie Magnet", ::ToggleZombieMagnet, "magnet");
    self addMenuOpt("zombies", "Send Zombies to Moon", ::ZombiesToMoon);
    self addMenuOpt("zombies", "Launch Zombies Up", ::FlingZombies);
    self addToggleOpt("zombies", "Freeze All Zombies", ::ToggleFreezeZombies, "freeze");
    self addMenuOpt("zombies", "Zombie Speed: Sprint", ::SetZombieSpeed, "sprint");
    self addMenuOpt("zombies", "Zombie Speed: Run", ::SetZombieSpeed, "run");
    self addMenuOpt("zombies", "Zombie Speed: Walk", ::SetZombieSpeed, "walk");
    self addMenuOpt("zombies", "Zombie Speed: Default", ::SetZombieSpeed, "default");
    self addToggleOpt("zombies", "Insta-Kill Aura", ::ToggleKillAura, "killaura");
    self addMenuOpt("zombies", "Delete All Zombies", ::DeleteZombies);
    self addMenuOpt("zombies", "Add 24 Zombies To Round", ::RespawnZombies);
    self addMenuOpt("zombies", "Leave One Zombie Alive", ::MM_LeaveOneZombieAlive);
    self addMenuOpt("zombies", "Kill Nearest Zombie", ::MM_KillNearestZombie);
    self addMenuOpt("zombies", "Teleport Nearest Zombie To Me", ::MM_TeleportNearestZombie);
    self addMenuOpt("zombies", "Teleport Nearest Zombie To Crosshair", ::MM_TeleportNearestZombieToCrosshair);
    self addSubMenu("zombies", "Spawn Zombie Types", "zspawn");
    self addSubMenu("zombies", "Zombie AI & Health Controls", "zai");
    self addSubMenu("zombies", "Boss & Special Enemy Controls", "zboss");
    self addSubMenu("zombies", "Zombie Effects & Crowd Tools", "zeffects");

    // Spawn options are filtered against the live map's stock registries.
    self addMenuOpt("zspawn", "Spawn 1 Regular Zombie", ::MM_SpawnZombieBatch, "normal", 1);
    self addMenuOpt("zspawn", "Spawn 5 Regular Zombies", ::MM_SpawnZombieBatch, "normal", 5);
    self addMenuOpt("zspawn", "Spawn 10 Regular Zombies", ::MM_SpawnZombieBatch, "normal", 10);
    self addMenuOpt("zspawn", "Spawn 24 Regular Zombies", ::MM_SpawnZombieBatch, "normal", 24);
    if(isDefined(level.dog_spawners) && level.dog_spawners.size > 0)
    {
        self addMenuOpt("zspawn", "Spawn 1 Hellhound", ::MM_SpawnZombieBatch, "dog", 1);
        self addMenuOpt("zspawn", "Spawn 5 Hellhounds", ::MM_SpawnZombieBatch, "dog", 5);
    }
    if(isDefined(level.leaper_spawners) && level.leaper_spawners.size > 0)
    {
        self addMenuOpt("zspawn", "Spawn 1 Denizen / Leaper", ::MM_SpawnZombieBatch, "leaper", 1);
        self addMenuOpt("zspawn", "Spawn 5 Denizens / Leapers", ::MM_SpawnZombieBatch, "leaper", 5);
    }
    self addMenuOpt("zspawn", "Spawn Type Availability", ::MM_ShowZombieSpawnTypes);

    self addToggleOpt("zai", "Disable Non-Boss Zombie AI", ::MM_ToggleZombiePacify, "zpacify");
    self addMenuOpt("zai", "Set Current Non-Boss Enemies to 1 HP", ::MM_SetZombieHealth, 1);
    self addMenuOpt("zai", "Set Current Zombies to 50 HP", ::MM_SetZombieHealth, 50);
    self addMenuOpt("zai", "Set Current Zombies to 100 HP", ::MM_SetZombieHealth, 100);
    self addMenuOpt("zai", "Set Current Zombies to 500 HP", ::MM_SetZombieHealth, 500);
    self addMenuOpt("zai", "Set Current Zombies to 1,000 HP", ::MM_SetZombieHealth, 1000);
    self addMenuOpt("zai", "Zombie Speed: Sprint", ::SetZombieSpeed, "sprint");
    self addMenuOpt("zai", "Zombie Speed: Run", ::SetZombieSpeed, "run");
    self addMenuOpt("zai", "Zombie Speed: Walk", ::SetZombieSpeed, "walk");
    self addMenuOpt("zai", "Zombie Speed: Default", ::SetZombieSpeed, "default");

    self addMenuOpt("zboss", "Kill All Quest Bosses", ::MM_KillZombieGroup, "boss");
    self addMenuOpt("zboss", "Kill All Hellhounds", ::MM_KillZombieGroup, "dog");
    self addMenuOpt("zboss", "Kill All Denizens / Leapers", ::MM_KillZombieGroup, "leaper");
    self addMenuOpt("zboss", "Kill All Special Enemies", ::MM_KillZombieGroup, "special");
    self addMenuOpt("zboss", "Show Live Boss / Special Enemy Count", ::MM_ShowZombieGroupCounts);

    self addMenuOpt("zeffects", "Explode All Regular Zombies", ::ExplodeZombies);
    self addMenuOpt("zeffects", "Burn All Regular Zombies", ::BurnZombies);
    self addMenuOpt("zeffects", "Launch All Regular Zombies", ::FlingZombies);
    self addMenuOpt("zeffects", "Send All Regular Zombies to the Moon", ::ZombiesToMoon);
    self addToggleOpt("zeffects", "Freeze All Regular Zombies", ::ToggleFreezeZombies, "freeze");
    self addToggleOpt("zeffects", "Zombie Magnet", ::ToggleZombieMagnet, "magnet");
    self addToggleOpt("zeffects", "Insta-Kill Aura", ::ToggleKillAura, "killaura");

    // --- VISION ---
    self addToggleOpt("vision", "Aimbot", ::ToggleAimbot, "aimbot");
    self addMenuOpt("vision", "Aim Target: Head (Aimbot + Silent)", ::SetAimTarget, "j_head");
    self addMenuOpt("vision", "Aim Target: Chest (Aimbot + Silent)", ::SetAimTarget, "j_spinelower");
    self addToggleOpt("vision", "Silent Aim (Bullets To Head)", ::ToggleSilentAim, "silentaim");
    self addMenuOpt("vision", "Silent Aim FOV: Narrow", ::SetSilentFov, 0.97);
    self addMenuOpt("vision", "Silent Aim FOV: Wide", ::SetSilentFov, 0.85);
    self addMenuOpt("vision", "Silent Aim FOV: Full 360", ::SetSilentFov, -1);
    self addToggleOpt("vision", "ESP (Zombie Dots)", ::ToggleESP, "esp");
    self addToggleOpt("vision", "ESP (Parts - All Maps)", ::MM_TogglePartsESP, "partesp");
    self addMenuOpt("vision", "ESP Dot: Tiny", ::SetESPSize, 2);
    self addMenuOpt("vision", "ESP Dot: Small", ::SetESPSize, 4);
    self addMenuOpt("vision", "ESP Dot: Medium", ::SetESPSize, 7);
    self addMenuOpt("vision", "ESP Color: Red", ::SetESPColor, (1, 0, 0));
    self addMenuOpt("vision", "ESP Color: Green", ::SetESPColor, (0, 1, 0));
    self addMenuOpt("vision", "ESP Color: Blue", ::SetESPColor, (0, 0, 1));
    self addMenuOpt("vision", "ESP Color: Yellow", ::SetESPColor, (1, 1, 0));
    self addMenuOpt("vision", "ESP Color: White", ::SetESPColor, (1, 1, 1));
    self addMenuOpt("vision", "ESP Color: Pink", ::SetESPColor, (1, 0.2, 0.8));

    // --- ORIGINS (only present on zm_tomb) ---
    if(level.script == "zm_tomb")
    {
        self addMenuOpt("origins", "Give Myself Shovel", ::MM_OriginsGiveShovel);
        self addMenuOpt("origins", "Give Myself Golden Shovel", ::MM_OriginsGiveGoldenShovel);
        self addMenuOpt("origins", "Give Myself Golden Helmet", ::MM_OriginsGiveGoldenHelmet);
        self addToggleOpt("origins", "Dig Site ESP", ::MM_OriginsToggleDigESP, "origdigesp");
        self addMenuOpt("origins", "Staff Progress Tracker", ::MM_OriginsStaffProgress);
        self addToggleOpt("origins", "Staff Upgrade Guide ESP", ::MM_OriginsToggleStaffGuide, "origstaffguide");
        self addMenuOpt("origins", "Stage All 4 Staff Crystals in Crazy Place", ::MM_OriginsStageAllCrystals);
        self addMenuOpt("origins", "Maxis Drone: Recall / Recover", ::MM_OriginsRecoverDrone);
        self addSubMenu("origins", "One Inch Punch", "originspunch");
        self addToggleOpt("origins", "Robot Foot Warning", ::MM_OriginsToggleRobotWarning, "origrobotwarn");
        self addMenuOpt("origins", "Tank Status", ::MM_OriginsTankStatus);
        self addMenuOpt("origins", "Call Tank (500 Points)", ::MM_OriginsCallTank);
        self addSubMenu("origins", "Crazy Place / Map Teleports", "originsteleport");
        self addMenuOpt("origins", "Collect All Shared Parts", ::MM_OriginsCollectAllSharedParts);
        self addToggleOpt("origins", "Auto-Collect Shared Parts", ::MM_OriginsToggleAutoCollect, "origcollect");
        self addMenuOpt("origins", "Force All Four Staff Upgrades", ::MM_OriginsUpgradeAllStaffs);
        self addMenuOpt("origins", "Turn On All Generators (Pack-a-Punch)", ::MM_OriginsTurnOnAllGenerators);
        self addToggleOpt("origins", "Ignore Mud Slowdown", ::MM_OriginsToggleNoMudSlow, "nomud");

        self addMenuOpt("originspunch", "Basic One Inch Punch", ::MM_OriginsGivePunch, "normal");
        self addMenuOpt("originspunch", "Upgraded One Inch Punch", ::MM_OriginsGivePunch, "upgraded");
        self addMenuOpt("originspunch", "Wind Elemental Punch", ::MM_OriginsGivePunch, "air");
        self addMenuOpt("originspunch", "Fire Elemental Punch", ::MM_OriginsGivePunch, "fire");
        self addMenuOpt("originspunch", "Ice Elemental Punch", ::MM_OriginsGivePunch, "ice");
        self addMenuOpt("originspunch", "Lightning Elemental Punch", ::MM_OriginsGivePunch, "lightning");

        self addMenuOpt("originsteleport", "Teleport to Crazy Place", ::MM_OriginsTeleportCrazyPlace);
        self addMenuOpt("originsteleport", "Teleport Inside Robot 1", ::MM_OriginsTeleportRobot, 0);
        self addMenuOpt("originsteleport", "Teleport Inside Robot 2", ::MM_OriginsTeleportRobot, 1);
        self addMenuOpt("originsteleport", "Teleport Inside Robot 3", ::MM_OriginsTeleportRobot, 2);
        self addMenuOpt("originsteleport", "Return via Fire Portal", ::MM_OriginsTeleportMainMap, 1);
        self addMenuOpt("originsteleport", "Return via Wind Portal", ::MM_OriginsTeleportMainMap, 2);
        self addMenuOpt("originsteleport", "Return via Lightning Portal", ::MM_OriginsTeleportMainMap, 3);
        self addMenuOpt("originsteleport", "Return via Ice Portal", ::MM_OriginsTeleportMainMap, 4);

        if(self isHost())
            self addMenuOpt("origins", "Complete Little Lost Girl (ends match)", ::MM_OriginsConfirmCompleteSecret);
        self.menuParents["origins"] = "main";
    }

    // --- MOB OF THE DEAD (only present on zm_prison) ---
    if(level.script == "zm_prison")
    {
        self addMenuOpt("prison", "Unlock Everything", ::MM_PrisonUnlockEverything);
        self addMenuOpt("prison", "Power All Perk Machines", ::MM_PrisonPowerPerks);
        self addMenuOpt("prison", "Power The Gondola", ::MM_PrisonPowerGondola);
        self addMenuOpt("prison", "Open Afterlife Doors", ::MM_PrisonOpenAfterlifeDoors);
        self addMenuOpt("prison", "Send Gondola (Free)", ::MM_PrisonSendGondola);
        self addMenuOpt("prison", "Afterlife: Refill My Life", ::MM_PrisonAfterlifeRefill);
        self addToggleOpt("prison", "Afterlife: Infinite Mana", ::MM_PrisonToggleInfMana, "prmana");
        self addMenuOpt("prison", "Spawn Brutus", ::MM_PrisonSpawnBrutus, false);
        self addMenuOpt("prison", "Spawn Brutus (Ignore Limit)", ::MM_PrisonSpawnBrutus, true);
        self addMenuOpt("prison", "Kill Brutus", ::MM_PrisonKillBrutus);
        self addMenuOpt("prison", "Give Spoon", ::MM_PrisonGiveSpoon, false);
        self addMenuOpt("prison", "Give Golden Spork", ::MM_PrisonGiveSpoon, true);
        if(self isHost())
        {
            self addMenuOpt("prison", "Afterlife: Refill Everyone's Life", ::MM_PrisonAfterlifeRefillAll);
            self addMenuOpt("prison", "Build Plane (Skip Parts)", ::MM_PrisonBuildPlane);
            self addMenuOpt("prison", "Refuel Plane (Skip 5 Cans)", ::MM_PrisonRefuelPlane);
        }
        self.menuParents["prison"] = "main";
    }

    // --- TRANZIT (only present on zm_transit) ---
    if(level.script == "zm_transit")
    {
        self addMenuOpt("transit", "Build Power Switch", ::MM_MapBuildable, "zm_transit", "powerswitch");
        self addMenuOpt("transit", "Activate Power Switch", ::MM_MapPowerSwitch, "zm_transit");
        self addMenuOpt("transit", "Build Turbine", ::MM_MapBuildable, "zm_transit", "turbine");
        self addMenuOpt("transit", "Build Zombie Shield", ::MM_MapBuildable, "zm_transit", "riotshield_zm");
        self addMenuOpt("transit", "Build Jet Gun", ::MM_MapBuildable, "zm_transit", "jetgun_zm");
        self addMenuOpt("transit", "Build Turret", ::MM_MapBuildable, "zm_transit", "turret");
        self addMenuOpt("transit", "Build Electric Trap", ::MM_MapBuildable, "zm_transit", "electric_trap");
        self addMenuOpt("transit", "Build Bus Cattle Catcher", ::MM_MapBuildable, "zm_transit", "cattlecatcher");
        self addMenuOpt("transit", "Build Bus Hatch", ::MM_MapBuildable, "zm_transit", "bushatch");
        self addMenuOpt("transit", "Build Diner Hatch", ::MM_MapBuildable, "zm_transit", "dinerhatch");
        self addMenuOpt("transit", "Build Bus Ladder", ::MM_MapBuildable, "zm_transit", "busladder");
        self addMenuOpt("transit", "Build Pack-a-Punch", ::MM_MapBuildable, "zm_transit", "pap");
        self addMenuOpt("transit", "Build Navcard Table", ::MM_MapBuildable, "zm_transit", "sq_common");
        self.menuParents["transit"] = "main";
    }

    // --- DIE RISE (only present on zm_highrise) ---
    if(level.script == "zm_highrise")
    {
        self addMenuOpt("highrise", "Activate Power Switch", ::MM_MapPowerSwitch, "zm_highrise");
        self addMenuOpt("highrise", "Build Trample Steam", ::MM_MapBuildable, "zm_highrise", "springpad_zm");
        self addMenuOpt("highrise", "Build Sliquifier", ::MM_MapBuildable, "zm_highrise", "slipgun_zm");
        self addMenuOpt("highrise", "Build Escape Pod Keys", ::MM_MapBuildable, "zm_highrise", "keys_zm");
        self addMenuOpt("highrise", "Build Elevator Control Key", ::MM_MapBuildable, "zm_highrise", "ekeys_zm");
        self addMenuOpt("highrise", "Build Navcard Table", ::MM_MapBuildable, "zm_highrise", "sq_common");
        self addMenuOpt("highrise", "Call All Elevators to First Stop", ::MM_HighriseSendElevators, 0);
        self.menuParents["highrise"] = "main";
    }

    // --- BURIED (only present on zm_buried) ---
    if(level.script == "zm_buried")
    {
        self addMenuOpt("buried", "Activate Power Switch", ::MM_MapPowerSwitch, "zm_buried");
        self addMenuOpt("buried", "Open Leroy's Cell", ::MM_BuriedOpenCell);
        self addMenuOpt("buried", "Build Turbine", ::MM_MapBuildable, "zm_buried", "turbine");
        self addMenuOpt("buried", "Build Trample Steam", ::MM_MapBuildable, "zm_buried", "springpad_zm");
        self addMenuOpt("buried", "Build Subwoofer", ::MM_MapBuildable, "zm_buried", "subwoofer_zm");
        self addMenuOpt("buried", "Build Head Chopper", ::MM_MapBuildable, "zm_buried", "headchopper_zm");
        self addMenuOpt("buried", "Build Cell Key", ::MM_MapBuildable, "zm_buried", "keys_zm");
        self addMenuOpt("buried", "Build Navcard Table", ::MM_MapBuildable, "zm_buried", "sq_common");
        self addMenuOpt("buried", "Build Maxis Tower", ::MM_MapBuildable, "zm_buried", "buried_sq_bt_m_tower");
        self addMenuOpt("buried", "Build Richtofen Tower", ::MM_MapBuildable, "zm_buried", "buried_sq_bt_r_tower");
        self.menuParents["buried"] = "main";
    }

    // --- PLAYERS (host only) ---
    if(self isHost())
    {
        self MM_BuildPlayersList();

        self addMenuOpt("player_actions", "[+] Give Mod Menu Access", ::ActionGiveMenu);
        self addMenuOpt("player_actions", "[-] Take Mod Menu Access", ::ActionTakeMenu);
        self addMenuOpt("player_actions", "Toggle God Mode", ::ActionGodMode);
        self addMenuOpt("player_actions", "Toggle Free-Roam / No Death Barriers", ::ActionBoundary);
        self addMenuOpt("player_actions", "Give All Perks", ::ActionGivePerks);
        self addMenuOpt("player_actions", "Give +100k Points", ::ActionPoints);
        self addMenuOpt("player_actions", "Revive", ::ActionRevive);        self addMenuOpt("player_actions", "Teleport To Them", ::ActionTeleportTo);
        self addMenuOpt("player_actions", "Bring Them To Me", ::ActionBring);
        self addMenuOpt("player_actions", "Freeze Player (Troll)", ::ActionFreeze);
        self addMenuOpt("player_actions", "Launch Player (Troll)", ::ActionSendToMoon);
        self addMenuOpt("player_actions", "Kill Player", ::ActionKill);
        self.menuParents["player_actions"] = "players";
    }
}

// Builds the weapon folder for the CURRENT map only. Returns true if it has any entries.
// Weapon IDs below were checked against the T6 zombie scripts of each map.
MM_BuildMapWeapons()
{
    m = "mapweapons";
    switch(level.script)
    {
        case "zm_tomb":
            self MM_AddWeaponOpt(m, "Ice Staff (Ull's Arrow)", "staff_water_upgraded_zm");
            self MM_AddWeaponOpt(m, "Fire Staff (Kagutsuchi)", "staff_fire_upgraded_zm");
            self MM_AddWeaponOpt(m, "Wind Staff (Boreas)", "staff_air_upgraded_zm");
            self MM_AddWeaponOpt(m, "Lightning Staff (Kimat)", "staff_lightning_upgraded_zm");
            self MM_AddWeaponOpt(m, "Mauser C96 (PaP)", "c96_upgraded_zm");
            self MM_AddWeaponOpt(m, "MG08/15 (PaP)", "mg08_upgraded_zm");
            self MM_AddWeaponOpt(m, "G-Strike", "beacon_zm");
            break;
        case "zm_prison":
            self MM_AddWeaponOpt(m, "Blundergat", "blundergat_zm");
            self MM_AddWeaponOpt(m, "The Sweeper", "blundergat_upgraded_zm");
            self MM_AddWeaponOpt(m, "Acid Gat", "blundersplat_zm");
            self MM_AddWeaponOpt(m, "Acid Gat (PaP)", "blundersplat_upgraded_zm");
            self MM_AddWeaponOpt(m, "Hell's Retriever", "bouncing_tomahawk_zm");
            self MM_AddWeaponOpt(m, "Hell's Redeemer", "upgraded_tomahawk_zm");
            self MM_AddWeaponOpt(m, "Thompson (PaP)", "thompson_upgraded_zm");
            break;
        case "zm_buried":
            self MM_AddWeaponOpt(m, "Paralyzer", "slowgun_zm");
            self MM_AddWeaponOpt(m, "Petrifier", "slowgun_upgraded_zm");
            self MM_AddWeaponOpt(m, "Remington New Model Army", "rnma_zm");
            self MM_AddWeaponOpt(m, "Remington (PaP)", "rnma_upgraded_zm");
            self MM_AddWeaponOpt(m, "Time Bomb", "time_bomb_zm");
            break;
        case "zm_highrise":
            self MM_AddWeaponOpt(m, "Sliquifier", "slipgun_zm");
            self MM_AddWeaponOpt(m, "Sliquifier (PaP)", "slipgun_upgraded_zm");
            break;
        case "zm_transit":
            self MM_AddWeaponOpt(m, "Jet Gun", "jetgun_zm");
            break;
        default:
            break;
    }

    if(isDefined(self.menuOpts[m]) && self.menuOpts[m].size > 0)
    {
        self.menuParents[m] = "main";
        return true;
    }
    return false;
}

MM_MapName()
{
    switch(level.script)
    {
        case "zm_transit":  return "TranZit";
        case "zm_nuked":    return "Nuketown";
        case "zm_highrise": return "Die Rise";
        case "zm_prison":   return "Mob of the Dead";
        case "zm_buried":   return "Buried";
        case "zm_tomb":     return "Origins";
    }
    return level.script;
}

// ============================================================================
//  HELPERS
// ============================================================================

MM_IsOn(key)
{
    if(key == "freeze")
        return level.mmFrozen;
    if(!isDefined(self.mmToggle))
        return false;
    if(!isDefined(self.mmToggle[key]))
        return false;
    return self.mmToggle[key];
}

// Flips a flag, prints status, returns the NEW state.
MM_Flip(key, label)
{
    if(!isDefined(self.mmToggle))
        self.mmToggle = [];

    on = !(self MM_IsOn(key));
    self.mmToggle[key] = on;

    if(on)
        self iprintln(label + " ^2ON");
    else
        self iprintln(label + " ^1OFF");
    return on;
}

// Flips a flag and starts/stops a looping thread. Loop must "endon" mm_stop_<key>.
MM_Toggle(key, label, loopFunc)
{
    on = self MM_Flip(key, label);
    if(on)
        self thread [[loopFunc]]();
    else
        self notify("mm_stop_" + key);
    return on;
}

MM_Forward(dist)
{
    ang = self getPlayerAngles();
    return self.origin + (anglesToForward((0, ang[1], 0)) * dist);
}

MM_CrosshairPos()
{
    eye = self getEye();
    dir = anglesToForward(self getPlayerAngles());
    trace = bulletTrace(eye, eye + (dir * 10000), false, self);
    return trace["position"];
}

MM_WeaponKnown(weap)
{
    if(!isDefined(weap) || weap == "" || weap == "none")
        return false;
    if(isDefined(level.zombie_weapons) && isDefined(level.zombie_weapons[weap]))
        return true;
    if(isDefined(level.zombie_weapons_upgraded) && isDefined(level.zombie_weapons_upgraded[weap]))
        return true;
    return false;
}

MM_FirstKnownWeapon(a, b)
{
    if(MM_WeaponKnown(a))
        return a;
    if(MM_WeaponKnown(b))
        return b;
    return undefined;
}

MM_DefaultMaxHealth()
{
    if(self hasPerk("specialty_armorvest"))
        return 250;
    return 100;
}

MM_ZombieTeam()
{
    if(isDefined(level.zombie_team))
        return level.zombie_team;
    return "axis";
}

// Every live enemy AI (zombies, dogs, bosses).
MM_AllEnemies()
{
    out = [];
    all = getAiSpeciesArray(MM_ZombieTeam(), "all");

    if(!isDefined(all))
        return out;

    foreach(z in all)
    {
        if(isDefined(z) && isDefined(z.origin) && isAlive(z))
            out[out.size] = z;
    }
    return out;
}

MM_IsBoss(z)
{
    if(isDefined(z.is_brutus) && z.is_brutus)
        return true;
    if(isDefined(z.is_avogadro) && z.is_avogadro)
        return true;
    if(isDefined(z.is_sloth) && z.is_sloth)
        return true;
    if(isDefined(z.is_mechz) && z.is_mechz)
        return true;
    return false;
}

// Live enemies without quest bosses (Brutus, Avogadro, Sloth, Mechz), so that
// delete / teleport / freeze cannot break a map's boss logic.
MM_AliveZombies()
{
    out = [];
    all = MM_AllEnemies();
    foreach(z in all)
    {
        if(MM_IsBoss(z))
            continue;
        out[out.size] = z;
    }
    return out;
}

MM_PlayerStillHere(p)
{
    if(!isDefined(p))
        return false;
    players = get_players();
    foreach(pl in players)
    {
        if(pl == p)
            return true;
    }
    return false;
}

MM_Target()
{
    if(!MM_PlayerStillHere(self.selectedPlayer))
    {
        self iprintln("^1That player is no longer in the game.");
        return undefined;
    }
    return self.selectedPlayer;
}

MM_AddScore(player, amount)
{
    player maps\mp\zombies\_zm_score::add_to_player_score(amount);
}

// ============================================================================
//  PLAYERS MENU (HOST)
// ============================================================================

MM_BuildPlayersList()
{
    self.menuOpts["players"] = [];
    self.menuParents["players"] = "main";

    self addMenuOpt("players", "Refresh Player List", ::PopulatePlayersMenu);
    self addToggleOpt("players", "Auto Revive All Teammates", ::MM_ToggleTeamRevive, "teamrevive");
    self addMenuOpt("players", "Revive All Players", ::ReviveAllPlayers);
    self addMenuOpt("players", "Give All Players 100k", ::GiveAllPoints);
    self addMenuOpt("players", "Kill All Players (not me)", ::KillAllPlayers);

    players = get_players();
    foreach(player in players)
    {
        if(player == self)
            continue;

        tag = "";
        if(player is_bot())
            tag = "[BOT] ";
        self addMenuOpt("players", "Manage: " + tag + player.name, ::SelectPlayer, player);
    }
    self.menuParents["player_actions"] = "players";
}

PopulatePlayersMenu()
{
    self MM_BuildPlayersList();
    self MM_ClampCursor();
    self UpdateMenuUI();
    self iprintln("Player list refreshed.");
}

SelectPlayer(player)
{
    self.selectedPlayer = player;
    self SwitchMenu("player_actions");
}

ActionGiveMenu()
{
    p = self MM_Target();
    if(!isDefined(p))
        return;

    if(p is_bot())
    {
        self iprintln("^1Bots can't use the menu.");
        return;
    }

    if(isDefined(p.menuSetup) && p.menuSetup)
    {
        self iprintln(p.name + " already has the menu.");
        return;
    }
    p MM_GrantMenu();
    self iprintln("Gave menu to " + p.name);
    p iprintlnbold("^2You have been given the Mod Menu by the Host!");
}

ActionTakeMenu()
{
    p = self MM_Target();
    if(!isDefined(p))
        return;

    if(!isDefined(p.menuSetup) || !p.menuSetup)
    {
        self iprintln(p.name + " doesn't have the menu.");
        return;
    }
    p MM_RevokeMenu();
    self iprintln("Took menu from " + p.name);
    p iprintlnbold("^1Your Mod Menu access was revoked.");
}

ActionGodMode()
{
    p = self MM_Target();
    if(!isDefined(p))
        return;

    on = p MM_Toggle("god", "God Mode", ::GodLoop);
    if(on)
        self iprintln("God Mode ^2GIVEN ^7to " + p.name);
    else
    {
        p disableInvulnerability();
        self iprintln("God Mode ^1REMOVED ^7from " + p.name);
    }
}

ActionBoundary()
{
    p = self MM_Target();
    if(!isDefined(p))
        return;

    on = p MM_Flip("noboundary", "Free-Roam / Death-Barrier Bypass");
    if(on)
    {
        p notify("stop_player_out_of_playable_area_monitor");
        self iprintln("^2Disabled map death monitor for " + p.name);
    }
    else
    {
        p thread maps\mp\zombies\_zm::player_out_of_playable_area_monitor();
        self iprintln("^1Restored map death monitor for " + p.name);
    }
}

ActionGivePerks()
{
    p = self MM_Target();
    if(!isDefined(p))
        return;
    p MM_GivePerks();
    self iprintln("Perks given to " + p.name);
}

ActionPoints()
{
    p = self MM_Target();
    if(!isDefined(p))
        return;
    MM_AddScore(p, 100000);
    self iprintln("Gave 100k to " + p.name);
}

ActionRevive()
{
    p = self MM_Target();
    if(!isDefined(p))
        return;
    if(p maps\mp\zombies\_zm_laststand::player_is_in_laststand())
    {
        p maps\mp\zombies\_zm_laststand::auto_revive(self);
        self iprintln("Revived " + p.name);
    }
    else
        self iprintln(p.name + " is not downed.");
}

ActionTeleportTo()
{
    p = self MM_Target();
    if(!isDefined(p))
        return;
    self setOrigin(p.origin);
    self iprintln("Teleported to " + p.name);
}

ActionBring()
{
    p = self MM_Target();
    if(!isDefined(p))
        return;
    p setOrigin(self.origin);
    self iprintln("Brought " + p.name);
}

ActionSendToMoon()
{
    p = self MM_Target();
    if(!isDefined(p))
        return;
    p setVelocity((0, 0, 1500));
    self iprintln("Launched " + p.name);
}

ActionFreeze()
{
    p = self MM_Target();
    if(!isDefined(p))
        return;

    if(!isDefined(p.isFrozen) || !p.isFrozen)
    {
        p.isFrozen = true;
        p freezeControls(true);
        self iprintln("Froze " + p.name);
    }
    else
    {
        p.isFrozen = false;
        p freezeControls(false);
        self iprintln("Unfroze " + p.name);
    }
}

// Kills a player outright. God mode, noclip and freeze are cleared first so
// nothing can block the kill. Works on bots too.
MM_KillPlayer(p)
{
    if(!isDefined(p) || !isAlive(p))
        return false;

    p notify("mm_stop_god");
    p notify("mm_stop_noclip");
    if(!isDefined(p.mmToggle))
        p.mmToggle = [];
    p.mmToggle["god"] = false;
    p.mmToggle["noclip"] = false;

    p disableInvulnerability();
    p unlink();

    if(isDefined(p.isFrozen) && p.isFrozen)
    {
        p.isFrozen = false;
        p freezeControls(false);
    }

    p suicide();
    return true;
}

ActionKill()
{
    p = self MM_Target();
    if(!isDefined(p))
        return;

    if(p == self)
    {
        self iprintln("^1Use Suicide in Personal Mods to kill yourself.");
        return;
    }

    if(self MM_KillPlayer(p))
        self iprintln("Killed " + p.name);
    else
        self iprintln(p.name + " is already dead.");
}

KillAllPlayers()
{
    players = get_players();
    count = 0;
    foreach(player in players)
    {
        if(player == self)
            continue;
        if(self MM_KillPlayer(player))
            count++;
    }
    self iprintln("Killed " + count + " player(s)");
}

ReviveAllPlayers()
{
    players = get_players();
    foreach(player in players)
    {
        if(player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            player maps\mp\zombies\_zm_laststand::auto_revive(self);
    }
    self iprintln("All downed players revived");
}

GiveAllPoints()
{
    players = get_players();
    foreach(player in players)
        MM_AddScore(player, 100000);
    self iprintln("Gave 100k to everyone");
}

// ============================================================================
//  PERSONAL MODS
// ============================================================================

ToggleGodMode()
{
    if(self MM_Toggle("god", "God Mode", ::GodLoop))
        return;
    self disableInvulnerability();
}

GodLoop()
{
    self endon("disconnect");
    self endon("mm_stop_god");

    // God Mode also bypasses the stock out-of-playable-area death monitor.
    // Keep this as a separate persistent toggle so turning God Mode off does
    // not unexpectedly re-enable map boundaries if the player chose free-roam.
    self MM_EnableGodBoundaryBypass();

    for(;;)
    {
        self enableInvulnerability();   // re-applied because revives clear it
        wait 0.5;
    }
}

// Enable the same per-player bypass used by the Free-Roam menu. This stops
// BO2's stock kill_brush / player_volume monitor from killing this player.
MM_EnableGodBoundaryBypass()
{
    if(!isDefined(self.mmToggle))
        self.mmToggle = [];

    if(!self MM_IsOn("noboundary"))
    {
        self.mmToggle["noboundary"] = true;
        self iprintln("^2God Mode: out-of-map death monitor disabled.");
    }

    self notify("stop_player_out_of_playable_area_monitor");
}

ToggleNoclip()
{
    if(self MM_Toggle("noclip", "Noclip", ::NoclipLoop))
    {
        // The stock BO2 out-of-playable-area monitor kills players even when
        // God Mode is active. Noclip therefore enables its per-player bypass.
        if(!self MM_IsOn("noboundary"))
        {
            self.mmToggle["noboundary"] = true;
            self notify("stop_player_out_of_playable_area_monitor");
            self iprintln("^2Free-roam death-barrier bypass enabled.");
        }
        return;
    }
    self unlink();
}

NoclipLoop()
{
    self endon("disconnect");
    self endon("mm_stop_noclip");

    obj = spawn("script_origin", self.origin);
    obj.angles = self.angles;
    self playerLinkTo(obj);
    self thread MM_NoclipCleanup(obj);
    if(!isDefined(self.mmNoclipSpeed))
        self.mmNoclipSpeed = 40;
    self iprintln("Noclip: Attack forward | ADS backward | Frag up | Tactical down");

    for(;;)
    {
        speed = self.mmNoclipSpeed;
        forward = anglesToForward(self getPlayerAngles());

        if(self attackButtonPressed())
            obj.origin = obj.origin + (forward * speed);
        if(self adsButtonPressed())
            obj.origin = obj.origin - (forward * speed);
        if(self fragButtonPressed())
            obj.origin = obj.origin + (0, 0, speed * 0.65);
        if(self secondaryOffhandButtonPressed())
            obj.origin = obj.origin - (0, 0, speed * 0.65);
        wait 0.05;
    }
}

MM_NoclipCleanup(obj)
{
    self waittill_any("disconnect", "mm_stop_noclip");
    if(isDefined(obj))
        obj delete();
}

ToggleJetpack()      { self MM_Toggle("jetpack", "Jetpack", ::JetpackLoop); }
JetpackLoop()
{
    self endon("disconnect");
    self endon("mm_stop_jetpack");
    for(;;)
    {
        if(self jumpButtonPressed() && !self.menuOpen)
        {
            vel = self getVelocity();
            if(vel[2] < 600)
                self setVelocity(vel + (0, 0, 60));
        }
        wait 0.05;
    }
}

ToggleSuperJump()    { self MM_Toggle("superjump", "Super Jump", ::SuperJumpLoop); }
SuperJumpLoop()
{
    self endon("disconnect");
    self endon("mm_stop_superjump");
    for(;;)
    {
        if(self jumpButtonPressed() && self isOnGround() && !self.menuOpen)
        {
            wait 0.1;
            self setVelocity(self getVelocity() + (0, 0, 400));
            wait 0.5;
        }
        wait 0.05;
    }
}

ToggleBhop()         { self MM_Toggle("bhop", "Auto-Bhop", ::BhopLoop); }
BhopLoop()
{
    self endon("disconnect");
    self endon("mm_stop_bhop");
    for(;;)
    {
        if(self jumpButtonPressed() && self isOnGround() && !self.menuOpen)
        {
            ang = self getPlayerAngles();
            vec = anglesToForward((0, ang[1], 0));
            self setVelocity(self getVelocity() + (vec[0] * 250, vec[1] * 250, 150));
            wait 0.1;
        }
        wait 0.05;
    }
}

ToggleVampire()      { self MM_Toggle("vampire", "Vampire Mode", ::VampireLoop); }
VampireLoop()
{
    self endon("disconnect");
    self endon("mm_stop_vampire");
    last = self.score;
    for(;;)
    {
        if(self.score > last)
            self.health = self.maxhealth;
        last = self.score;
        wait 0.1;
    }
}

ToggleMovementAmmo() { self MM_Toggle("moveammo", "Move = Refill Ammo", ::MoveAmmoLoop); }
MoveAmmoLoop()
{
    self endon("disconnect");
    self endon("mm_stop_moveammo");
    for(;;)
    {
        if(length(self getVelocity()) > 10)
            self MM_RefillCurrent();
        wait 0.1;
    }
}

ToggleMagicBullets() { self MM_Toggle("magic", "Magic Bullets", ::MagicBulletsLoop); }
MagicBulletsLoop()
{
    self endon("disconnect");
    self endon("mm_stop_magic");

    weap = MM_FirstKnownWeapon("raygun_mark2_upgraded_zm", "ray_gun_upgraded_zm");
    if(!isDefined(weap))
    {
        self iprintln("^1No Ray Gun on this map.");
        self.mmToggle["magic"] = false;
        return;
    }

    for(;;)
    {
        self waittill("weapon_fired");
        eye = self getEye();
        dir = anglesToForward(self getPlayerAngles());
        magicBullet(weap, eye + (dir * 30), eye + (dir * 9999), self);
    }
}

ToggleHealth()
{
    if(self MM_Flip("health", "Super Health"))
    {
        self setMaxHealth(99999);
        self.health = 99999;
    }
    else
    {
        self setMaxHealth(self MM_DefaultMaxHealth());
        self.health = self.maxhealth;
    }
}

ToggleIgnoreMe()
{
    self.ignoreme = self MM_Flip("ignore", "Zombies Ignore You");
}

ToggleSpeed()
{
    if(self MM_Flip("speed", "Max Speed"))
        self setMoveSpeedScale(2.0);
    else
        self setMoveSpeedScale(1.0);
}

ToggleInvis()
{
    if(self MM_Flip("invis", "Invisibility"))
        self hide();
    else
        self show();
}

ToggleThirdPerson()
{
    if(self MM_Flip("thirdp", "Third Person"))
        self setClientThirdPerson(1);
    else
        self setClientThirdPerson(0);
}

SetFOV(val)
{
    self setClientDvar("cg_fov", val);
    self iprintln("FOV set to " + val);
}

GivePoints()
{
    MM_AddScore(self, 100000);
    self iprintln("Given ^2+100,000 ^7points");
}

ToggleInfPoints()    { self MM_Toggle("infpoints", "Infinite Points", ::InfPointsLoop); }
InfPointsLoop()
{
    self endon("disconnect");
    self endon("mm_stop_infpoints");
    for(;;)
    {
        if(self.score < 500000)
            MM_AddScore(self, 1000000);
        wait 1;
    }
}

SavePosition()
{
    self.mmSavedPos = self.origin;
    self.mmSavedAng = self getPlayerAngles();
    self iprintln("Position ^2saved");
}

LoadPosition()
{
    if(!isDefined(self.mmSavedPos))
    {
        self iprintln("^1No saved position.");
        return;
    }
    self setOrigin(self.mmSavedPos);
    self setPlayerAngles(self.mmSavedAng);
    self iprintln("Position ^2loaded");
}

TeleportToCrosshair()
{
    self setOrigin(self MM_CrosshairPos() + (0, 0, 10));
    self iprintln("Teleported");
}

DoSuicide()
{
    self suicide();
}

// ============================================================================
//  WEAPONS & PERKS
// ============================================================================

ToggleInfAmmo()      { self MM_Toggle("infammo", "Infinite Ammo", ::InfAmmoLoop); }
InfAmmoLoop()
{
    self endon("disconnect");
    self endon("mm_stop_infammo");
    for(;;)
    {
        self MM_RefillCurrent();
        wait 0.1;
    }
}

// Refills clip + reserve of one weapon, including its dual-wield and
// alternate (underbarrel) halves.
MM_RefillWeapon(weap)
{
    if(!isDefined(weap) || weap == "none" || weap == "")
        return;

    self setWeaponAmmoClip(weap, weaponClipSize(weap));

    dw = weaponDualWieldWeaponName(weap);
    if(isDefined(dw) && dw != "none" && dw != "")
        self setWeaponAmmoClip(dw, weaponClipSize(dw));

    alt = weaponAltWeaponName(weap);
    if(isDefined(alt) && alt != "none" && alt != "")
        self setWeaponAmmoClip(alt, weaponClipSize(alt));

    self giveMaxAmmo(weap);
}

MM_RefillCurrent()
{
    self MM_RefillWeapon(self getCurrentWeapon());
}

FillCurrentAmmo()
{
    self MM_RefillCurrent();
    self iprintln("Ammo filled");
}

FillAllAmmo()
{
    prim = self getWeaponsListPrimaries();
    foreach(w in prim)
        self MM_RefillWeapon(w);
    self iprintln("All ammo filled");
}

GiveWeap(weap)
{
    if(!MM_WeaponKnown(weap))
    {
        self iprintln("^1That weapon is not loaded on this map.");
        return;
    }

    // Let the game handle weapon limits, PaP camos, equipment and melee slots.
    self maps\mp\zombies\_zm_weapons::weapon_give(weap, isSubStr(weap, "upgraded"));
    self iprintln("Weapon given");
}

// Two-slot heavy loadout. Each weapon is checked against the active map
// registry before the stock Zombies weapon-give routine is called.
MM_GiveRocketLoadout()
{
    given = 0;

    if(MM_WeaponKnown("usrpg_zm"))
    {
        self maps\mp\zombies\_zm_weapons::weapon_give("usrpg_zm", false);
        given++;
    }
    else if(MM_WeaponKnown("usrpg_upgraded_zm"))
    {
        self maps\mp\zombies\_zm_weapons::weapon_give("usrpg_upgraded_zm", true);
        given++;
    }

    if(MM_WeaponKnown("m32_zm"))
    {
        self maps\mp\zombies\_zm_weapons::weapon_give("m32_zm", false);
        given++;
    }
    else if(MM_WeaponKnown("m32_upgraded_zm"))
    {
        self maps\mp\zombies\_zm_weapons::weapon_give("m32_upgraded_zm", true);
        given++;
    }

    if(given > 0)
        self iprintln("^2Heavy loadout granted. Check your weapon slots.");
    else
        self iprintln("^1Neither rocket weapon is available on this map.");
}

// Returns the Pack-a-Punched version of a weapon, or undefined if it has none.
MM_UpgradeOf(weap)
{
    if(!isDefined(weap) || weap == "none" || weap == "")
        return undefined;

    weap = self maps\mp\zombies\_zm_weapons::switch_from_alt_weapon(weap);
    base = maps\mp\zombies\_zm_weapons::get_base_name(weap);

    if(!MM_WeaponKnown(base))
        return undefined;
    if(isSubStr(base, "upgraded"))
        return undefined;
    if(!maps\mp\zombies\_zm_weapons::can_upgrade_weapon(base))
        return undefined;

    return maps\mp\zombies\_zm_weapons::get_upgrade_weapon(base);
}

PapCurrentWeapon()
{
    weap = self getCurrentWeapon();
    weap = self maps\mp\zombies\_zm_weapons::switch_from_alt_weapon(weap);

    if(isSubStr(weap, "upgraded"))
    {
        self iprintln("Already Pack-a-Punched");
        return;
    }

    upg = self MM_UpgradeOf(weap);
    if(!isDefined(upg))
    {
        self iprintln("^1This weapon can't be upgraded");
        return;
    }

    self takeWeapon(weap);
    self maps\mp\zombies\_zm_weapons::weapon_give(upg, true);
    self giveMaxAmmo(upg);
    self iprintln("Weapon upgraded!");
}

PapAllWeapons()
{
    count = 0;
    current = self getCurrentWeapon();
    current = self maps\mp\zombies\_zm_weapons::switch_from_alt_weapon(current);
    newCurrent = undefined;

    prim = self getWeaponsListPrimaries();
    foreach(w in prim)
    {
        if(isSubStr(w, "upgraded"))
            continue;

        upg = self MM_UpgradeOf(w);
        if(!isDefined(upg))
            continue;

        self takeWeapon(w);
        self maps\mp\zombies\_zm_weapons::weapon_give(upg, true);
        self giveMaxAmmo(upg);
        if(w == current)
            newCurrent = upg;
        count++;
    }

    if(isDefined(newCurrent))
        self switchToWeapon(newCurrent);
    self iprintln("Upgraded " + count + " weapon(s)");
}

DropWeapon()
{
    primaries = self getWeaponsListPrimaries();
    if(primaries.size < 2)
    {
        self iprintln("^1Can't drop your only weapon");
        return;
    }
    weap = self getCurrentWeapon();
    self dropItem(weap);
    self iprintln("Weapon dropped");
}

// Unlock every persistent upgrade registered by the active classic ZM map.
// The stock monitor awards each upgrade and runs its normal activation thread.
MM_GiveAllPersistentUpgrades()
{
    if(!isDefined(level.pers_upgrades) || !isDefined(level.pers_upgrades_keys) || level.pers_upgrades_keys.size < 1)
    {
        self iprintln("^1No Persistent Upgrades are registered on this map.");
        self iprintln("^7Perma-Perks are available in classic TranZit, Die Rise and Buried.");
        return;
    }

    if(!maps\mp\zombies\_zm_pers_upgrades::is_pers_system_active())
    {
        self iprintln("^1Perma-Perks are disabled in this game mode.");
        return;
    }

    if(isDefined(level.zm_disable_recording_stats) && level.zm_disable_recording_stats)
    {
        self iprintln("^1Stats recording is disabled; permanent unlocks cannot be saved.");
        return;
    }

    if(!isDefined(self.stats_this_frame))
        self.stats_this_frame = [];

    changedStats = 0;
    foreach(upgradeName in level.pers_upgrades_keys)
    {
        if(!isDefined(level.pers_upgrades[upgradeName]))
            continue;

        upgrade = level.pers_upgrades[upgradeName];
        if(!isDefined(upgrade.stat_names) || !isDefined(upgrade.stat_desired_values))
            continue;

        statCount = upgrade.stat_names.size;
        if(upgrade.stat_desired_values.size < statCount)
            statCount = upgrade.stat_desired_values.size;

        for(i = 0; i < statCount; i++)
        {
            statName = upgrade.stat_names[i];
            desiredValue = upgrade.stat_desired_values[i];
            if(!isDefined(statName) || !isDefined(desiredValue))
                continue;

            currentValue = self maps\mp\zombies\_zm_stats::get_global_stat(statName);
            if(!isDefined(currentValue))
                currentValue = 0;

            // Never reduce an existing stat value; only raise it to the unlock threshold.
            if(currentValue < desiredValue)
            {
                self maps\mp\zombies\_zm_stats::set_client_stat(statName, desiredValue, 0);
                changedStats++;
            }
        }
    }

    // Let the stat-recording threads finish before asking the stock monitor to test.
    wait 0.1;
    self.pers_upgrade_force_test = 1;
    wait 0.25;

    unlocked = 0;
    foreach(upgradeName in level.pers_upgrades_keys)
    {
        if(isDefined(self.pers_upgrades_awarded[upgradeName]) && self.pers_upgrades_awarded[upgradeName])
            unlocked++;
    }

    self iprintlnbold("^2PERMA-PERK UNLOCK CHECK COMPLETE");
    self iprintln("^7Unlocked: ^2" + unlocked + " ^7/ ^2" + level.pers_upgrades_keys.size + " ^7available upgrades");

    if(unlocked < level.pers_upgrades_keys.size)
        self iprintln("^3Some upgrades were not confirmed. Check the current map, mode and stat settings.");
}

// Collect every perk the current map actually registers:
// - physical vending-machine triggers;
// - map-specific random-perk pools (Origins Wunderfizz includes perks
//   that do not have their own permanent vending-machine entity);
// - registered custom perks supplied by the current map.
MM_GetAvailablePerks()
{
    perks = [];

    machines = getEntArray("zombie_vending", "targetname");
    if(isDefined(machines))
    {
        foreach(machine in machines)
        {
            if(!isDefined(machine) || !isDefined(machine.script_noteworthy))
                continue;

            perk = machine.script_noteworthy;
            found = false;
            foreach(existing in perks)
            {
                if(existing == perk)
                {
                    found = true;
                    break;
                }
            }

            if(!found)
                perks[perks.size] = perk;
        }
    }

    // This is the same map-specific pool the Wunderfizz uses. The values,
    // rather than array indexes, are the actual specialty_* perk identifiers.
    if(isDefined(level._random_perk_machine_perk_list))
    {
        randomKeys = getarraykeys(level._random_perk_machine_perk_list);
        foreach(key in randomKeys)
        {
            perk = level._random_perk_machine_perk_list[key];
            if(!isDefined(perk))
                continue;

            found = false;
            foreach(existing in perks)
            {
                if(existing == perk)
                {
                    found = true;
                    break;
                }
            }

            if(!found)
                perks[perks.size] = perk;
        }
    }

    // Include any other custom perk registered by this map.    if(isDefined(level._custom_perks))
    {
        customKeys = getarraykeys(level._custom_perks);
        foreach(perk in customKeys)
        {
            if(!isDefined(perk))
                continue;

            found = false;
            foreach(existing in perks)
            {
                if(existing == perk)
                {
                    found = true;
                    break;
                }
            }

            if(!found)
                perks[perks.size] = perk;
        }
    }

    return perks;
}

// Gives all available perks, not only perks with a physical vending machine.
MM_GivePerks()
{
    perks = self MM_GetAvailablePerks();
    given = 0;

    foreach(perk in perks)
    {
        if(!isDefined(perk) || self hasPerk(perk))
            continue;

        self maps\mp\zombies\_zm_perks::give_perk(perk, false);
        given++;
        wait 0.20;
    }

    return given;
}

GiveAllPerks()
{
    perks = self MM_GetAvailablePerks();
    given = self MM_GivePerks();

    self iprintln("^2Gave " + given + " available perks ^7(" + perks.size + " recognized)");
}

RemoveAllPerks()
{
    perks = self MM_GetAvailablePerks();
    removed = 0;

    foreach(perk in perks)
    {
        if(isDefined(perk) && self hasPerk(perk))
        {
            self notify(perk + "_stop");
            removed++;
        }
    }

    self iprintln("^2Removed " + removed + " available perks");
}

// ============================================================================
//  SURVIVAL, AUTOMATION & QUALITY-OF-LIFE
// ============================================================================

MM_GiveScore(amount)
{
    if(amount < 1)
        return;
    MM_AddScore(self, amount);
    self iprintln("^2+" + amount + " points");
}

MM_RefillHealth()
{
    if(self MM_IsOn("health"))
    {
        self setMaxHealth(99999);
        self.health = 99999;
    }
    else
        self.health = self.maxhealth;
    self iprintln("^2Health restored");
}

MM_ResetMovement()
{
    self setMoveSpeedScale(1.0);
    self.mmMoveScale = 1.0;
    self setVelocity((0, 0, 0));
    if(self MM_IsOn("noclip"))
    {
        self.mmToggle["noclip"] = false;
        self notify("mm_stop_noclip");
        self unlink();
    }
    self iprintln("^2Movement settings restored");
}

MM_ResetWorld()
{
    setDvar("g_gravity", 800);
    setDvar("timescale", 1.0);
    self iprintln("^2World reset: gravity 800, game speed 1.0");
}

MM_AdvanceRound(amount)
{
    if(amount < 1)
        return;
    targetRound = level.round_number + amount + 1;
    SetRound(targetRound);
}

MM_ToggleAutoRevive()
{
    self MM_Toggle("autorevive", "Auto Revive", ::MM_AutoReviveLoop);
}

MM_AutoReviveLoop()
{
    self endon("disconnect");
    self endon("mm_stop_autorevive");
    for(;;)
    {
        if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            self maps\mp\zombies\_zm_laststand::auto_revive(self);
        wait 0.20;
    }
}

MM_ToggleTeamRevive()
{
    self MM_Toggle("teamrevive", "Auto Revive Team", ::MM_TeamReviveLoop);
}

MM_TeamReviveLoop()
{
    self endon("disconnect");
    self endon("mm_stop_teamrevive");
    for(;;)
    {
        players = get_players();
        foreach(player in players)
        {
            if(!isDefined(player))
                continue;
            if(player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
                player maps\mp\zombies\_zm_laststand::auto_revive(self);
        }
        wait 0.20;
    }
}

MM_ToggleAutoPerks()
{
    self MM_Toggle("autoperks", "Auto Rebuy Perks", ::MM_AutoPerksLoop);
}

MM_AutoPerksLoop()
{
    self endon("disconnect");
    self endon("mm_stop_autoperks");
    for(;;)
    {
        if(!self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            self MM_GivePerks();
        wait 3.0;
    }
}

MM_ToggleInfAmmoAll()
{
    self MM_Toggle("infammoall", "Infinite Ammo (All Weapons)", ::MM_InfAmmoAllLoop);
}

MM_InfAmmoAllLoop()
{
    self endon("disconnect");
    self endon("mm_stop_infammoall");
    for(;;)
    {
        primaries = self getWeaponsListPrimaries();
        foreach(weap in primaries)
            self MM_RefillWeapon(weap);
        wait 0.20;
    }
}

// ============================================================================
 // LIVE EASTER EGG TRACKER - Mob of the Dead, TranZit, Buried and Die Rise
 // Reads the stock quest flags / sidequest stats; it does not change quest state.
 // ============================================================================

MM_EETrackerAvailable()
{
    return level.script == "zm_prison" || level.script == "zm_transit" || level.script == "zm_buried" || level.script == "zm_highrise";
}

MM_EETrackerInit()
{
    if(!self MM_EETrackerAvailable())
        return;

    if(!isDefined(self.mmToggle))
        self.mmToggle = [];

    if(!isDefined(self.mmToggle["eetracker"]))
        self.mmToggle["eetracker"] = true;

    if(!isDefined(self.mmEETrackerStarted) || !self.mmEETrackerStarted)
    {
        self.mmEETrackerStarted = true;
        self thread MM_EETrackerLoop();
    }
}

MM_ToggleEETracker()
{
    self MM_Flip("eetracker", "Easter Egg Tracker");
}

MM_EETrackerLoop()
{
    self endon("disconnect");
    hud = undefined;
    lastTrackerText = undefined;

    for(;;)
    {
        if(self MM_IsOn("eetracker"))
        {
            if(!isDefined(hud))
            {
                hud = self MM_NewText(385, 86, 0.68);
                hud.color = (0.85, 1, 0.85);
                hud.sort = 1003;
            }

            trackerText = self MM_EETrackerBuildText();
            if(!isDefined(lastTrackerText) || lastTrackerText != trackerText)
            {
                hud setText(trackerText);
                lastTrackerText = trackerText;
            }
        }
        else if(isDefined(hud))
        {
            hud destroy();
            hud = undefined;
        }

        wait 0.45;
    }

    if(isDefined(hud))
        hud destroy();
}

MM_EETrackerStatus(done)
{
    if(done)
        return "^2[OK]";
    return "^1[--]";
}

MM_EETrackerStageMark(stepIndex, currentIndex, questDone)
{
    if(questDone || stepIndex < currentIndex)
        return "^2[OK]";
    if(stepIndex == currentIndex)
        return "^3[NOW]";
    return "^1[--]";
}

MM_EETrackerStat(statName)
{
    value = self maps\mp\zombies\_zm_stats::get_global_stat(statName);
    if(!isDefined(value))
        value = 0;
    return value;
}

MM_EETrackerBuildText()
{
    if(level.script == "zm_prison")
        return self MM_EETrackerMob();
    if(level.script == "zm_transit")
        return self MM_EETrackerTranzit();
    if(level.script == "zm_buried")
        return self MM_EETrackerBuried();
    if(level.script == "zm_highrise")
        return self MM_EETrackerDieRise();

    return "^1EASTER EGG TRACKER\n^7This map is not supported.";
}

MM_EETrackerMob()
{
    dogs = flag("quest_completed_thrice");
    spoon = flag("spoon_obtained");
    blundergat = flag("warden_blundergat_obtained");
    nixie = flag("nixie_puzzle_completed");
    planeBuilt = flag("plane_built");
    boarded = flag("plane_boarded");
    departed = flag("plane_departed");
    zapped = flag("plane_zapped");
    crashed = flag("plane_crashed");

    keyFound = flag("key_found");
    parts = 0;
    if(flag("cloth_found")) parts++;
    if(flag("fueltanks_found")) parts++;
    if(flag("engine_found")) parts++;
    if(flag("steering_found")) parts++;
    if(flag("rigging_found")) parts++;

    goodEnding = self MM_EETrackerStat("prison_ee_good_ending") > 0;
    badEnding = self MM_EETrackerStat("prison_ee_bad_ending") > 0;

    endingText = "^3Pending";
    if(goodEnding)
        endingText = "^2Crew victory";
    else if(badEnding)
        endingText = "^1Weasel victory";

    nextText = "Complete the prerequisite quests";
    if(dogs && spoon && blundergat && !nixie)
        nextText = "Solve all four Nixie-tube codes";
    else if(nixie && !planeBuilt)
        nextText = "Follow the audio logs and assemble the plane";
    else if(planeBuilt && !boarded)
        nextText = "Board the plane for the final flight";
    else if(boarded && !departed)
        nextText = "Wait for take-off";
    else if(departed && !zapped)
        nextText = "Reach the Golden Gate Bridge";
    else if(zapped && !crashed)
        nextText = "Finish the crash sequence";
    else if(crashed && !goodEnding && !badEnding)
        nextText = "Finish the final Weasel showdown";

    return "^2MOB OF THE DEAD - POP GOES THE WEASEL"
        + "\\n^7Three dog heads: " + self MM_EETrackerStatus(dogs)
        + "   Spoon: " + self MM_EETrackerStatus(spoon)
        + "\\n^7Warden's Blundergat: " + self MM_EETrackerStatus(blundergat)
        + "   Nixie codes: " + self MM_EETrackerStatus(nixie)
        + "\\n^7Quest key: " + self MM_EETrackerStatus(keyFound)
        + "   Plane parts: ^3" + parts + "/5"
        + "   Build: " + self MM_EETrackerStatus(planeBuilt)
        + "\\n^7Flight: Board " + self MM_EETrackerStatus(boarded)
        + " Depart " + self MM_EETrackerStatus(departed)
        + "\\n^7Bridge " + self MM_EETrackerStatus(zapped)
        + " Crash " + self MM_EETrackerStatus(crashed)
        + "\\n^7Ending: " + endingText
        + "\\n^3NEXT: ^7" + nextText;
}

MM_EETrackerTranzit()
{
    navcard = self MM_EETrackerStat("navcard_applied_zm_transit") > 0;

    // These stock counters are advanced by the original Maxis / Richtofen quest scripts.
    maxA = self MM_EETrackerStat("sq_transit_maxis_stage_2") > 0;
    maxB = self MM_EETrackerStat("sq_transit_maxis_stage_3") > 0;
    maxC = self MM_EETrackerStat("sq_transit_maxis_complete") > 0;
    richA = self MM_EETrackerStat("sq_transit_rich_stage_2") > 0;
    richB = self MM_EETrackerStat("sq_transit_rich_stage_3") > 0;
    richC = self MM_EETrackerStat("sq_transit_rich_complete") > 0;

    maxNext = "Place two powered turbines at the tower";
    if(maxA)
        maxNext = "Stun Avogadro at the tower";
    if(maxB)
        maxNext = "Finish the remaining Maxis light tasks";
    if(maxC)
        maxNext = "Maxis route complete";

    richNext = "Build the Jet Gun and fire it at the tower";
    if(richA)
        richNext = "Lure 25 zombies into the tower";
    if(richB)
        richNext = "EMP the four safety lights";
    if(richC)
        richNext = "Richtofen route complete";

    return "^2TRANZIT - TOWER EASTER EGG"
        + "\\n^7Navcard applied: " + self MM_EETrackerStatus(navcard)
        + "\\n^7MAXIS A/B/C: " + self MM_EETrackerStatus(maxA)
        + " " + self MM_EETrackerStatus(maxB)
        + " " + self MM_EETrackerStatus(maxC)
        + "\\n^7M NEXT: ^3" + maxNext
        + "\\n^7RICHTOFEN A/B/C: " + self MM_EETrackerStatus(richA)
        + " " + self MM_EETrackerStatus(richB)
        + " " + self MM_EETrackerStatus(richC)
        + "\\n^7R NEXT: ^3" + richNext;
}

MM_EETrackerDieRise()
{
    navBuilt = flag("sq_nav_built");
    navcard = self MM_EETrackerStat("navcard_applied_zm_highrise") > 0;
    dragon = flag("sq_atd_drg_puzzle_complete");
    lionBall = flag("sq_ball_picked_up");

    richtofenBalls = flag("ssp1_complete");
    richtofenPads = flag("pts_1_springpads_placed");
    maxisRebirth = flag("ssp2_resurrection_done") && flag("ssp2_statue_complete");
    maxisPads = flag("pts_2_springpads_placed");

    branchDone = flag("sq_branch_complete");
    towerActive = flag("sq_tower_active");
    richtofenDone = self MM_EETrackerStat("sq_highrise_rich_complete") > 0;
    maxisDone = self MM_EETrackerStat("sq_highrise_maxis_complete") > 0;

    stageName = "";
    if(isDefined(level._last_stage_started))
        stageName = level._last_stage_started;

    nextText = "Build the Navcard computer";
    if(navBuilt && !navcard)
        nextText = "Apply the correct Navcard";
    else if(navcard && !dragon)
        nextText = "Solve the dragon / elevator sequence";
    else if(dragon && !lionBall)
        nextText = "Shoot and collect the lion ball";
    else if(lionBall && !branchDone)
    {
        if(stageName == "ssp_1")
            nextText = "Richtofen: liquify both dragon balls";
        else if(stageName == "pts_1")
            nextText = "Richtofen: place spring pads and launch zombies";
        else if(stageName == "ssp_2")
            nextText = "Maxis: complete the corpse and reincarnation steps";
        else if(stageName == "pts_2")
            nextText = "Maxis: finish the generator spring-pad steps";
        else
            nextText = "Complete the active Richtofen or Maxis branch";
    }
    else if(branchDone && !towerActive)
        nextText = "Punch the tower legs in the displayed order";
    else if(towerActive && !richtofenDone && !maxisDone)
        nextText = "Finish the tower sequence";
    else if(richtofenDone || maxisDone)
        nextText = "Die Rise main quest complete";

    routeText = "Not selected";
    if(flag("sq_ric_tower_complete"))
        routeText = "Richtofen";
    else if(flag("sq_max_tower_complete"))
        routeText = "Maxis";

    return "^2DIE RISE - TOWER EASTER EGG"
        + "\\n^7Nav computer: " + self MM_EETrackerStatus(navBuilt)
        + "   Navcard: " + self MM_EETrackerStatus(navcard)
        + "\\n^7Dragon puzzle: " + self MM_EETrackerStatus(dragon)
        + "   Lion ball: " + self MM_EETrackerStatus(lionBall)
        + "\\n^7Richtofen balls / pads: " + self MM_EETrackerStatus(richtofenBalls)
        + " " + self MM_EETrackerStatus(richtofenPads)
        + "\\n^7Maxis rebirth / pads: " + self MM_EETrackerStatus(maxisRebirth)
        + " " + self MM_EETrackerStatus(maxisPads)
        + "\\n^7Route: ^3" + routeText
        + "   Tower: " + self MM_EETrackerStatus(towerActive)
        + "\\n^3NEXT: ^7" + nextText;
}

MM_EETrackerBuried()
{
    navBuilt = flag("sq_nav_built");
    navcard = self MM_EETrackerStat("navcard_applied_zm_buried") > 0;
    richDone = self MM_EETrackerStat("sq_buried_rich_complete") > 0;
    maxDone = self MM_EETrackerStat("sq_buried_maxis_complete") > 0;
    questDone = richDone || maxDone;

    routeText = "Not selected";
    if(flag("sq_is_ric_tower_built"))
        routeText = "Richtofen";
    else if(flag("sq_is_max_tower_built"))
        routeText = "Maxis";

    stageName = "";
    if(isDefined(level._last_stage_started))
        stageName = level._last_stage_started;

    stageIndex = -1;
    currentText = "Build a tower and start the side quest";
    if(stageName == "bt")
    {
        stageIndex = 0;
        currentText = "Build the first tower - place its four objects";
    }
    else if(stageName == "mta")
    {
        stageIndex = 1;
        currentText = "Complete the four amplifier task";
    }
    else if(stageName == "gl")
    {
        stageIndex = 2;
        currentText = "Find and collect the lantern";
    }
    else if(stageName == "ftl")
    {
        stageIndex = 3;
        currentText = "Charge the lantern with zombie souls";
    }
    else if(stageName == "ll")
    {
        stageIndex = 4;
        currentText = "Read the tunnel-sign code";
    }
    else if(stageName == "ts")
    {
        stageIndex = 5;
        currentText = "Activate the signs in the correct sequence";
    }
    else if(stageName == "ctw")
    {
        stageIndex = 6;
        currentText = "Guide the wisp to the guillotine";
    }
    else if(stageName == "tpo")
    {
        stageIndex = 7;
        currentText = "Complete the Time Bomb stage";
    }
    else if(stageName == "ip")
    {
        stageIndex = 8;
        currentText = "Solve the final button / lever puzzle";
    }
    else if(stageName == "ows")
    {
        stageIndex = 9;
        currentText = "Complete the moving-target challenge";
    }

    if(questDone)
        stageIndex = 10;

    nextText = currentText;
    if(!navBuilt)
        nextText = "Build the Navcard computer";
    else if(!navcard)
        nextText = "Apply the correct Navcard";
    else if(questDone)
        nextText = "Buried main quest complete";

    return "^2BURIED - MAZE / TOWER EASTER EGG"
        + "\\n^7Nav computer: " + self MM_EETrackerStatus(navBuilt)
        + "   Navcard: " + self MM_EETrackerStatus(navcard)
        + "\\n^7Route: ^3" + routeText
        + "   Wisp: " + self MM_EETrackerStatus(flag("sq_wisp_success"))
        + "\\n^7Stages  BT " + self MM_EETrackerStageMark(0, stageIndex, questDone)
        + "  MTA " + self MM_EETrackerStageMark(1, stageIndex, questDone)
        + "  GL " + self MM_EETrackerStageMark(2, stageIndex, questDone)
        + "  FTL " + self MM_EETrackerStageMark(3, stageIndex, questDone)
        + "  LL " + self MM_EETrackerStageMark(4, stageIndex, questDone)
        + "\\n^7        TS " + self MM_EETrackerStageMark(5, stageIndex, questDone)
        + "  CTW " + self MM_EETrackerStageMark(6, stageIndex, questDone)
        + "  TPO " + self MM_EETrackerStageMark(7, stageIndex, questDone)
        + "  IP " + self MM_EETrackerStageMark(8, stageIndex, questDone)
        + "  OWS " + self MM_EETrackerStageMark(9, stageIndex, questDone)
        + "\\n^7Current: ^3" + currentText
        + "\\n^3NEXT: ^7" + nextText;
}

// ============================================================================
 // QUEST OBJECT ESP — world waypoints for current Easter Egg objectives.
 // Uses stock map entities, structs and spawned quest models only.
 // ============================================================================

MM_EETrackerESPAvailable()
{
    return self MM_EETrackerAvailable();
}

MM_EEAddQuestTarget(targets, target, label)
{
    if(!isDefined(target) || !isDefined(target.origin))
        return targets;

    foreach(existing in targets)
    {
        if(isDefined(existing) && isDefined(existing.ent) && existing.ent == target)
            return targets;
    }

    item = spawnstruct();
    item.ent = target;
    item.label = label;
    targets[targets.size] = item;
    return targets;
}

MM_EEAddQuestEnt(targets, targetName, label)
{
    ent = getent(targetName, "targetname");
    return self MM_EEAddQuestTarget(targets, ent, label);
}

MM_EEAddQuestEntKey(targets, targetName, keyName, label)
{
    ent = getent(targetName, keyName);
    return self MM_EEAddQuestTarget(targets, ent, label);
}

MM_EEAddQuestEntArray(targets, targetName, keyName, label)
{
    ents = getentarray(targetName, keyName);
    foreach(ent in ents)
        targets = self MM_EEAddQuestTarget(targets, ent, label);
    return targets;
}

MM_EEAddQuestStruct(targets, structName, label)
{
    spot = getstruct(structName, "targetname");
    return self MM_EEAddQuestTarget(targets, spot, label);
}

MM_EEAddQuestStructArray(targets, structName, keyName, label)
{
    spots = getstructarray(structName, keyName);
    foreach(spot in spots)
        targets = self MM_EEAddQuestTarget(targets, spot, label);
    return targets;
}


MM_EEAddQuestStructKey(targets, structName, keyName, label)
{
    spot = getstruct(structName, keyName);
    return self MM_EEAddQuestTarget(targets, spot, label);
}

MM_EEAddQuestStructArrayNoKey(targets, structName, label)
{
    spots = getstructarray(structName);
    foreach(spot in spots)
        targets = self MM_EEAddQuestTarget(targets, spot, label);
    return targets;
}

// Same spawned-piece registry lookup used by Mob of the Dead's stock quest scripts.
MM_EEFindCraftablePieceModel(craftableName, pieceName)
{
    if(!isDefined(level.a_uts_craftables))
        return undefined;

    foreach(utsCraftable in level.a_uts_craftables)
    {
        if(!isDefined(utsCraftable) || !isDefined(utsCraftable.craftablestub) ||
           !isDefined(utsCraftable.craftablestub.name) ||
           utsCraftable.craftablestub.name != craftableName)
            continue;

        if(!isDefined(utsCraftable.craftablespawn) || !isDefined(utsCraftable.craftablespawn.a_piecespawns))
            return undefined;

        foreach(pieceSpawn in utsCraftable.craftablespawn.a_piecespawns)
        {
            if(isDefined(pieceSpawn) && isDefined(pieceSpawn.piecename) &&
               pieceSpawn.piecename == pieceName && isDefined(pieceSpawn.model))
                return pieceSpawn.model;
        }
    }
    return undefined;
}

MM_EEAddCraftablePieceTarget(targets, craftableName, pieceName, label)
{
    model = self MM_EEFindCraftablePieceModel(craftableName, pieceName);
    return self MM_EEAddQuestTarget(targets, model, label);
}

MM_EECollectQuestTargets()
{
    targets = [];

    if(level.script == "zm_prison")
        return self MM_EECollectMobTargets(targets);
    if(level.script == "zm_transit")
        return self MM_EECollectTranzitTargets(targets);
    if(level.script == "zm_highrise")
        return self MM_EECollectDieRiseTargets(targets);
    if(level.script == "zm_buried")
        return self MM_EECollectBuriedTargets(targets);

    return targets;
}

MM_EECollectMobTargets(targets)
{
    if(!flag("quest_completed_thrice") && isDefined(level.a_wolf_structs))
    {
        foreach(spot in level.a_wolf_structs)
            targets = self MM_EEAddQuestTarget(targets, spot, "WOLF HEAD");
    }

    if(!flag("spoon_obtained"))
    {
        targets = self MM_EEAddQuestEnt(targets, "pickup_spoon", "SPOON / SPORK");
        targets = self MM_EEAddQuestEnt(targets, "afterlife_show_spork", "SPOON / SPORK");
    }

    if(!flag("warden_blundergat_obtained"))
    {
        targets = self MM_EEAddQuestEnt(targets, "sq_bg_reward_pickup", "BLUNDERGAT REWARD");
        targets = self MM_EEAddQuestEntArray(targets, "sq_bg_macguffin", "targetname", "SKULL - RETRIEVER");
    }

    if(!flag("key_found"))
        targets = self MM_EEAddCraftablePieceTarget(targets, "quest_key1", "p6_zm_al_key", "WARDEN KEY");

    if(!flag("nixie_puzzle_completed"))
    {
        for(i = 1; i <= 3; i++)
            targets = self MM_EEAddQuestEnt(targets, "nixie_tube_" + i, "NIXIE TUBE " + i);
    }

    if(isDefined(level.m_headphones))
        targets = self MM_EEAddQuestTarget(targets, level.m_headphones, "AUDIO LOG");

    if(!flag("plane_built"))
    {
        if(!flag("cloth_found"))
            targets = self MM_EEAddCraftablePieceTarget(targets, "plane", "cloth", "PLANE CLOTH");
        if(!flag("fueltanks_found"))
            targets = self MM_EEAddCraftablePieceTarget(targets, "plane", "fueltanks", "PLANE FUEL TANKS");
        if(!flag("engine_found"))
            targets = self MM_EEAddCraftablePieceTarget(targets, "plane", "engine", "PLANE ENGINE");
        if(!flag("steering_found"))
            targets = self MM_EEAddCraftablePieceTarget(targets, "plane", "steering", "PLANE STEERING");
        if(!flag("rigging_found"))
            targets = self MM_EEAddCraftablePieceTarget(targets, "plane", "rigging", "PLANE RIGGING");

        targets = self MM_EEAddQuestEnt(targets, "plane_hideable_engine", "ENGINE PART");
        targets = self MM_EEAddQuestEnt(targets, "plane_hideable_clothes_pile", "CLOTH PART");
    }
    else if(!flag("plane_boarded"))
    {
        targets = self MM_EEAddQuestEnt(targets, "plane_fly_trigger", "BOARD THE PLANE");
        targets = self MM_EEAddQuestEntKey(targets, "plane_fly_afterlife_trigger", "script_noteworthy", "AFTERLIFE FLIGHT");
    }
    else if(!flag("plane_zapped") && !flag("plane_crashed"))
        targets = self MM_EEAddQuestEnt(targets, "plane_fly_trigger", "PLANE FLIGHT");

    if(flag("spawn_fuel_tanks") && !flag("plane_ready"))
    {
        for(fuelIndex = 1; fuelIndex <= 5; fuelIndex++)
            targets = self MM_EEAddCraftablePieceTarget(targets, "refuelable_plane", "fuel" + fuelIndex, "PLANE FUEL CAN");
        targets = self MM_EEAddQuestEnt(targets, "plane_fuelable_trigger", "REFUEL THE PLANE");
    }

    return targets;
}
MM_EECollectTranzitTargets(targets)
{
    navStarted = self MM_EETrackerStat("sq_transit_started") > 0;
    navApplied = self MM_EETrackerStat("navcard_applied_zm_transit") > 0;

    if(!navStarted || !navApplied)
    {
        targets = self MM_EEAddQuestEnt(targets, "sq_common_buildable_trigger", "BUILD NAVCARD TABLE");
        targets = self MM_EEAddQuestStruct(targets, "sq_common_key", "NAVCARD TABLE");
    }

    if(isDefined(level.sq_volume) &&
       !(self MM_EETrackerStat("sq_transit_maxis_complete") > 0 &&
         self MM_EETrackerStat("sq_transit_rich_complete") > 0))
        targets = self MM_EEAddQuestTarget(targets, level.sq_volume, "TOWER OBJECTIVE");

    if(isDefined(level.sq_progress) && isDefined(level.sq_progress["maxis"]))
    {
        maxis = level.sq_progress["maxis"];

        if(!isDefined(maxis["A_complete"]) || !maxis["A_complete"])
        {
            targets = self MM_EEAddQuestEnt(targets, "sq_common_area", "MAXIS - TWO TOWER TURBINES");
            if(isDefined(maxis["A_turbine_1"]) && !isint(maxis["A_turbine_1"]))
                targets = self MM_EEAddQuestTarget(targets, maxis["A_turbine_1"], "MAXIS TURBINE 1");
            if(isDefined(maxis["A_turbine_2"]) && !isint(maxis["A_turbine_2"]))
                targets = self MM_EEAddQuestTarget(targets, maxis["A_turbine_2"], "MAXIS TURBINE 2");
        }
        else if(!isDefined(maxis["B_complete"]) || !maxis["B_complete"])
            targets = self MM_EEAddQuestEnt(targets, "sq_common_area", "MAXIS - STUN AVOGADRO");
        else if(!isDefined(maxis["C_complete"]) || !maxis["C_complete"])
        {
            screecherZones = getstructarray("screecher_escape", "targetname");
            foreach(zone in screecherZones)
            {
                if(!isDefined(zone) || !isDefined(zone.origin))
                    continue;
                if(isDefined(maxis["C_screecher_1"]) && maxis["C_screecher_1"] == zone)
                    continue;
                if(isDefined(maxis["C_screecher_2"]) && maxis["C_screecher_2"] == zone)
                    continue;
                targets = self MM_EEAddQuestTarget(targets, zone, "MAXIS - TURBINE LIGHT");
            }
        }
    }

    if(isDefined(level.sq_progress) && isDefined(level.sq_progress["rich"]))
    {
        rich = level.sq_progress["rich"];

        if(!isDefined(rich["A_complete"]) || !rich["A_complete"])
            targets = self MM_EEAddQuestEnt(targets, "sq_common_area", "RICHTOFEN - JET GUN TOWER");
        else if(!isDefined(rich["B_complete"]) || !rich["B_complete"])
            targets = self MM_EEAddQuestEnt(targets, "sq_common_area", "RICHTOFEN - 25 ZOMBIES");
        else if(!isDefined(rich["C_complete"]) || !rich["C_complete"])
        {
            lights = getstructarray("screecher_escape", "targetname");
            foreach(light in lights)
            {
                alreadyOff = false;
                if(isDefined(level.sq_richtofen_c_screecher_lights))
                {
                    foreach(doneLight in level.sq_richtofen_c_screecher_lights)
                    {
                        if(isDefined(doneLight) && doneLight == light)
                            alreadyOff = true;
                    }
                }
                if(!alreadyOff)
                    targets = self MM_EEAddQuestTarget(targets, light, "RICHTOFEN - EMP LIGHT");
            }
        }
    }

    return targets;
}
MM_EECollectDieRiseTargets(targets)
{
    navBuilt = flag("sq_nav_built");
    navApplied = self MM_EETrackerStat("navcard_applied_zm_highrise") > 0;
    stageName = "";
    if(isDefined(level._cur_stage_name))
        stageName = level._cur_stage_name;
    else if(isDefined(level._last_stage_started))
        stageName = level._last_stage_started;

    if(!navBuilt || !navApplied)
    {
        targets = self MM_EEAddQuestEnt(targets, "sq_common_buildable_trigger", "BUILD NAVCARD TABLE");
        targets = self MM_EEAddQuestStruct(targets, "sq_common_key", "NAVCARD TABLE");
        return targets;
    }

    if(!flag("sq_atd_drg_puzzle_complete"))
    {
        elevatorTriggers = array("elevator_bldg1b_trigger", "elevator_bldg1d_trigger", "elevator_bldg3b_trigger", "elevator_bldg3c_trigger");
        elevatorFlags = array("sq_atd_elevator0", "sq_atd_elevator1", "sq_atd_elevator2", "sq_atd_elevator3");
        for(elevatorIndex = 0; elevatorIndex < elevatorTriggers.size; elevatorIndex++)
        {
            if(!flag(elevatorFlags[elevatorIndex]))
                targets = self MM_EEAddQuestEnt(targets, elevatorTriggers[elevatorIndex], "STAND ON ELEVATOR");
        }
        targets = self MM_EEAddQuestEntArray(targets, "trig_atd_drg_puzzle", "targetname", "DRAGON ORDER SWITCH");
        targets = self MM_EEAddQuestEntArray(targets, "elevator_dragon_icon", "targetname", "DRAGON SYMBOL");
        targets = self MM_EEAddQuestEntArray(targets, "atd2_marker_unlit", "script_noteworthy", "DRAGON SYMBOL");
    }
    else if(!flag("sq_ball_picked_up"))
        targets = self MM_EEAddQuestEntArray(targets, "sq_dragon_lion_ball", "targetname", "COLLECT THE LION BALL");
    else if(stageName == "ssp_1" && (!flag("ssp1_ball0_complete") || !flag("ssp1_ball1_complete")))
        targets = self MM_EEAddQuestEntArray(targets, "sq_sliquify_ball", "targetname", "RICHTOFEN - LIQUIFY BALL");
    else if(stageName == "ssp_2" && !flag("ssp2_resurrection_done"))
        targets = self MM_EEAddQuestEnt(targets, "corpse_room_trigger", "MAXIS - CORPSE ROOM");
    else if(stageName == "pts_1" && !flag("pts_1_springpads_placed"))
    {
        targets = self MM_EEAddQuestStructArray(targets, "pts_lion", "targetname", "RICHTOFEN - TRAMPLE STEAM SPOT");
        targets = self MM_EEAddQuestEnt(targets, "pts_tower_trig", "LAUNCH ZOMBIES");
        targets = self MM_EEAddQuestStruct(targets, "sq_zombie_launch_target", "TOWER LAUNCH TARGET");
    }
    else if(stageName == "pts_2" && !flag("pts_2_springpads_placed"))
    {
        targets = self MM_EEAddQuestStructArray(targets, "pts_ghoul", "targetname", "MAXIS - TRAMPLE STEAM SPOT");
        targets = self MM_EEAddQuestEnt(targets, "pts_tower_trig", "LAUNCH ZOMBIES");
        targets = self MM_EEAddQuestStruct(targets, "sq_zombie_launch_target", "TOWER LAUNCH TARGET");
    }

    if(flag("sq_branch_complete") && !flag("sq_tower_active") &&
       isDefined(level.a_wind_order) && isDefined(level.n_cur_leg) &&
       level.n_cur_leg < level.a_wind_order.size)
    {
        nextDirection = level.a_wind_order[level.n_cur_leg];
        targets = self MM_EEAddQuestEntKey(targets, "sq_tower_" + nextDirection, "script_noteworthy", "NEXT TOWER LEG - " + nextDirection);
    }

    return targets;
}
MM_EECollectBuriedTargets(targets)
{
    stageName = "";
    if(isDefined(level._cur_stage_name))
        stageName = level._cur_stage_name;
    else if(isDefined(level._last_stage_started))
        stageName = level._last_stage_started;

    navBuilt = flag("sq_nav_built");
    navApplied = self MM_EETrackerStat("navcard_applied_zm_buried") > 0;
    if(!navBuilt || !navApplied)
    {
        targets = self MM_EEAddQuestEnt(targets, "sq_common_buildable_trigger", "BUILD NAVCARD TABLE");
        targets = self MM_EEAddQuestStruct(targets, "sq_common_key", "NAVCARD TABLE");
        return targets;
    }

    if(stageName == "bt")
    {
        targets = self MM_EEAddQuestStruct(targets, "sq_guillotine", "RICHTOFEN TOWER SITE");
        targets = self MM_EEAddQuestStruct(targets, "sq_gallows", "MAXIS TOWER SITE");
    }
    else if(stageName == "mta")
    {
        targets = self MM_EEAddQuestEntArray(targets, "sq_amplifier", "targetname", "AMPLIFIER");
        targets = self MM_EEAddQuestStructArrayNoKey(targets, "sq_amplifier_spot", "AMPLIFIER PLACEMENT");
    }
    else if(stageName == "gl")
    {
        targets = self MM_EEAddQuestStructKey(targets, "sq_ghost_lamp_start", "script_noteworthy", "LANTERN START");
        if(isDefined(level.vh_lantern))
        {
            targets = self MM_EEAddQuestTarget(targets, level.vh_lantern, "FOLLOW THE LANTERN");
            if(isDefined(level.vh_lantern.m_lantern))
                targets = self MM_EEAddQuestTarget(targets, level.vh_lantern.m_lantern, "COLLECT THE LANTERN");
        }
    }
    else if(stageName == "ftl")
    {
        if(isDefined(level.vh_lantern))
        {
            targets = self MM_EEAddQuestTarget(targets, level.vh_lantern, "CHARGE THE LANTERN");
            if(isDefined(level.vh_lantern.m_lantern))
                targets = self MM_EEAddQuestTarget(targets, level.vh_lantern.m_lantern, "CHARGE THE LANTERN");
        }
        targets = self MM_EEAddQuestEnt(targets, "sq_lantern_symbol", "OIL LAMP GENERATOR");
        if(flag("ftl_lantern_charged") && isDefined(level.sq_lamp_generator_unitrig) && isDefined(level.sq_lamp_generator_unitrig.origin))
            targets = self MM_EEAddQuestTarget(targets, level.sq_lamp_generator_unitrig, "BUILD OIL LAMP");
    }
    else if(stageName == "ll")
    {
        targets = self MM_EEAddQuestEntArray(targets, "sq_tunnel_sign", "targetname", "READ TUNNEL SIGN");
        targets = self MM_EEAddQuestStructArray(targets, "sq_code_pos", "targetname", "TUNNEL CODE POSITION");
    }
    else if(stageName == "ts")
        targets = self MM_EEAddQuestEntArray(targets, "sq_tunnel_sign", "targetname", "ACTIVATE SIGN IN ORDER");
    else if(stageName == "ctw")
    {
        if(isDefined(level.vh_wisp))
            targets = self MM_EEAddQuestTarget(targets, level.vh_wisp, "FOLLOW THE WISP");
        targets = self MM_EEAddQuestEnt(targets, "sq_wisp", "WISP");
        targets = self MM_EEAddQuestEnt(targets, "sq_guillotine", "WISP DESTINATION");
        targets = self MM_EEAddQuestStruct(targets, "sq_guillotine", "WISP DESTINATION");
    }
    else if(stageName == "tpo")
    {
        if(!flag("sq_tpo_found_item"))
        {
            targets = self MM_EEAddQuestEnt(targets, "sq_tpo_timebomb_volume", "PLACE TIME BOMB HERE");
            targets = self MM_EEAddQuestEntArray(targets, "sq_tpo_corpse_model", "targetname", "SEARCH THIS CORPSE");
        }
        else if(!flag("sq_tpo_generator_powered"))
        {
            targets = self MM_EEAddQuestEnt(targets, "sq_guillotine", "INSTALL THE SWITCH");
            if(isDefined(level.sq_tpo_unitrig) && isDefined(level.sq_tpo_unitrig.realorigin))
            {
                switchMarker = spawnstruct();
                switchMarker.origin = level.sq_tpo_unitrig.realorigin;
                targets = self MM_EEAddQuestTarget(targets, switchMarker, "GUillotine SWITCH");
            }
        }
        targets = self MM_EEAddQuestStruct(targets, "sq_gallows", "MAXIS TIME BOMB AREA");
    }
    else if(stageName == "ip")
    {
        targets = self MM_EEAddQuestEnt(targets, "sq_bp_board", "PUZZLE BOARD");
        targets = self MM_EEAddQuestStructArray(targets, "sq_bp_button", "targetname", "BOARD BUTTON");
        targets = self MM_EEAddQuestEntArray(targets, "sq_ml_lever", "targetname", "MAZE LEVER");
        targets = self MM_EEAddQuestStructArray(targets, "sq_maze_lever", "targetname", "MAZE LEVER POSITION");
    }
    else if(stageName == "ows")
    {
        targets = self MM_EEAddQuestStruct(targets, "sq_ows_fountain", "START AT FOUNTAIN");
        targets = self MM_EEAddQuestStructArray(targets, "otw_target_spot", "script_noteworthy", "SHOOT MOVING TARGET");
    }
    else
    {
        targets = self MM_EEAddQuestStruct(targets, "sq_guillotine", "QUEST START");
        targets = self MM_EEAddQuestStruct(targets, "sq_gallows", "QUEST START");
    }

    return targets;
}
MM_EECreateQuestESPMarker()
{
    hud = newClientHudElem(self);
    hud.archived = 1;
    hud.foreground = false;
    hud.hideWhenInMenu = true;
    hud.sort = 2;
    hud.alpha = 0;
    hud.color = (0.2, 1.0, 1.0);
    hud setShader("white", 6, 6);
    hud setWaypoint(true, "white");
    return hud;
}

MM_EECreateQuestESPLabel()
{
    hud = newClientHudElem(self);
    hud.archived = 1;
    hud.foreground = false;
    hud.hideWhenInMenu = true;
    hud.sort = 3;
    hud.alpha = 0;
    hud.color = (1.0, 0.9, 0.35);
    hud.font = "objective";
    hud.fontScale = 0.62;
    hud setWaypoint(true, "white");
    return hud;
}

MM_ToggleEETrackerESP()
{
    self MM_Toggle("eetargets", "Quest Object ESP", ::MM_EETrackerESPLoop);
}

MM_EETrackerESPLoop()
{
    self endon("disconnect");

    if(isDefined(self.mmEEESPActive) && self.mmEEESPActive)
        return;

    self.mmEEESPActive = true;
    maxMarkers = 24;
    dots = [];
    labels = [];
    lastLabelText = [];

    for(i = 0; i < maxMarkers; i++)
    {
        dots[i] = self MM_EECreateQuestESPMarker();
        labels[i] = self MM_EECreateQuestESPLabel();
    }

    // Pinned step-by-step guide, following the Origins staff-guide layout.
    guideRowCount = 6;
    guideHuds = [];
    guideLastRows = [];
    for(rowIndex = 0; rowIndex < guideRowCount; rowIndex++)
    {
        guideHuds[rowIndex] = self MM_NewText(-22, 112 + (rowIndex * 17), 0.92);
        guideHuds[rowIndex].horzAlign = "right";
        guideHuds[rowIndex].alignX = "right";
        guideHuds[rowIndex].x = -22;
        guideHuds[rowIndex].sort = 1100;
        guideHuds[rowIndex].color = (0.9, 0.95, 1);
    }

    self.mmEEESPDots = dots;
    self.mmEEESPLabels = labels;

    for(;;)
    {
        if(!self MM_IsOn("eetargets"))
            break;

        targets = self MM_EECollectQuestTargets();
        used = [];

        for(slot = 0; slot < maxMarkers; slot++)
        {
            bestIdx = -1;
            bestDistance = 999999999;

            foreach(idx, item in targets)
            {
                if(isDefined(used[idx]) || !isDefined(item) || !isDefined(item.ent) || !isDefined(item.ent.origin))
                    continue;

                distanceNow = distancesquared(self.origin, item.ent.origin);
                if(distanceNow < bestDistance)
                {
                    bestDistance = distanceNow;
                    bestIdx = idx;
                }
            }

            if(bestIdx < 0)
            {
                dots[slot].alpha = 0;
                labels[slot].alpha = 0;
                continue;
            }

            used[bestIdx] = true;
            target = targets[bestIdx].ent;
            markerPos = target.origin + (0, 0, 28);
            dots[slot].x = markerPos[0];
            dots[slot].y = markerPos[1];
            dots[slot].z = markerPos[2];
            dots[slot].alpha = 1;

            labels[slot].x = markerPos[0];
            labels[slot].y = markerPos[1];
            labels[slot].z = markerPos[2] + 10;

            // Never append changing distances: new HUD strings can exhaust configstrings.
            labelText = "^3" + targets[bestIdx].label;
            if(!isDefined(lastLabelText[slot]) || lastLabelText[slot] != labelText)
            {
                labels[slot] setText(labelText);
                lastLabelText[slot] = labelText;
            }
            labels[slot].alpha = 1;
        }

        guideLines = strtok(self MM_EETrackerGuideBuildText(), "\n");
        for(rowIndex = 0; rowIndex < guideRowCount; rowIndex++)
        {
            if(rowIndex < guideLines.size)
            {
                if(!isDefined(guideLastRows[rowIndex]) || guideLastRows[rowIndex] != guideLines[rowIndex])
                {
                    guideHuds[rowIndex] setText(guideLines[rowIndex]);
                    guideLastRows[rowIndex] = guideLines[rowIndex];
                }
                guideHuds[rowIndex].alpha = 1;
            }
            else
                guideHuds[rowIndex].alpha = 0;
        }

        wait 0.15;
    }

    foreach(dot in dots)
    {
        if(isDefined(dot))
            dot destroy();
    }
    foreach(label in labels)
    {
        if(isDefined(label))
            label destroy();
    }
    foreach(guideHud in guideHuds)
    {
        if(isDefined(guideHud))
            guideHud destroy();
    }

    self.mmEEESPDots = [];
    self.mmEEESPLabels = [];
    self.mmEEESPActive = false;
}
MM_ToggleStatusHUD()
{
    self MM_Toggle("statushud", "Live Match HUD", ::MM_StatusHUDLoop);
}

MM_StatusHUDLoop()
{
    self endon("disconnect");

    hud = self MM_NewText(12, 350, 0.85);
    hud.color = (0.75, 1, 0.75);
    hud.sort = 1002;

    for(;;)
    {
        if(!self MM_IsOn("statushud"))
            break;

        enemyCount = MM_AllEnemies().size;
        roundText = level.round_number + 1;
        weapon = self getCurrentWeapon();
        if(!isDefined(weapon) || weapon == "none")
            weapon = "Unarmed";

        perkCount = 0;
        availablePerks = self MM_GetAvailablePerks();
        foreach(perk in availablePerks)
        {
            if(self hasPerk(perk))
                perkCount++;
        }

        hud setText("^2BO2 LIVE ^7| ROUND: ^3" + roundText
            + " ^7| POINTS: ^3" + self.score
            + " ^7| HP: ^3" + self.health + "/" + self.maxhealth
            + " ^7| ENEMIES: ^3" + enemyCount
            + "\\n^7WEAPON: ^3" + weapon + " ^7| PERKS: ^3" + perkCount);
        wait 0.35;
    }

    if(isDefined(hud))
        hud destroy();
}

MM_ClearRegularZombies()
{
    zombies = MM_AliveZombies();
    killed = 0;
    foreach(z in zombies)
    {
        if(!isDefined(z) || !isAlive(z))
            continue;
        z doDamage(z.health + 9999, z.origin, self);
        killed++;
    }
    self iprintln("^2Cleared " + killed + " regular zombies; boss entities were preserved.");
}

// ============================================================================
//  LOBBY / MAP
// ============================================================================

TurnOnPower()
{
    if(flag("power_on"))
    {
        self iprintln("Power is already on");
        return;
    }

    // Same sequence the Die Rise / Buried power switches run.
    level notify("electric_door");
    level thread maps\mp\zombies\_zm_perks::perk_unpause_all_perks();
    flag_set("power_on");
    level setClientField("zombie_power_on", 1);
    self iprintln("Power turned ^2ON");
}

OpenAllDoors()
{
    if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
    {
        self iprintln("^1You can't open doors while downed.");
        return;
    }

    setDvar("zombie_unlock_all", 1);

    doors = getEntArray("zombie_door", "targetname");
    foreach(door in doors)
    {
        if(isDefined(door.has_been_opened) && door.has_been_opened)
            continue;
        door notify("trigger", self, true);
        wait 0.05;
    }

    airlocks = getEntArray("zombie_airlock_buy", "targetname");
    foreach(a in airlocks)
    {
        a notify("trigger", self, true);
        wait 0.05;
    }

    debris = getEntArray("zombie_debris", "targetname");
    foreach(d in debris)
    {
        d notify("trigger", self, true);
        wait 0.05;
    }

    wait 1;
    setDvar("zombie_unlock_all", 0);
    self iprintln("All doors ^2opened");
}

SpawnDrop(type)
{
    level maps\mp\zombies\_zm_powerups::specific_powerup_drop(type, MM_Forward(60) + (0, 0, 30));
    self iprintln("Drop spawned");
}

MM_KillEnemies()
{
    enemies = MM_AllEnemies();
    foreach(z in enemies)
    {
        if(isDefined(z) && isAlive(z))
            z doDamage(z.health + 666, z.origin);
    }
}

SkipRound()
{
    level.zombie_total = 0;
    MM_KillEnemies();
    self iprintln("Skipping round...");
}

SetRound(round)
{
    // round_number is incremented when the current round ends.
    level.round_number = round - 1;
    level.zombie_total = 0;
    MM_KillEnemies();
    self iprintln("Jumping to round " + round + "...");
}

SetTimeScale(val)
{
    setDvar("timescale", val);
    self iprintln("Game speed: " + val);
}

MM_SetLowGravity()
{
    setDvar("g_gravity", 100);
    self iprintln("Gravity: 100");
}

MM_SetNormalGravity()
{
    setDvar("g_gravity", 800);
    self iprintln("Gravity: 800");
}

RestartMap()
{
    map_restart(false);
}

EndGame()
{
    level notify("end_game");
}

// ============================================================================
//  ZOMBIES
// ============================================================================

KillAllZombies()
{
    zombies = MM_AliveZombies();
    foreach(z in zombies)
    {
        if(isDefined(z) && isAlive(z))
            z doDamage(z.health + 666, z.origin);
    }
    self iprintln("All zombies killed");
}

ExplodeZombies()
{
    zombies = MM_AliveZombies();
    foreach(z in zombies)
    {
        if(!isDefined(z) || !isAlive(z))
            continue;
        // Skip the splash for zombies next to you so you don't hurt yourself.
        if(distance(self.origin, z.origin) > 250)
            radiusDamage(z.origin, 150, 1000, 1000, self);
        z doDamage(z.health + 666, z.origin);
    }
    self iprintln("Zombies exploded");
}

BurnZombies()
{
    zombies = MM_AliveZombies();
    foreach(z in zombies)
    {
        if(isDefined(z) && isAlive(z))
            z doDamage(z.health + 666, z.origin, self, self, "none", "MOD_BURNED");
    }
    self iprintln("Zombies burned");
}

TeleportZombies()
{
    pos = MM_Forward(150);
    zombies = MM_AliveZombies();
    foreach(z in zombies)
    {
        if(isDefined(z))
            z forceTeleport(pos);
    }
    self iprintln("Zombies teleported to you");
}

TeleportZombiesCrosshair()
{
    pos = self MM_CrosshairPos();
    zombies = MM_AliveZombies();
    foreach(z in zombies)
    {
        if(isDefined(z))
            z forceTeleport(pos);
    }
    self iprintln("Zombies teleported to crosshair");
}

ToggleZombieMagnet() { self MM_Toggle("magnet", "Zombie Magnet", ::MagnetLoop); }
MagnetLoop()
{
    self endon("disconnect");
    self endon("mm_stop_magnet");
    for(;;)
    {
        pos = MM_Forward(150);
        zombies = MM_AliveZombies();
        foreach(z in zombies)
        {
            if(isDefined(z))
                z forceTeleport(pos);
        }
        wait 0.1;
    }
}

MM_FlingZombie(force)
{
    self endon("death");
    self startRagdoll();
    self launchRagdoll((randomIntRange(-150, 150), randomIntRange(-150, 150), force));
    wait 1.5;
    if(isDefined(self) && isAlive(self))
        self doDamage(self.health + 666, self.origin);
}

FlingZombies()
{
    zombies = MM_AliveZombies();
    foreach(z in zombies)
        z thread MM_FlingZombie(900);
    self iprintln("Zombies launched");
}

ZombiesToMoon()
{
    zombies = MM_AliveZombies();
    foreach(z in zombies)
        z thread MM_FlingZombie(3500);
    self iprintln("Zombies sent to the moon");
}

ToggleFreezeZombies()
{
    level.mmFrozen = !level.mmFrozen;
    if(level.mmFrozen)
    {
        level thread MM_FreezeLoop();
        self iprintln("Zombies Frozen ^2ON");
    }
    else
    {
        level notify("mm_unfreeze");
        zombies = MM_AliveZombies();
        foreach(z in zombies)
        {
            z.ignoreall = false;
            z.animPlaybackRate = 1;
            z.moveplaybackrate = 1;
        }
        self iprintln("Zombies Frozen ^1OFF");
    }
}

MM_FreezeLoop()
{
    level endon("mm_unfreeze");
    level endon("end_game");
    for(;;)
    {
        zombies = MM_AliveZombies();
        foreach(z in zombies)
        {
            z.ignoreall = true;
            z.animPlaybackRate = 0;
            z.moveplaybackrate = 0;
        }
        wait 0.2;
    }
}

SetZombieSpeed(mode)
{
    level notify("mm_speed_stop");

    if(mode == "default")
    {
        level.mmSpeed = undefined;
        self iprintln("Zombie speed: default (applies to new zombies)");
        return;
    }

    level.mmSpeed = mode;
    level thread MM_ZombieSpeedLoop();
    self iprintln("Zombie speed: " + mode);
}

MM_ZombieSpeedLoop()
{
    level endon("mm_speed_stop");
    level endon("end_game");
    for(;;)
    {
        zombies = MM_AliveZombies();
        foreach(z in zombies)
        {
            if(!isDefined(z.animname) || z.animname != "zombie")
                continue;
            if(!isDefined(z.zombie_move_speed) || z.zombie_move_speed != level.mmSpeed)
                z set_zombie_run_cycle(level.mmSpeed);
        }
        wait 0.5;
    }
}

ToggleKillAura()     { self MM_Toggle("killaura", "Insta-Kill Aura", ::KillAuraLoop); }
KillAuraLoop()
{
    self endon("disconnect");
    self endon("mm_stop_killaura");
    for(;;)
    {
        zombies = MM_AliveZombies();
        foreach(z in zombies)
        {
            if(isDefined(z) && isAlive(z) && distance(self.origin, z.origin) < 150)
                z doDamage(z.health + 666, z.origin, self);
        }
        wait 0.2;
    }
}

DeleteZombies()
{
    zombies = MM_AliveZombies();
    foreach(z in zombies)
    {
        if(isDefined(z))
            z delete();
    }
    self iprintln("Zombies deleted");
}

RespawnZombies()
{
    level.zombie_total += 24;
    self iprintln("Added 24 zombies to the round");
}

// ============================================================================
//  AIMBOT / ESP
// ============================================================================

ToggleAimbot()       { self MM_Toggle("aimbot", "Aimbot", ::AimbotLoop); }

SetAimTarget(bone)
{
    self.aimbotBone = bone;
    self iprintln("Aimbot target: " + bone);
}

AimbotLoop()
{
    self endon("disconnect");
    self endon("mm_stop_aimbot");

    if(!isDefined(self.aimbotBone))
        self.aimbotBone = "j_head";

    for(;;)
    {
        wait 0.05;
        if(self.menuOpen)
            continue;
        if(!self adsButtonPressed() && !self attackButtonPressed())
            continue;

        eye = self getEye();
        fwd = anglesToForward(self getPlayerAngles());
        best = undefined;
        bestDot = 0.5;   // only targets within ~60 degrees of the crosshair

        zombies = MM_AllEnemies();
        foreach(z in zombies)
        {
            tag = z getTagOrigin(self.aimbotBone);
            if(!isDefined(tag))
                continue;

            dot = vectorDot(fwd, vectorNormalize(tag - eye));
            if(dot < bestDot)
                continue;
            if(!bulletTracePassed(eye, tag, false, self))
                continue;

            bestDot = dot;   // closer to the crosshair wins
            best = tag;
        }

        if(isDefined(best))
            self setPlayerAngles(vectorToAngles(best - eye));
    }
}

// ----------------------------------------------------------------------------
//  SILENT AIM
//  Your view never moves. Every shot you fire also sends a bullet from the gun
//  straight to the head of the enemy nearest your crosshair (needs a clear line
//  of sight), so shots bend around your aim like a trickshot.
// ----------------------------------------------------------------------------

ToggleSilentAim()    { self MM_Toggle("silentaim", "Silent Aim", ::SilentAimLoop); }

SetSilentFov(dotLimit)
{
    self.silentFov = dotLimit;
    if(dotLimit <= -1)
        self iprintln("Silent Aim FOV: full 360");
    else if(dotLimit >= 0.95)
        self iprintln("Silent Aim FOV: narrow");
    else
        self iprintln("Silent Aim FOV: wide");
}

// Only real bullet weapons: no grenades, launchers, melee or equipment.
MM_SilentWeaponOK(weap)
{
    if(!isDefined(weap) || weap == "none" || weap == "")
        return false;

    wclass = weaponClass(weap);
    switch(wclass)
    {
        case "rifle":
        case "smg":
        case "mg":
        case "pistol":
        case "spread":
        case "pistol spread":
            return true;
    }
    return false;
}

// Position of the best target: nearest to the crosshair, inside the FOV
// cone, with a clear line of sight. Returns undefined if there is none.
MM_SilentTarget(eye)
{
    fwd = anglesToForward(self getPlayerAngles());
    best = undefined;
    bestDot = self.silentFov;

    enemies = MM_AllEnemies();
    foreach(z in enemies)
    {
        tag = z getTagOrigin(self.aimbotBone);
        if(!isDefined(tag))
            continue;

        dot = vectorDot(fwd, vectorNormalize(tag - eye));
        if(dot < bestDot)
            continue;
        if(!bulletTracePassed(eye, tag, false, self))
            continue;

        bestDot = dot;
        best = tag;
    }
    return best;
}

SilentAimLoop()
{
    self endon("disconnect");
    self endon("mm_stop_silentaim");

    if(!isDefined(self.aimbotBone))
        self.aimbotBone = "j_head";
    if(!isDefined(self.silentFov))
        self.silentFov = 0.85;

    for(;;)
    {
        self waittill("weapon_fired");

        if(self.menuOpen)
            continue;

        weap = self getCurrentWeapon();
        if(!MM_SilentWeaponOK(weap))
            continue;

        eye = self getEye();
        target = self MM_SilentTarget(eye);
        if(!isDefined(target))
            continue;

        // Start at the muzzle side of the eye and run on past the head.
        start = eye + (anglesToForward(self getPlayerAngles()) * 20);
        endPos = target + (vectorNormalize(target - start) * 100);
        magicBullet(weap, start, endPos, self);
    }
}

ToggleESP()          { self MM_Toggle("esp", "ESP", ::ESPLoop); }

SetESPColor(color)
{
    self.espColor = color;
    self iprintln("ESP color changed");
}

SetESPSize(size)
{
    self.espSize = size;
    self iprintln("ESP dot size: " + size);
}

// Destroys the ESP dots if the player disconnects while ESP is running.
MM_ESPDisconnectCleanup()
{
    self endon("mm_esp_off");
    self waittill("disconnect");

    if(isDefined(self.mmESPHuds))
    {
        foreach(hud in self.mmESPHuds)
        {
            if(isDefined(hud))
                hud destroy();
        }
    }
}

// Applies shape / size to one dot. Used on creation and when the size changes.
MM_StyleESPDot(hud, size)
{
    hud setShader("white", size, size);
    hud setWaypoint(true, "white");
    hud scaleOverTime(0.05, size, size);
}

MM_CreateESPDot()
{
    hud = newClientHudElem(self);
    hud.archived = 1;
    hud.foreground = false;
    hud.hideWhenInMenu = true;
    hud.sort = 1;
    hud.alpha = 0;
    hud.color = self.espColor;
    self MM_StyleESPDot(hud, self.espSize);
    return hud;
}

ESPLoop()
{
    self endon("disconnect");

    // Prevent duplicate dot pools if ESP is toggled rapidly.
    if(isDefined(self.mmESPThreadActive) && self.mmESPThreadActive)
        return;

    self.mmESPThreadActive = true;
    if(!isDefined(self.espColor))
        self.espColor = (1, 0, 0);
    if(!isDefined(self.espSize))
        self.espSize = 2;

    // One tiny dot per target. Ten dots = ten HUD elements, which is less than
    // the old four-bar frame used for just four targets.
    maxDots = 10;
    huds = [];
    for(i = 0; i < maxDots; i++)
        huds[i] = self MM_CreateESPDot();

    self.mmESPHuds = huds;
    appliedSize = self.espSize;
    self thread MM_ESPDisconnectCleanup();

    for(;;)
    {
        if(!self MM_IsOn("esp"))
            break;

        // Size changed from the menu: restyle the existing dots.
        if(appliedSize != self.espSize)
        {
            appliedSize = self.espSize;
            for(i = 0; i < maxDots; i++)
                self MM_StyleESPDot(huds[i], appliedSize);
        }

        zombies = MM_AllEnemies();
        count = zombies.size;
        used = [];

        // Mark the nearest targets, one dot each, just above the head.
        for(slot = 0; slot < maxDots; slot++)
        {
            bestIdx = -1;
            bestDistance = 999999999;

            for(i = 0; i < count; i++)
            {
                if(isDefined(used[i]))
                    continue;

                distanceNow = distancesquared(self.origin, zombies[i].origin);
                if(distanceNow < bestDistance)
                {
                    bestDistance = distanceNow;
                    bestIdx = i;
                }
            }

            if(bestIdx < 0)
            {
                huds[slot].alpha = 0;
                continue;
            }

            used[bestIdx] = true;
            z = zombies[bestIdx];

            head = z getTagOrigin("j_head");
            if(!isDefined(head))
                head = z.origin + (0, 0, 60);
            pos = head + (0, 0, 8);

            huds[slot].x = pos[0];
            huds[slot].y = pos[1];
            huds[slot].z = pos[2];
            huds[slot].color = self.espColor;
            huds[slot].alpha = 1;
        }

        wait 0.1;
    }

    self notify("mm_esp_off");

    foreach(hud in huds)
    {
        if(isDefined(hud))
            hud destroy();
    }

    self.mmESPHuds = [];
    self.mmESPThreadActive = false;
}


// ============================================================================
//  ULTIMATE ZM MOD MENU - ORIGINS MODULE
//  Origins-only controls, kept separate so this map can be edited safely.
//  Uses the real Origins staff, craftable and Easter-egg flags from the
//  Plutonium T6 stock scripts. Included by zm_modmenu.gsc.
// ============================================================================

MM_OriginsGiveShovel()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1The shovel is only available on Origins.");
        return;
    }

    if(!isDefined(self.dig_vars))
    {
        self iprintln("^1Origins digging system is not initialized yet. Try again after spawning.");
        return;
    }

    // Match the stock Origins shovel inventory and per-player HUD clientfield.
    self.dig_vars["has_shovel"] = 1;
    player_number = self getentitynumber() + 1;
    level setclientfield("shovel_player" + player_number, 1);
    self iprintlnbold("^2Origins shovel given.");
}

MM_OriginsGiveGoldenShovel()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1The Golden Shovel is only available on Origins.");
        return;
    }

    if(!isDefined(self.dig_vars))
    {
        self iprintln("^1Origins digging system is not initialized yet. Try again after spawning.");
        return;
    }

    self.dig_vars["has_shovel"] = 1;
    self.dig_vars["has_upgraded_shovel"] = 1;
    player_number = self getentitynumber() + 1;
    level setclientfield("shovel_player" + player_number, 2);

    // The upgraded shovel also unlocks the stock personal Zombie Blood dig
    // spots. Start that stock thread only once for this player.
    if(!isDefined(self.mmGoldenDigSpotStarted))
    {
        bloodDigFunc = getfunction("maps/mp/zm_tomb_dig", "ee_zombie_blood_dig");
        if(isDefined(bloodDigFunc))
        {
            self.mmGoldenDigSpotStarted = true;
            self thread [[ bloodDigFunc ]]();
        }
    }

    self playsoundtoplayer("zmb_squest_golden_anything", self);
    self iprintlnbold("^2Golden Shovel given.");
}

MM_OriginsGiveGoldenHelmet()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1The Golden Helmet is only available on Origins.");
        return;
    }

    if(!isDefined(self.dig_vars))
    {
        self iprintln("^1Origins digging system is not initialized yet. Try again after spawning.");
        return;
    }

    // Set only this player's stock helmet state and HUD clientfield.
    self.dig_vars["has_helmet"] = 1;
    player_number = self getentitynumber() + 1;
    level setclientfield("helmet_player" + player_number, 1);
    self iprintlnbold("^2Golden Helmet given.");
}

// The Origins digging system exposes the live mound models through
// level.a_dig_spots[].m_dig. This ESP tracks active mounds only; buried spots
// that have not spawned a visible mound are intentionally not marked.
MM_OriginsToggleDigESP()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1Dig Site ESP is only available on Origins.");
        return;
    }

    self scripts\zm\zm_modmenu::MM_Toggle("origdigesp", "Origins Dig Site ESP", ::MM_OriginsDigESPLoop);
}

MM_OriginsDigESPLoop()
{
    self endon("disconnect");

    if(isDefined(self.mmOriginsDigESPActive) && self.mmOriginsDigESPActive)
        return;

    self.mmOriginsDigESPActive = true;
    maxDots = 24;
    huds = [];
    for(i = 0; i < maxDots; i++)
        huds[i] = self MM_CreatePartESPDot();

    while(self scripts\zm\zm_modmenu::MM_IsOn("origdigesp"))
    {
        if(level.script != "zm_tomb" || !isDefined(level.a_dig_spots))
        {
            for(i = 0; i < maxDots; i++)
                huds[i].alpha = 0;
            wait 0.25;
            continue;
        }

        spots = [];
        foreach(spot in level.a_dig_spots)
        {
            if(!isDefined(spot) || (isDefined(spot.dug) && spot.dug))
                continue;
            if(!isDefined(spot.m_dig) || !isDefined(spot.m_dig.origin))
                continue;
            spots[spots.size] = spot.m_dig;
        }

        used = [];
        for(slot = 0; slot < maxDots; slot++)
        {
            bestIdx = -1;
            bestDistance = 999999999;
            foreach(idx, mound in spots)
            {
                if(isDefined(used[idx]) || !isDefined(mound) || !isDefined(mound.origin))
                    continue;
                distanceNow = distancesquared(self.origin, mound.origin);
                if(distanceNow < bestDistance)
                {
                    bestDistance = distanceNow;
                    bestIdx = idx;
                }
            }

            if(bestIdx < 0)
            {
                huds[slot].alpha = 0;
                continue;
            }

            used[bestIdx] = true;
            mound = spots[bestIdx];
            huds[slot].x = mound.origin[0];
            huds[slot].y = mound.origin[1];
            huds[slot].z = mound.origin[2] + 35;
            huds[slot].color = (1, 0.75, 0.1);
            huds[slot].alpha = 1;
        }
        wait 0.15;
    }

    foreach(hud in huds)
    {
        if(isDefined(hud))
            hud destroy();
    }
    self.mmOriginsDigESPActive = false;
}


// Live four-staff checklist. This is a guide/ESP overlay only: it reads the
// native craftable counts, weapon inventory, charger flags and robot plinths.
// It never awards parts or changes Easter Egg state.
MM_OriginsToggleStaffGuide()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1Staff Upgrade Guide is only available on Origins.");
        return;
    }
    self scripts\zm\zm_modmenu::MM_Toggle("origstaffguide", "Staff Upgrade Guide ESP", ::MM_OriginsStaffGuideLoop);
}

MM_OriginsStaffGuideLoop()
{
    self endon("disconnect");
    if(isDefined(self.mmOriginsStaffGuideActive) && self.mmOriginsStaffGuideActive)
        return;

    self.mmOriginsStaffGuideActive = true;

    // Keep the staff overview pinned while cycling the detailed puzzle guide.
    // This prevents the multi-staff ESP from filling the screen with every
    // puzzle instruction at once; all live markers continue updating.
    pageIndex = 0;
    pageTimer = 0;

    // Use the exact same font, size and row spacing as the main menu.
    // Separate HUD rows avoid the oversized multiline/default-font rendering.
    guideHuds = [];
    guideRowCount = 8;
    for(rowIndex = 0; rowIndex < guideRowCount; rowIndex++)
    {
        guideHuds[rowIndex] = self MM_NewText(-22, 112 + (rowIndex * 19), 1.25);
        guideHuds[rowIndex].horzAlign = "right";
        guideHuds[rowIndex].alignX = "right";
        guideHuds[rowIndex].x = -22;
        guideHuds[rowIndex].sort = 1100;
        guideHuds[rowIndex].color = (0.9, 0.95, 1);
    }

    maxMarkers = 64;
    markerHuds = [];
    for(i = 0; i < maxMarkers; i++)
        markerHuds[i] = self MM_CreatePartESPDot();
    self.mmOriginsStaffGuideHuds = markerHuds;

    // Cache rendered rows so unchanged HUD strings are not resubmitted every
    // quarter-second. Dynamic puzzle values update only when their value changes.
    guideLastRows = [];

    while(self scripts\zm\zm_modmenu::MM_IsOn("origstaffguide"))
    {
        if(level.script != "zm_tomb")
        {
            self.mmToggle["origstaffguide"] = false;
            break;
        }

        markers = [];
        guideText = "^3STAFF^7  ^2GREEN=OK^7  ^1ORANGE=ACTION^7\n";
        guideText += self MM_OriginsStaffGuideLine("WIND", "elemental_staff_air", "staff_air_zm", "staff_air_upgraded_zm", "staff_air_zm_upgrade_unlocked", 2) + "\n";
        guideText += self MM_OriginsStaffGuideLine("FIRE", "elemental_staff_fire", "staff_fire_zm", "staff_fire_upgraded_zm", "staff_fire_zm_upgrade_unlocked", 1) + "\n";
        guideText += self MM_OriginsStaffGuideLine("LIGHTNING", "elemental_staff_lightning", "staff_lightning_zm", "staff_lightning_upgraded_zm", "staff_lightning_zm_upgrade_unlocked", 3) + "\n";
        guideText += self MM_OriginsStaffGuideLine("ICE", "elemental_staff_water", "staff_water_zm", "staff_water_upgraded_zm", "staff_water_zm_upgrade_unlocked", 4);

        // Once a staff's puzzle/crypt unlock flag is set, mark the next physical
        // interaction: its charger until 20 souls, then its upgraded pickup.
        chargeStaffs = array(
            "staff_air_zm",
            "staff_fire_zm",
            "staff_lightning_zm",
            "staff_water_zm"
        );
        chargeFlags = array(
            "staff_air_zm_upgrade_unlocked",
            "staff_fire_zm_upgrade_unlocked",
            "staff_lightning_zm_upgrade_unlocked",
            "staff_water_zm_upgrade_unlocked"
        );
        upgradedWeapons = array(
            "staff_air_upgraded_zm",
            "staff_fire_upgraded_zm",
            "staff_lightning_upgraded_zm",
            "staff_water_upgraded_zm"
        );
        for(chargeIndex = 0; chargeIndex < chargeStaffs.size; chargeIndex++)
        {
            chargeWeapon = chargeStaffs[chargeIndex];

            if(!flag(chargeFlags[chargeIndex]))
                continue;

            chargeCount = self MM_OriginsStaffChargeProgress(chargeWeapon);
            if(chargeCount < 20)
            {
                chargerEnt = self MM_OriginsGetStaffCharger(chargeWeapon);
                if(isDefined(chargerEnt) && isDefined(chargerEnt.origin))
                    markers[markers.size] = self MM_OriginsGuideMakeMarker(chargerEnt.origin + (0, 0, 32), (1, 0.5, 0.05));
            }
            else if(!self hasweapon(upgradedWeapons[chargeIndex]))
            {
                upgradeEnt = self MM_OriginsGetStaffUpgradeEntity(chargeWeapon);
                if(isDefined(upgradeEnt) && isDefined(upgradeEnt.origin))
                    markers[markers.size] = self MM_OriginsGuideMakeMarker(upgradeEnt.origin + (0, 0, 32), (0.1, 1, 0.2));
            }
        }

        // FIRE: mark unfinished Crazy Place soul chests, then the four exact
        // church torches selected by the live stock puzzle script.
        if(self hasweapon("staff_fire_zm") && !flag("fire_puzzle_1_complete"))
        {
            fireVolumes = [];
            if(isDefined(level.sacrifice_volumes))
                fireVolumes = level.sacrifice_volumes;
            else
                fireVolumes = getentarray("fire_sacrifice_volume", "targetname");
            fireLeft = 0;
            fireTotal = fireVolumes.size;
            foreach(volume in fireVolumes)
            {
                if(!isDefined(volume) || !isDefined(volume.origin))
                    continue;
                if(isDefined(volume.b_gods_pleased) && volume.b_gods_pleased)
                    continue;

                fireLeft++;
                markers[markers.size] = self MM_OriginsGuideMakeMarker(volume.origin + (0, 0, 28), (1, 0.55, 0.05));
            }
            guideText += "\\n^3FIRE - CRAZY PLACE CHESTS^7: kill zombies inside each orange marker.";
            guideText += "\nUnfinished chests: " + fireLeft + "/" + fireTotal;
        }
        else if(self hasweapon("staff_fire_zm") && !flag("fire_puzzle_2_complete"))
        {
            fireNumbers = getentarray("fire_torch_ternary", "script_noteworthy");
            torchIndex = 0;
            torchValues = "";
            foreach(numberEnt in fireNumbers)
            {
                if(!isDefined(numberEnt) || !isDefined(numberEnt.target))
                    continue;
                torchTarget = getstruct(numberEnt.target, "targetname");
                if(!isDefined(torchTarget) || !isDefined(torchTarget.origin))
                    continue;

                torchIndex++;
                torchColor = (1, 0.12, 0.08);
                torchColorName = "RED";
                if(torchIndex == 2)
                {
                    torchColor = (1, 0.55, 0.05);
                    torchColorName = "ORANGE";
                }
                else if(torchIndex == 3)
                {
                    torchColor = (0.8, 0.2, 1);
                    torchColorName = "PURPLE";
                }
                else if(torchIndex == 4)
                {
                    torchColor = (0.1, 0.8, 1);
                    torchColorName = "CYAN";
                }
                markers[markers.size] = self MM_OriginsGuideMakeMarker(torchTarget.origin + (0, 0, 30), torchColor);
                if(torchValues != "")
                    torchValues += "  ";
                torchValues += "T" + torchIndex + "(" + torchColorName + ")=";
                if(isDefined(numberEnt.script_string))
                    torchValues += numberEnt.script_string;
                else if(isDefined(numberEnt.script_int))
                    torchValues += numberEnt.script_int;
                else
                    torchValues += torchIndex;
            }
            guideText += "\\n^3FIRE - CHURCH TORCHES^7: light all four marked torches; order is not required.";
            guideText += "\nMarker colors: T1 RED, T2 ORANGE, T3 PURPLE, T4 CYAN.";
            guideText += "\nLive torch markers: " + torchIndex + "/4";
            if(torchValues != "")
                guideText += "   Numbers: " + torchValues;
            guideText += "\nTargets are read from this match's randomized puzzle state.";
        }
        else if(self hasweapon("staff_fire_zm"))
            guideText += "\\n^2FIRE: both Crazy Place puzzles are complete.";

        // LIGHTNING: use the three live piano chord definitions. Green
        // waypoints identify the three correct keys for the current chord.
        if(self hasweapon("staff_lightning_zm") && !flag("electric_puzzle_1_complete"))
        {
            chordNames = array("a_minor", "e_minor", "d_minor");
            chordStep = 0;
            if(isDefined(level.mmOriginsPianoChordStep))
                chordStep = level.mmOriginsPianoChordStep;
            if(chordStep < 0)
                chordStep = 0;
            if(chordStep > 2)
                chordStep = 2;

            chordName = chordNames[chordStep];
            chordStruct = getstruct("piano_chord_" + chordName, "script_noteworthy");
            pianoNotes = [];
            if(isDefined(chordStruct) && isDefined(chordStruct.script_string))
                pianoNotes = strtok(chordStruct.script_string, " ");

            if(pianoNotes.size >= 3)
            {
                keys = getstructarray("piano_key", "script_noteworthy");
                foreach(key in keys)
                {
                    if(!isDefined(key) || !isDefined(key.origin) || !isDefined(key.script_string))
                        continue;
                    keyColor = undefined;
                    if(key.script_string == pianoNotes[0])
                        keyColor = (1, 0.12, 0.08);
                    else if(key.script_string == pianoNotes[1])
                        keyColor = (0.1, 0.35, 1);
                    else if(key.script_string == pianoNotes[2])
                        keyColor = (1, 0.9, 0.1);
                    if(isDefined(keyColor))
                        markers[markers.size] = self MM_OriginsGuideMakeMarker(key.origin + (0, 0, 20), keyColor);
                }

                pianoPlayed = 0;
                if(isDefined(level.a_piano_keys_playing))
                    pianoPlayed = level.a_piano_keys_playing.size;

                guideText += "\\n^3LIGHTNING - PIANO CHORD " + (chordStep + 1) + "/3^7 (" + chordName + ")";
                guideText += "\nShoot the three marked keys with the Lightning Staff (any order):";
                guideText += "\nRED=" + pianoNotes[0] + "  BLUE=" + pianoNotes[1] + "  YELLOW=" + pianoNotes[2];
                guideText += "\n(" + pianoPlayed + "/3 keys hit)";
            }
            else
                guideText += "\\n^3LIGHTNING PIANO^7: waiting for chord data to initialize.";
        }

        // Required switch positions follow the stock path:
        // ELEC -> ICE -> VILLAGE -> AIR -> START -> TANK PLATFORM -> RUINS -> CHAMBER.
        if(self hasweapon("staff_lightning_zm") && flag("electric_puzzle_1_complete") && !flag("electric_puzzle_2_complete"))
        {
            if(isDefined(level.electric_relays))
            {
                relayNames = array("elec", "ice", "village", "air", "start", "tank_platform", "ruins", "bunker");
                relayGoals = array(0, 3, 2, 2, 1, 0, 2, -1);
                guideText += "\\n^3LIGHTNING - RELAY SWITCHES^7: make every active marker GREEN.";
                for(relayIndex = 0; relayIndex < relayNames.size; relayIndex++)
                {
                    relayName = relayNames[relayIndex];
                    relay = level.electric_relays[relayName];
                    if(!isDefined(relay) || !isDefined(relay.e_switch) || !isDefined(relay.e_switch.origin))
                        continue;

                    // Status is carried by marker color instead of a changing
                    // multi-switch HUD string, avoiding configstring growth.
                    relayMarkerColor = (1, 0.35, 0.05);
                    if(relayGoals[relayIndex] < 0)
                        relayMarkerColor = (0.55, 0.55, 0.55);
                    else if(isDefined(relay.position) && relay.position == relayGoals[relayIndex])
                        relayMarkerColor = (0.1, 1, 0.2);

                    markers[markers.size] = self MM_OriginsGuideMakeMarker(relay.e_switch.origin + (0, 0, 24), relayMarkerColor);
                }
                guideText += "\nTargets (positions 0-3): ELEC 0, ICE 3, VILLAGE 2, AIR 2, START 1, TANK 0, RUINS 2.";
                guideText += "\\n^1ORANGE^7 = wrong, ^2GREEN^7 = correct, ^7GRAY^7 = unused BUNKER switch.";
            }
        }

        // WIND: each ring's randomized current position and its stock target
        // are read live. Smoke markers point from each source to its destination.
        if(self hasweapon("staff_air_zm") && !flag("air_puzzle_1_complete"))
        {
            if(isDefined(level.a_ceiling_rings))
            {
                guideText += "\\n^3WIND - RING HIT ESP^7 (ORANGE=shoot, GREEN=aligned):\n";
                // The ring origin is the hit target used by the stock damage
                // handler. Put a waypoint directly over each ring, not in a
                // screen-space list. Orange means it still needs a Wind Staff
                // hit; green means position == script_int and it is solved.
                foreach(ring in level.a_ceiling_rings)
                {
                    if(!isDefined(ring) || !isDefined(ring.origin) || !isDefined(ring.position) || !isDefined(ring.script_int))
                        continue;

                    ringColor = (1, 0.35, 0.05);
                    if(ring.position == ring.script_int)
                        ringColor = (0.1, 1, 0.2);

                    markers[markers.size] = self MM_OriginsGuideMakeMarker(ring.origin + (0, 0, 16), ringColor);
                }
                // Keep this text static. Printing every combination of ring
                // positions creates hundreds of unique HUD strings and can
                // exhaust the engine configstring table (G_FindConfigstringIndex).
                guideText += "\\n^3WIND - CEILING RINGS^7: shoot every ^1ORANGE^7 marker with the Wind Staff.";
                guideText += "\\n^2GREEN^7 markers are already aligned; each dot marks a ring to aim at.";
            }
        }
        else if(self hasweapon("staff_air_zm") && !flag("air_puzzle_2_complete"))
        {
            smokeSources = getstructarray("puzzle_smoke_origin", "targetname");
            smokeIndex = 0;
            foreach(smoke in smokeSources)
            {
                if(!isDefined(smoke) || !isDefined(smoke.origin))
                    continue;
                smokeIndex++;
                markers[markers.size] = self MM_OriginsGuideMakeMarker(smoke.origin + (0, 0, 30), (0.1, 0.8, 1));
            }

            smokeDest = getstruct("puzzle_smoke_dest", "targetname");
            if(isDefined(smokeDest) && isDefined(smokeDest.origin))
                markers[markers.size] = self MM_OriginsGuideMakeMarker(smokeDest.origin + (0, 0, 40), (0.1, 1, 0.2));
            guideText += "\\n^3WIND - SMOKE DIRECTION^7: blue markers are smoke sources; GREEN marker is the destination.";
            guideText += "\nShoot each blue detector with the Wind Staff, then steer its smoke toward the green destination.";
            guideText += "\nSources marked: " + smokeIndex;
        }

        // ICE: the active gem value identifies the correct unsolved ceiling
        // tile. Tombstone markers remain only while their stock stone models exist.
        if(self hasweapon("staff_water_zm") && !flag("ice_puzzle_1_complete"))
        {
            iceGem = getent("ice_chamber_gem", "targetname");
            if(isDefined(iceGem) && isDefined(iceGem.value) && iceGem.value >= 0)
            {
                iceValue = iceGem.value;
                iceCode = "";
                if(isDefined(level.ternary_digits) && iceValue < level.ternary_digits.size)
                {
                    digits = level.ternary_digits[iceValue];
                    for(digitIndex = 0; digitIndex < 3; digitIndex++)
                    {
                        if(digitIndex > 0)
                            iceCode += "-";
                        if(digits[digitIndex] >= 0)
                            iceCode += digits[digitIndex];
                        else
                            iceCode += "X";
                    }
                }

                if(isDefined(level.unsolved_tiles))
                {
                    correctTileCount = 0;
                    foreach(tile in level.unsolved_tiles)
                    {
                        if(!isDefined(tile) || !isDefined(tile.origin) || !isDefined(tile.value) || tile.value != iceValue)
                            continue;
                        if(isDefined(tile.showing_tile_side) && !tile.showing_tile_side)
                            continue;
                        correctTileCount++;
                        markers[markers.size] = self MM_OriginsGuideMakeMarker(tile.origin + (0, 0, 36), (0.1, 1, 0.2));
                    }
                    guideText += "\\n^3ICE - CEILING TILE^7: shoot the GREEN-marked tile with the Ice Staff.";
                    guideText += "\nLive gem value: " + iceValue + "   Ternary display: " + iceCode + "   Matching tiles: " + correctTileCount;
                }
            }
            else
                guideText += "\\n^3ICE CEILING TILE^7: waiting for the gem to display its next value.";
        }
        else if(self hasweapon("staff_water_zm") && !flag("ice_puzzle_2_complete"))
        {
            iceStones = getstructarray("puzzle_stone_water", "targetname");
            stoneCount = 0;
            foreach(stone in iceStones)
            {
                if(!isDefined(stone) || !isDefined(stone.e_model) || !isDefined(stone.e_model.origin))
                    continue;
                stoneCount++;
                markers[markers.size] = self MM_OriginsGuideMakeMarker(stone.e_model.origin + (0, 0, 24), (0.1, 0.8, 1));
            }

            stonesLeft = stoneCount;
            if(isDefined(level.ice_stones_remaining))
                stonesLeft = level.ice_stones_remaining;
            guideText += "\\n^3ICE - CRAZY PLACE TOMBSTONES^7: freeze every blue marker with the Ice Staff.";
            guideText += "\nThen shoot each frozen stone with a normal bullet weapon (NOT a Staff).";
            guideText += "\nStones remaining: " + stonesLeft;
        }

        // CRYPT: once both local puzzles for a staff are complete, the
        // matching chamber gem must be hit and the four outer discs aligned.
        if(self hasweapon("staff_fire_zm") && flag("fire_puzzle_1_complete") && flag("fire_puzzle_2_complete") && !flag("staff_fire_zm_upgrade_unlocked"))
        {
            cryptGuide = self MM_OriginsBuildCryptGuide("crypt_gem_fire", "fire_orb_plinth_final");
            foreach(cryptMarker in cryptGuide.markers)
                markers[markers.size] = cryptMarker;
            guideText += "\\n^3FIRE - CRYPT ORB^7: " + cryptGuide.text;
        }
        if(self hasweapon("staff_air_zm") && flag("air_puzzle_1_complete") && flag("air_puzzle_2_complete") && !flag("staff_air_zm_upgrade_unlocked"))
        {
            cryptGuide = self MM_OriginsBuildCryptGuide("crypt_gem_air", "air_orb_plinth_final");
            foreach(cryptMarker in cryptGuide.markers)
                markers[markers.size] = cryptMarker;
            guideText += "\\n^3WIND - CRYPT ORB^7: " + cryptGuide.text;
        }
        if(self hasweapon("staff_lightning_zm") && flag("electric_puzzle_1_complete") && flag("electric_puzzle_2_complete") && !flag("staff_lightning_zm_upgrade_unlocked"))
        {
            cryptGuide = self MM_OriginsBuildCryptGuide("crypt_gem_elec", "lightning_orb_plinth_final");
            foreach(cryptMarker in cryptGuide.markers)
                markers[markers.size] = cryptMarker;
            guideText += "\\n^3LIGHTNING - CRYPT ORB^7: " + cryptGuide.text;
        }
        if(self hasweapon("staff_water_zm") && flag("ice_puzzle_1_complete") && flag("ice_puzzle_2_complete") && !flag("staff_water_zm_upgrade_unlocked"))
        {
            cryptGuide = self MM_OriginsBuildCryptGuide("crypt_gem_ice", "ice_orb_plinth_final");
            foreach(cryptMarker in cryptGuide.markers)
                markers[markers.size] = cryptMarker;
            guideText += "\\n^3ICE - CRYPT ORB^7: " + cryptGuide.text;
        }

        for(slot = 0; slot < maxMarkers; slot++)
        {
            if(slot < markers.size && isDefined(markers[slot]) && isDefined(markers[slot].origin))
            {
                marker = markers[slot];
                markerHuds[slot].x = marker.origin[0];
                markerHuds[slot].y = marker.origin[1];
                markerHuds[slot].z = marker.origin[2];
                markerHuds[slot].color = marker.color;
                markerHuds[slot].alpha = 1;
            }
            else
                markerHuds[slot].alpha = 0;
        }

        // Match the main menu's 8-row viewport exactly: same objective font,
        // 1.25 scale and 19-pixel row spacing. Five overview rows stay pinned;
        // only two detailed instruction rows rotate. Markers remain live.
        guideLines = strtok(guideText, "\n");
        summaryLineCount = 5;
        detailLinesPerPage = 2;
        detailCount = guideLines.size - summaryLineCount;
        if(detailCount < 0)
            detailCount = 0;

        pageCount = 1;
        if(detailCount > 0)
        {
            pageCount = 0;
            linesRemaining = detailCount;
            while(linesRemaining > 0)
            {
                pageCount++;
                linesRemaining -= detailLinesPerPage;
            }
        }

        if(pageIndex >= pageCount)
            pageIndex = 0;

        displayRows = [];
        for(lineIndex = 0; lineIndex < summaryLineCount && lineIndex < guideLines.size; lineIndex++)
            displayRows[displayRows.size] = guideLines[lineIndex];

        pageStart = summaryLineCount + (pageIndex * detailLinesPerPage);
        for(lineIndex = pageStart; lineIndex < pageStart + detailLinesPerPage && lineIndex < guideLines.size; lineIndex++)
            displayRows[displayRows.size] = guideLines[lineIndex];

        displayRows[displayRows.size] = "^7[GUIDE " + (pageIndex + 1) + "/" + pageCount + "]";

        for(rowIndex = 0; rowIndex < guideRowCount; rowIndex++)
        {
            if(rowIndex < displayRows.size)
            {
                if(!isDefined(guideLastRows[rowIndex]) || guideLastRows[rowIndex] != displayRows[rowIndex])
                {
                    guideHuds[rowIndex] setText(displayRows[rowIndex]);
                    guideLastRows[rowIndex] = displayRows[rowIndex];
                }
                guideHuds[rowIndex].alpha = 1;
            }
            else
                guideHuds[rowIndex].alpha = 0;
        }

        pageTimer += 0.25;
        if(pageTimer >= 5)
        {
            pageTimer = 0;
            pageIndex++;
            if(pageIndex >= pageCount)
                pageIndex = 0;
        }
        wait 0.25;
    }

    foreach(markerHud in markerHuds)
    {
        if(isDefined(markerHud))
            markerHud destroy();
    }
    foreach(guideHud in guideHuds)
    {
        if(isDefined(guideHud))
            guideHud destroy();
    }
    self.mmOriginsStaffGuideHuds = [];
    self.mmOriginsStaffGuideTextHuds = [];
    self.mmOriginsStaffGuideActive = false;
}

MM_OriginsGuideMakeMarker(origin, color)
{
    marker = spawnstruct();
    marker.origin = origin;
    marker.color = color;
    return marker;
}

MM_OriginsPianoChordTracker()
{
    level endon("end_game");
    level.mmOriginsPianoChordStep = 0;
    lastRinging = flag("piano_chord_ringing");

    for(;;)
    {
        if(flag("electric_puzzle_1_complete"))
        {
            level.mmOriginsPianoChordStep = 3;
            break;
        }

        ringing = flag("piano_chord_ringing");
        // The stock script raises this flag after a chord is accepted, holds
        // it during the chord cooldown, then clears it before the next chord.
        // Advance on the falling edge so the just-solved chord stays displayed
        // until the stock script is ready for the next one.
        if(!ringing && lastRinging && level.mmOriginsPianoChordStep < 3)
            level.mmOriginsPianoChordStep++;

        lastRinging = ringing;
        wait 0.05;
    }
}

MM_OriginsStaffGuideLine(label, craftableName, baseWeapon, upgradedWeapon, upgradeFlag, crystalIndex)
{
    parts = 0;
    if(isDefined(level.num_staffpieces_picked_up) &&
       isDefined(level.num_staffpieces_picked_up[craftableName]))
        parts = level.num_staffpieces_picked_up[craftableName];

    built = isDefined(level.craftables_crafted) &&
            isDefined(level.craftables_crafted[craftableName]) &&
            level.craftables_crafted[craftableName];
    upgradeReady = flag(upgradeFlag);
    placed = false;
    if(isDefined(level.a_elemental_staffs_upgraded))
    {
        foreach(staff in level.a_elemental_staffs_upgraded)
        {
            if(!isDefined(staff) || !isDefined(staff.base_weapname) ||
               staff.base_weapname != baseWeapon)
                continue;
            if(isDefined(staff.ee_in_use) && staff.ee_in_use)
                placed = true;
        }
    }

    if(placed)
        step = "^2Upgraded staff placed in robot";
    else if(self hasweapon(upgradedWeapon))
        step = "^3Place upgraded staff in its matching robot";
    else if(upgradeReady)
    {
        charge = self MM_OriginsStaffChargeProgress(baseWeapon);
        if(charge >= 20)
            step = "^2Charger full - pick up the upgraded staff";
        else
            step = "^3Insert base staff at its charger; souls: " + charge + "/20";
    }
    else if(self hasweapon(baseWeapon))
    {
        if(label == "WIND")
        {
            if(!flag("air_puzzle_1_complete"))
                step = "^3Crazy Place: align the 3 ceiling rings";
            else if(!flag("air_puzzle_2_complete"))
                step = "^3Crazy Place: aim smoke streams at the green destination";
            else
                step = "^3Crypt: hit the Wind gem and align all 4 discs";
        }
        else if(label == "FIRE")
        {
            if(!flag("fire_puzzle_1_complete"))
                step = "^3Crazy Place: clear all marked soul chests";
            else if(!flag("fire_puzzle_2_complete"))
                step = "^3Church: light all 4 marked torches";
            else
                step = "^3Crypt: hit the Fire gem and align all 4 discs";
        }
        else if(label == "LIGHTNING")
        {
            if(!flag("electric_puzzle_1_complete"))
                step = "^3Crazy Place: play the marked piano chord";
            else if(!flag("electric_puzzle_2_complete"))
                step = "^3Crazy Place: set the marked relay switches";
            else
                step = "^3Crypt: hit the Lightning gem and align all 4 discs";
        }
        else
        {
            if(!flag("ice_puzzle_1_complete"))
                step = "^3Crazy Place: shoot the green-marked ceiling tile";
            else if(!flag("ice_puzzle_2_complete"))
                step = "^3Crazy Place: freeze and shatter all marked tombstones";
            else
                step = "^3Crypt: hit the Ice gem and align all 4 discs";
        }
    }
    else if(parts >= 3 && !built)
        step = "^3Build it at the excavation table";
    else if(built)
        step = "^3Pick up the base staff";
    else
        step = "^3Find staff parts (" + parts + "/3)";

    return "^7" + label + ": " + step;
}

MM_OriginsGetStaffCharger(baseWeapon)
{
    if(!isDefined(level.a_elemental_staffs))
        return undefined;

    foreach(staff in level.a_elemental_staffs)
    {
        if(!isDefined(staff) || !isDefined(staff.weapname) || staff.weapname != baseWeapon)
            continue;
        if(isDefined(staff.charger))
            return staff.charger;
    }
    return undefined;
}

MM_OriginsGetStaffUpgradeEntity(baseWeapon)
{
    if(!isDefined(level.a_elemental_staffs_upgraded))
        return undefined;

    foreach(staff in level.a_elemental_staffs_upgraded)
    {
        if(!isDefined(staff) || !isDefined(staff.base_weapname) || staff.base_weapname != baseWeapon)
            continue;
        return staff;
    }
    return undefined;
}

MM_OriginsStaffChargeProgress(baseWeapon)
{
    if(isDefined(level.a_elemental_staffs))
    {
        foreach(staff in level.a_elemental_staffs)
        {
            if(!isDefined(staff) || !isDefined(staff.weapname) || staff.weapname != baseWeapon)
                continue;
            if(isDefined(staff.charger) && isDefined(staff.charger.charges_received))
                return staff.charger.charges_received;
        }
    }
    return 0;
}

MM_OriginsBuildCryptGuide(gemName, plinthName)
{
    data = spawnstruct();
    data.markers = [];
    data.text = "";

    gemFound = false;
    cryptGems = getentarray("crypt_gem", "script_noteworthy");
    foreach(gem in cryptGems)
    {
        if(!isDefined(gem) || !isDefined(gem.targetname) || gem.targetname != gemName || !isDefined(gem.origin))
            continue;
        data.markers[data.markers.size] = self MM_OriginsGuideMakeMarker(gem.origin + (0, 0, 36), (1, 0.12, 0.08));
        gemFound = true;
    }

    finalPlinth = getstruct(plinthName, "targetname");
    if(isDefined(finalPlinth) && isDefined(finalPlinth.origin))
        data.markers[data.markers.size] = self MM_OriginsGuideMakeMarker(finalPlinth.origin + (0, 0, 36), (0.1, 1, 0.2));

    if(gemFound)
        data.text = "Shoot the RED matching gem with that staff.";
    else
        data.text = "Gem already launched or waiting for its model; use the disc guide below.";

    if(isDefined(finalPlinth))
        data.text += " GREEN marker = its final orb plinth.";

    if(isDefined(level.gem_start_pos) && isDefined(level.gem_start_pos[gemName]))
    {
        mainDisc = getent("crypt_puzzle_disc_main", "targetname");
        if(isDefined(mainDisc) && isDefined(mainDisc.position) && isDefined(mainDisc.origin))
        {
            targetPosition = (mainDisc.position + level.gem_start_pos[gemName]) % 4;
            data.markers[data.markers.size] = self MM_OriginsGuideMakeMarker(mainDisc.origin + (0, 0, 34), (1, 1, 1));
            data.text += "\nMAIN disc=" + mainDisc.position + "; all four outer discs must equal " + targetPosition + ".";

            discs = getentarray("crypt_puzzle_disc", "script_noteworthy");
            discFallbackIndex = 0;
            foreach(disc in discs)
            {
                if(!isDefined(disc) || !isDefined(disc.origin) || !isDefined(disc.position))
                    continue;
                if(isDefined(disc.targetname) && disc.targetname == "crypt_puzzle_disc_main")
                    continue;

                discFallbackIndex++;
                discIndex = discFallbackIndex;
                if(isDefined(disc.script_int) && disc.script_int >= 1 && disc.script_int <= 4)
                    discIndex = disc.script_int;

                discColor = (1, 0.12, 0.08);
                discColorName = "RED";
                if(discIndex == 2)
                {
                    discColor = (0.1, 0.35, 1);
                    discColorName = "BLUE";
                }
                else if(discIndex == 3)
                {
                    discColor = (1, 0.9, 0.1);
                    discColorName = "YELLOW";
                }
                else if(discIndex == 4)
                {
                    discColor = (0.8, 0.2, 1);
                    discColorName = "PURPLE";
                }

                data.markers[data.markers.size] = self MM_OriginsGuideMakeMarker(disc.origin + (0, 0, 34), discColor);
                discStatus = "FIX";
                if(disc.position == targetPosition)
                    discStatus = "OK";
                data.text += "\nD" + discIndex + " " + discColorName + " " + disc.position + "->" + targetPosition + " [" + discStatus + "]";
            }
        }
        else
            data.text += "\nWaiting for Crypt disc state to initialize.";
    }
    else
        data.text += "\nWaiting for Crypt gem position data.";

    return data;
}


MM_OriginsStaffProgress()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1Staff tracker is only available on Origins.");
        return;
    }

    self iprintlnbold("^3ORIGINS STAFF PROGRESS");
    self MM_OriginsPrintStaffState("Wind", "elemental_staff_air", "staff_air_zm", "staff_air_zm_upgrade_unlocked", 2);
    self MM_OriginsPrintStaffState("Fire", "elemental_staff_fire", "staff_fire_zm", "staff_fire_zm_upgrade_unlocked", 1);
    self MM_OriginsPrintStaffState("Lightning", "elemental_staff_lightning", "staff_lightning_zm", "staff_lightning_zm_upgrade_unlocked", 3);
    self MM_OriginsPrintStaffState("Ice", "elemental_staff_water", "staff_water_zm", "staff_water_zm_upgrade_unlocked", 4);

    if(flag("ee_all_staffs_placed"))
        self iprintln("^2All four staffs are placed in the robots.");
    else
        self iprintln("^3All staffs placed: NO");
}

MM_OriginsPrintStaffState(label, craftableName, weaponName, upgradeFlag, crystalIndex)
{
    built = false;
    upgraded = flag(upgradeFlag);
    placed = false;
    partsPickedUp = 0;
    crystalHeld = isDefined(self.crystal_id) && self.crystal_id == crystalIndex;

    if(isDefined(level.craftables_crafted) && isDefined(level.craftables_crafted[craftableName]) && level.craftables_crafted[craftableName])
        built = true;

    if(isDefined(level.num_staffpieces_picked_up) && isDefined(level.num_staffpieces_picked_up[craftableName]))
        partsPickedUp = level.num_staffpieces_picked_up[craftableName];

    // The stock robot-head interaction marks the UPGRADED staff entity as
    // ee_in_use, so inspect the upgraded entity registry for placed staffs.
    if(isDefined(level.a_elemental_staffs_upgraded))
    {
        foreach(staff in level.a_elemental_staffs_upgraded)
        {
            if(!isDefined(staff) || !isDefined(staff.base_weapname) || staff.base_weapname != weaponName)
                continue;
            if(isDefined(staff.ee_in_use) && staff.ee_in_use)
                placed = true;
        }
    }

    status = "^1Not built";
    if(built)
        status = "^2Built";
    if(upgraded)
        status = status + " ^7| ^2Upgraded";
    else
        status = status + " ^7| ^1Not upgraded";
    if(placed)
        status = status + " ^7| ^2Placed";
    else
        status = status + " ^7| ^3Not placed";
    gemStatus = "^3Gem not held";
    if(crystalHeld)
        gemStatus = "^2Gem held";
    self iprintln("^7" + label + ": ^7Parts " + partsPickedUp + " / 3 ^7| " + gemStatus);
    self iprintln("^7  " + status);
}

MM_OriginsRecoverDrone()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1Maxis Drone Recovery is only available on Origins.");
        return;
    }

    if(!isDefined(level.maxis_quadrotor))
    {
        self iprintln("^3No active Maxis drone is currently flying.");
        return;
    }

    // This is the native notification watched by the stock drone controller;
    // it sends the live drone back to its build/pickup table.
    level notify("drone_should_return");
    self iprintln("^2Maxis drone recall requested.");
}

MM_OriginsGivePunch(element)
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1One Inch Punch is only available on Origins.");
        return;
    }

    if(!isDefined(element))
        element = "normal";

    punchFunc = getfunction("maps/mp/zombies/_zm_weap_one_inch_punch", "one_inch_punch_melee_attack");
    if(!isDefined(punchFunc))
    {
        self iprintln("^1The stock One Inch Punch handler is not available.");
        return;
    }

    if(element == "normal")
    {
        self.b_punch_upgraded = 0;
        self.str_punch_element = "upgraded";
    }
    else
    {
        self.b_punch_upgraded = 1;
        self.str_punch_element = element;
    }

    self thread [[ punchFunc ]]();
    self iprintlnbold("^2One Inch Punch loadout requested: ^7" + element);
}

MM_OriginsToggleRobotWarning()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1Robot Foot Warning is only available on Origins.");
        return;
    }

    self scripts\zm\zm_modmenu::MM_Toggle("origrobotwarn", "Robot Foot Warning", ::MM_OriginsRobotWarningLoop);
}

MM_OriginsRobotWarningLoop()
{
    self endon("disconnect");

    warning = newClientHudElem(self);
    warning.horzAlign = "center";
    warning.vertAlign = "top";
    warning.alignX = "center";
    warning.alignY = "top";
    warning.x = 0;
    warning.y = 28;
    warning.font = "objective";
    warning.fontScale = 1.7;
    warning.foreground = true;
    warning.hideWhenInMenu = true;
    warning.sort = 1200;
    warning.alpha = 0;

    while(self scripts\zm\zm_modmenu::MM_IsOn("origrobotwarn"))
    {
        closest = undefined;
        closestDist = 999999999;
        if(isDefined(level.a_giant_robots))
        {
            foreach(robot in level.a_giant_robots)
            {
                if(!isDefined(robot) || !isDefined(robot.origin) || !isDefined(robot.is_walking) || !robot.is_walking)
                    continue;
                d = distancesquared(self.origin, robot.origin);
                if(d < closestDist)
                {
                    closestDist = d;
                    closest = robot;
                }
            }
        }

        if(isDefined(closest) && closestDist < 4000000)
        {
            safe = false;
            if(isDefined(level.giant_robot_footstep_safe_spots))
            {
                foreach(safeSpot in level.giant_robot_footstep_safe_spots)
                {
                    if(isDefined(safeSpot) && self istouching(safeSpot))
                    {
                        safe = true;
                        break;
                    }
                }
            }

            if(safe)
            {
                warning.color = (0.2, 1, 0.2);
                warning setText("GIANT ROBOT MOVING - SAFE SPOT");
            }
            else
            {
                warning.color = (1, 0.15, 0.05);
                warning setText("GIANT ROBOT APPROACHING - FIND COVER!");
            }
            warning.alpha = 1;
        }
        else
            warning.alpha = 0;

        wait 0.15;
    }

    if(isDefined(warning))
        warning destroy();
}

MM_OriginsTankStatus()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1Tank controls are only available on Origins.");
        return;
    }
    tank = undefined;
    if(isDefined(level.vh_tank))
        tank = level.vh_tank;
    if(!isDefined(tank))
        tank = getent("tank", "targetname");
    if(!isDefined(tank))
    {
        self iprintln("^1Origins tank entity is not available yet.");
        return;
    }

    current = "unknown";
    if(isDefined(tank.str_location_current))
        current = tank.str_location_current;
    next = "village";
    if(current == "village")
        next = "bunkers";
    else if(current == "bunkers")
        next = "village";

    if(tank ent_flag("tank_moving"))
        state = "^2MOVING";
    else if(tank ent_flag("tank_cooldown"))
        state = "^3COOLDOWN";
    else if(tank ent_flag("tank_activated"))
        state = "^3ACTIVATED";
    else
        state = "^2STOPPED";

    self iprintlnbold("^3ORIGINS TANK STATUS");
    self iprintln("^7State: " + state);
    self iprintln("^7Current station: ^2" + current);
    self iprintln("^7Next station: ^3" + next);
}

MM_OriginsCallTank()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1Tank controls are only available on Origins.");
        return;
    }

    tank = undefined;
    if(isDefined(level.vh_tank))
        tank = level.vh_tank;
    if(!isDefined(tank))
        tank = getent("tank", "targetname");
    if(!isDefined(tank) || !isDefined(tank.t_use))
    {
        self iprintln("^1Tank use trigger is not available yet.");
        return;
    }
    if(tank ent_flag("tank_moving") || tank ent_flag("tank_activated"))
    {
        self iprintln("^3The tank is already moving or activated.");
        return;
    }
    if(tank ent_flag("tank_cooldown"))
    {
        self iprintln("^3The tank is cooling down. Try again after it is ready.");
        return;
    }
    if(self.score < 500)
    {
        self iprintln("^1You need 500 points to call the tank.");
        return;
    }

    // Let the stock use handler perform the payment and movement flags.
    tank.t_use useby(self);
    self iprintln("^2Tank call activated through the stock interaction.");
}

MM_OriginsTeleportFunc(name)
{
    if(!isDefined(level.mm_origins_teleport_funcs))
        level.mm_origins_teleport_funcs = [];
    if(!isDefined(level.mm_origins_teleport_funcs[name]))
        level.mm_origins_teleport_funcs[name] = getfunction("maps/mp/zm_tomb_teleporter", name);
    return level.mm_origins_teleport_funcs[name];
}

MM_OriginsTeleportHasFreeSpot(targetName)
{
    if(!isDefined(targetName) || targetName == "")
        return false;
    spots = getstructarray(targetName, "targetname");
    if(!isDefined(spots) || spots.size < 1)
        return false;
    players = getplayers();
    foreach(spot in spots)
    {
        if(!isDefined(spot) || !isDefined(spot.origin))
            continue;
        free = true;
        foreach(player in players)
        {
            if(isDefined(player) && distance2dsquared(spot.origin, player.origin) < 4096)
            {
                free = false;
                break;
            }
        }
        if(free)
            return true;
    }
    return false;
}

MM_OriginsTeleportCrazyPlace()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1Crazy Place teleport is only available on Origins.");
        return;
    }
    if(!flag("start_zombie_round_logic"))
    {
        self iprintln("^1Start the first round before teleporting.");
        return;
    }

    pads = getstructarray("trigger_teleport_pad", "targetname");
    teleportFunc = MM_OriginsTeleportFunc("stargate_teleport_player");
    if(!isDefined(teleportFunc))
    {
        self iprintln("^1The stock Origins teleporter handler is unavailable.");
        return;
    }

    foreach(pad in pads)
    {
        if(!isDefined(pad) || !isDefined(pad.target) || !isDefined(pad.script_int))
            continue;
        if(!flag("enable_teleporter_" + pad.script_int))
            continue;
        if(!MM_OriginsTeleportHasFreeSpot(pad.target))
            continue;

        level thread [[ teleportFunc ]](pad.target, self, 1.5, 1);
        self iprintln("^2Crazy Place teleport started.");
        return;
    }
    self iprintln("^1No active Crazy Place portal with a free landing spot was found.");
}


// Enter one of the three giant robots using the map's own head teleport target.
// The hatch must already be open; this preserves the stock foot/hatch timing.
MM_OriginsTeleportRobot(robotId)
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1Robot teleport is only available on Origins.");
        return;
    }
    if(!isDefined(robotId) || robotId < 0 || robotId > 2)
        return;    if(!isDefined(level.a_giant_robots) || !isDefined(level.a_giant_robots[robotId]))
    {
        self iprintln("^1That giant robot is not initialized yet.");
        return;
    }
    if(!isDefined(level.gr_foot_hatch_closed) ||
       !isDefined(level.gr_foot_hatch_closed[robotId]) ||
       level.gr_foot_hatch_closed[robotId])
    {
        self iprintln("^3Wait for Robot " + (robotId + 1) + "'s hatch to open before entering.");
        return;
    }

    robot = level.a_giant_robots[robotId];
    if(!isDefined(robot) || !isDefined(robot.b_has_hatch) || !robot.b_has_hatch)
    {
        self iprintln("^1That robot's hatch is not available.");
        return;
    }
    if(isDefined(self.in_giant_robot_head))
    {
        self iprintln("^3You are already inside a giant robot.");
        return;
    }

    targetName = "head_" + robotId + "_teleport_player";
    teleportFunc = MM_OriginsTeleportFunc("stargate_teleport_player");
    if(!isDefined(teleportFunc) || !MM_OriginsTeleportHasFreeSpot(targetName))
    {
        self iprintln("^1The stock robot-head teleport destination is unavailable.");
        return;
    }

    self.ignoreme = 1;
    self.teleport_initial_origin = self.origin;
    self.in_giant_robot_head = robotId;
    robot ent_flag_set("robot_head_entered");
    level thread [[ teleportFunc ]](targetName, self, 4.0, 0);

    // Start the same stock head watchdog and transition workers used by the
    // foot trigger. Resolve them at runtime to avoid cross-map externals.
    watchFunc = getfunction("maps/mp/zm_tomb_giant_robot", "player_death_watch_on_giant_robot");
    startFunc = getfunction("maps/mp/zm_tomb_giant_robot", "player_transition_into_robot_head_start");
    finishFunc = getfunction("maps/mp/zm_tomb_giant_robot", "player_transition_into_robot_head_finish");
    // Resolve the HUD fade helper at runtime. A direct call here creates an
    // unresolved external because this mod-menu script does not include _hud.
    fadeFunc = getfunction("maps/mp/gametypes_zm/_hud", "fadetoblackforxsec");
    if(isDefined(fadeFunc))
        self thread [[ fadeFunc ]](0, 4.0, 0.01, 0.2, "white");
    if(isDefined(watchFunc))
        self thread [[ watchFunc ]]();
    if(isDefined(startFunc))
        self thread [[ startFunc ]](0.01);
    if(isDefined(finishFunc))
        self thread [[ finishFunc ]](4.21);

    self iprintlnbold("^2Entering Robot " + (robotId + 1) + ".");
}

MM_OriginsTeleportMainMap(portalIndex)
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1Map exit teleport is only available on Origins.");
        return;
    }
    if(!isDefined(level.a_teleport_exit_triggers) || !isDefined(level.a_teleport_exit_triggers[portalIndex]))
    {
        self iprintln("^1That Crazy Place exit is not initialized yet.");
        return;
    }

    exitTrigger = level.a_teleport_exit_triggers[portalIndex];
    if(!isDefined(exitTrigger.origin) || distance2dsquared(self.origin, exitTrigger.origin) > 4000000)
    {
        self iprintln("^3You must be inside the Crazy Place to use a return portal.");
        return;
    }
    if(!isDefined(exitTrigger.target) || !MM_OriginsTeleportHasFreeSpot(exitTrigger.target))
    {
        self iprintln("^1That exit has no available landing spot right now.");
        return;
    }

    teleportFunc = MM_OriginsTeleportFunc("stargate_teleport_player");
    if(!isDefined(teleportFunc))
    {
        self iprintln("^1The stock Origins teleporter handler is unavailable.");
        return;
    }

    level thread [[ teleportFunc ]](exitTrigger.target, self, 1.5, 1);
    self iprintln("^2Return to the Origins map started.");
}


// Stage the four elemental crystals through the same stock notification that
// Origins' teleporter sends after a successful portal trip. Each crystal's
// native staff_crystal_wait_for_teleport thread then raises its own plinth.
MM_OriginsStageAllCrystals()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1Staff crystals are only available on Origins.");
        return;
    }
    if(!self isHost())
    {
        self iprintln("^1Staging all four crystals requires the host.");
        return;
    }
    if(!flag("start_zombie_round_logic"))
    {
        self iprintln("^1Start the first round before staging crystals.");
        return;
    }

    if(!isDefined(level.a_elemental_staffs) || level.a_elemental_staffs.size < 4)
    {
        self iprintln("^1The Origins staff system is not initialized yet.");
        return;
    }

    staged = 0;
    for(element = 1; element <= 4; element++)
    {
        level notify("player_teleported", self, element);
        staged++;
        wait_network_frame();
    }

    self iprintlnbold("^2All four native staff-crystal plinths were signalled.");
    self iprintln("^7This stages the crystals in the Crazy Place; it does not grant four carried inventory items.");
}

MM_OriginsCollectAllSharedParts()
{
    self MM_OriginsCollectSharedParts(false);
}

// _zm_craftables only ships on maps that use it (Origins, Mob of the Dead). A
// direct file::function reference is resolved at script load and causes
// "Unresolved external" on every other map, so look the functions up at runtime.
// getfunction() returns undefined when the file is not loaded.
MM_CraftablesFunc(name)
{
    if(!isDefined(level.mm_craftables_funcs))
        level.mm_craftables_funcs = [];

    if(!isDefined(level.mm_craftables_funcs[name]))
        level.mm_craftables_funcs[name] = getfunction("maps/mp/zombies/_zm_craftables", name);

    return level.mm_craftables_funcs[name];
}

MM_OriginsCollectSharedParts(quiet)
{
    if(level.script != "zm_tomb")
    {
        if(!quiet)
            self iprintln("^1This action is only available on Origins.");
        return;
    }

    if(!self isHost())
    {
        if(!quiet)
            self iprintln("^1Collecting shared map parts requires the host.");
        return;
    }

    if(!flag("start_zombie_round_logic"))
    {
        if(!quiet)
            self iprintln("^1Start the first round before collecting map parts.");
        return;
    }

    if(!isDefined(level.zombie_include_craftables))
    {
        if(!quiet)
            self iprintln("^1Origins craftables are not ready yet. Try again after the round starts.");
        return;
    }

    collected = 0;
    skipped = 0;

    foreach(craftable in level.zombie_include_craftables)
    {
        if(!isDefined(craftable) || !isDefined(craftable.a_piecestubs))
            continue;

        foreach(piecestub in craftable.a_piecestubs)
        {
            // Origins staff stems/tips and several other build pieces are
            // shared inventory items. Crystals are intentionally excluded:
            // they are non-shared and the stock game allows one at a time.
            if(!isDefined(piecestub) || !isDefined(piecestub.is_shared) || !piecestub.is_shared)
                continue;
            if(!isDefined(piecestub.spawns) || piecestub.spawns.size < 1)
                continue;

            if(isDefined(piecestub.piecespawn))
            {
                if(isDefined(piecestub.piecespawn.in_shared_inventory) && piecestub.piecespawn.in_shared_inventory)
                    continue;
                if(isDefined(piecestub.piecespawn.crafted) && piecestub.piecespawn.crafted)
                    continue;
            }

            piece = undefined;
            if(isDefined(piecestub.piecespawn) && isDefined(piecestub.piecespawn.model))
                piece = piecestub.piecespawn;
            else
            {
                // Use the stock generator so map-specific spawn points,
                // callbacks, clientfields and unitrigger data stay correct.
                generate_piece_func = MM_CraftablesFunc("generate_piece");
                if(isDefined(generate_piece_func))
                    piece = [[ generate_piece_func ]](piecestub);
                piecestub.piecespawn = piece;
            }

            if(isDefined(piece) && isDefined(piece.model) && isDefined(piece.unitrigger))
            {
                take_piece_func = MM_CraftablesFunc("player_take_piece");
                if(!isDefined(take_piece_func))
                {
                    skipped++;
                    continue;
                }

                self [[ take_piece_func ]](piece);
                collected++;
                wait 0.05;
            }
            else
                skipped++;
        }
    }

    if(!quiet)
    {
        if(collected > 0)
            self iprintlnbold("^2Origins shared parts collected: ^7" + collected);
        else
            self iprintln("^3No uncollected shared parts are currently available.");

        if(skipped > 0)
            self iprintln("^3Some registered spawns were unavailable and were skipped: " + skipped);
        self iprintln("^7Crystal pickups are individual items and are not bulk-collected.");
    }
}

MM_OriginsToggleAutoCollect()
{
    self scripts\zm\zm_modmenu::MM_Toggle("origcollect", "Auto-Collect Shared Parts", ::MM_OriginsAutoCollectLoop);
}

MM_OriginsAutoCollectLoop()
{
    self endon("disconnect");

    while(self scripts\zm\zm_modmenu::MM_IsOn("origcollect"))
    {
        if(level.script != "zm_tomb")
        {
            self.mmToggle["origcollect"] = false;
            self iprintln("^1Origins auto-collect stopped: map changed.");
            break;
        }

        self MM_OriginsCollectSharedParts(true);
        wait 0.75;
    }
}

// Force all four native staff chargers to the stock 20-soul completion
// threshold. The real Origins charger threads still create the upgrade
// pickup triggers and set ee_all_staffs_upgraded when all four finish.
MM_OriginsUpgradeAllStaffs()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1This action is only available on Origins.");
        return;
    }

    if(!self isHost())
    {
        self iprintln("^1Staff upgrades require the host.");
        return;
    }

    if(!flag("start_zombie_round_logic"))
    {
        self iprintln("^1Start the first round before upgrading the staffs.");
        return;
    }

    if(!isDefined(level.a_elemental_staffs) || level.a_elemental_staffs.size < 4)
    {
        self iprintln("^1The Origins staff system is not initialized yet.");
        return;
    }

    upgraded = 0;
    foreach(staff in level.a_elemental_staffs)
    {
        if(!isDefined(staff) || !isDefined(staff.charger) || !isDefined(staff.weapname))
            continue;

        staff.charger.charges_received = 20;
        flag_set(staff.weapname + "_upgrade_unlocked");
        upgraded++;
        wait_network_frame();
    }

    if(upgraded == 4)
        self iprintlnbold("^2All four staff upgrade chargers forced to full charge.");
    else
        self iprintln("^3Staff chargers updated: " + upgraded + " / 4");
    self iprintln("^7Use Map Weapons to give an upgraded staff; normal weapon-slot limits still apply.");
}

// zm_tomb_capture_zones only exists on Origins. A direct file::function
// reference would raise "Unresolved external" on every other map, so the stock
// capture-zone functions are looked up at runtime (same approach as
// MM_CraftablesFunc). getfunction() returns undefined if the file is not loaded.
MM_OriginsCaptureFunc(name)
{
    if(!isDefined(level.mm_capture_funcs))
        level.mm_capture_funcs = [];

    if(!isDefined(level.mm_capture_funcs[name]))
        level.mm_capture_funcs[name] = getfunction("maps/mp/zm_tomb_capture_zones", name);

    return level.mm_capture_funcs[name];
}

// Captures all six Origins generators so the stock logic powers up the
// Pack-a-Punch (all_zones_captured -> pack_a_punch_enable -> power_on).
// Zones are switched through the game's own set_player_controlled_area(), the
// same call a real capture ends with, so perk machines, mystery boxes, HUD and
// the Pack-a-Punch assembly animation all update normally.
MM_OriginsTurnOnAllGenerators()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1This action is only available on Origins.");
        return;
    }

    if(!self isHost())
    {
        self iprintln("^1Turning on the generators requires the host.");
        return;
    }

    if(!flag("start_zombie_round_logic") || !flag("capture_zones_init_done"))
    {
        self iprintln("^1Start the first round before turning on the generators.");
        return;
    }

    if(!isDefined(level.zone_capture) || !isDefined(level.zone_capture.zones))
    {
        self iprintln("^1The generator system is not initialized yet.");
        return;
    }

    setControlled = MM_OriginsCaptureFunc("set_player_controlled_area");
    if(!isDefined(setControlled))
    {
        self iprintln("^1Could not find the Origins capture-zone functions.");
        return;
    }

    switched = 0;
    foreach(zone in level.zone_capture.zones)
    {
        if(!isDefined(zone))
            continue;

        if(zone ent_flag("zone_contested"))
        {
            // A capture or recapture event is running on this generator: push
            // it to 100% and let the stock capture loop finish it (it also
            // clears the capture zombies and the event flags by itself).
            zone.n_current_progress = 100;
            level setclientfield(zone.script_noteworthy, 1);
            zone ent_flag_clear("zone_contested");
            switched++;
        }
        else if(!zone ent_flag("player_controlled"))
        {
            zone [[ setControlled ]]();
            zone.n_last_progress = zone.n_current_progress;
            zone.n_current_progress = 100;
            level setclientfield("state_" + zone.script_noteworthy, 2);
            level setclientfield(zone.script_noteworthy, 1);
            switched++;
        }

        wait_network_frame();
    }

    wait 0.5;

    if(flag("all_zones_captured"))
    {
        if(switched > 0)
            self iprintlnbold("^2All generators are on. Pack-a-Punch is powered.");
        else
            self iprintln("^3All generators were already on.");
    }
    else
    {
        self iprintln("^3Generators updated: " + switched + ". Captured now: " + level.total_capture_zones + " / 6");
    }
}

// Origins' Little Lost Girl quest is an eight-stage sidequest. This option
// intentionally bypasses those objectives; the final flag triggers the stock
// sidequest ending and ends the current match for everyone.
MM_OriginsConfirmCompleteSecret()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1This action is only available on Origins.");
        return;
    }

    if(!self isHost())
    {
        self iprintln("^1The Origins secret completion requires the host.");
        return;
    }

    if(!isDefined(self.mmOriginsSecretArmed) || !self.mmOriginsSecretArmed)
    {
        self.mmOriginsSecretArmed = true;
        self iprintlnbold("^1WARNING: select this again within 6 seconds to complete the secret and end the match.");
        self thread MM_OriginsSecretConfirmTimeout();
        return;
    }

    self.mmOriginsSecretArmed = false;
    self thread MM_OriginsCompleteSecretThread();
}

MM_OriginsSecretConfirmTimeout()
{
    self endon("disconnect");
    wait 6;
    self.mmOriginsSecretArmed = false;
}

MM_OriginsCompleteSecretThread()
{
    self endon("disconnect");

    if(level.script != "zm_tomb" || !self isHost())
        return;

    if(!flag("start_zombie_round_logic"))
    {
        self iprintln("^1Start the first round before completing the secret.");
        return;
    }

    if(!maps\mp\zombies\_zm_sidequests::is_sidequest_allowed("zclassic"))
    {
        self iprintln("^1The Little Lost Girl secret is not enabled in this game mode.");
        return;
    }

    // Unlock the stock staff upgrade handlers first, then satisfy each stage
    // gate in the same order used by zm_tomb_ee_main and steps 1 through 8.
    flag_set("staff_air_zm_upgrade_unlocked");
    flag_set("staff_fire_zm_upgrade_unlocked");
    flag_set("staff_lightning_zm_upgrade_unlocked");
    flag_set("staff_water_zm_upgrade_unlocked");
    wait_network_frame();

    flag_set("ee_all_staffs_crafted");
    flag_set("all_zones_captured");
    wait_network_frame();

    flag_set("ee_all_staffs_upgraded");
    flag_set("ee_all_staffs_placed");
    wait_network_frame();

    flag_set("ee_mech_zombie_hole_opened");
    flag_set("ee_quadrotor_disabled");
    flag_set("ee_mech_zombie_fight_completed");
    wait_network_frame();

    flag_set("ee_maxis_drone_retrieved");
    flag_set("ee_all_players_upgraded_punch");
    wait_network_frame();

    flag_set("ee_sam_portal_active");
    flag_set("ee_souls_absorbed");
    wait_network_frame();

    self iprintlnbold("^2Origins secret completion requested. The stock ending will now run.");
    wait 0.5;
    flag_set("ee_samantha_released");
}

MM_OriginsToggleNoMudSlow()
{
    if(level.script != "zm_tomb")
    {
        self iprintln("^1Mud slowdown control is only available on Origins.");
        return;
    }

    self scripts\zm\zm_modmenu::MM_Toggle("nomud", "Ignore Mud Slowdown", ::MM_OriginsNoMudSlowLoop);
}

// The stock Origins movement monitor sets self.is_player_slowed and applies
// 0.6 (or 0.7 with Stamin-Up) while touching the mud. Restore normal speed for
// this player only; do not alter the map's shared slow-area entities.
MM_OriginsNoMudSlowLoop()
{
    self endon("disconnect");

    while(self scripts\zm\zm_modmenu::MM_IsOn("nomud"))
    {
        if(isDefined(self.is_player_slowed) && self.is_player_slowed)
        {
            self.n_move_scale = 1.0;
            self setMoveSpeedScale(1.0);
        }
        wait 0.05;
    }
}


// ============================================================================
//  ULTIMATE ZM MOD MENU - MOB OF THE DEAD MODULE
//  Mob of the Dead (zm_prison) only. Everything here hooks into the stock
//  scripts (zm_alcatraz_*, _zm_afterlife, _zm_ai_brutus, zm_prison_spoon):
//  the same notifies / flags / functions the game itself uses. Files that only
//  exist on this map are looked up at runtime with getfunction(), so loading
//  the menu on any other map never raises "Unresolved external".
// ============================================================================

MM_PrisonFunc(file, name)
{
    if(!isDefined(level.mm_prison_funcs))
        level.mm_prison_funcs = [];

    key = file + "::" + name;
    if(!isDefined(level.mm_prison_funcs[key]))
        level.mm_prison_funcs[key] = getfunction(file, name);

    return level.mm_prison_funcs[key];
}

// Common checks: right map, host if required, and the round logic started.
MM_PrisonReady(needHost)
{
    if(level.script != "zm_prison")
    {
        self iprintln("^1This action is only available on Mob of the Dead.");
        return false;
    }

    if(needHost && !self isHost())
    {
        self iprintln("^1This action requires the host.");
        return false;
    }

    if(!flag("start_zombie_round_logic"))
    {
        self iprintln("^1Start the first round first.");
        return false;
    }

    return true;
}

// Notifies the stock thread that powers every perk machine's shock box
// (the same notify the game's own debug command uses). It runs one machine
// per second, so give it a few seconds. Classic mode only.
MM_PrisonPowerPerks()
{
    if(!self MM_PrisonReady(true))
        return;

    level notify("unlock_all_perk_machines");
    self iprintln("^2Powering all perk machines (about one per second)...");
}

// Same notify as the stock debug path: it powers the gondola from the roof
// side and shuts the opposite shock box, exactly like a real power-up.
MM_PrisonPowerGondola()
{
    if(!self MM_PrisonReady(true))
        return;

    if(!flag_exists("gondola_initialized"))
    {
        self iprintln("^1The gondola is not available in this game mode.");
        return;
    }

    if(flag("gondola_initialized"))
    {
        self iprintln("^3The gondola is already powered.");
        return;
    }

    level notify("gondola_powered_on_roof");
    self iprintln("^2Gondola powered.");
}

// Mob's custom Afterlife doors are zombie_door entities marked with
// script_noteworthy="afterlife_door". Use the stock blocker transition, but
// resolve it at runtime so the map-only module cannot cause load-time externals.
MM_PrisonOpenAfterlifeDoors()
{
    if(!self MM_PrisonReady(true))
        return;

    doorOpenedFunc = MM_PrisonFunc("maps/mp/zombies/_zm_blockers", "door_opened");
    if(!isDefined(doorOpenedFunc))
    {
        self iprintln("^1Mob of the Dead door handler is not loaded.");
        return;
    }

    opened = 0;
    doors = getEntArray("zombie_door", "targetname");
    foreach(door in doors)
    {
        if(!isDefined(door) || !isDefined(door.script_noteworthy))
            continue;
        if(door.script_noteworthy != "afterlife_door")
            continue;
        if(isDefined(door.has_been_opened) && door.has_been_opened)
            continue;
        if(isDefined(door.door_is_moving) && door.door_is_moving)
            continue;

        // Same native transition used by Mob's hidden open_sesame debug path.
        door [[ doorOpenedFunc ]](0);
        opened++;
        wait 0.1;
    }

    if(opened > 0)
        self iprintln("^2Afterlife doors opened: ^7" + opened);
    else
        self iprintln("^3No closed Afterlife doors found (or they are still moving).");
}

MM_PrisonUnlockEverything()
{
    if(!self MM_PrisonReady(true))
        return;

    self MM_PrisonPowerPerks();
    self MM_PrisonPowerGondola();
    self MM_PrisonOpenAfterlifeDoors();
}

// Free gondola ride. The stock call trigger on the side the gondola is NOT on
// is parked waiting for a player, so trigger it like a player would: the stock
// code then moves the gondola and re-arms its own buttons correctly.
MM_PrisonSendGondola()
{
    if(!self MM_PrisonReady(false))
        return;

    if(!flag_exists("gondola_initialized") || !flag("gondola_initialized"))
    {
        self iprintln("^1Power the gondola first.");
        return;
    }

    if(flag("gondola_in_motion"))
    {
        self iprintln("^3The gondola is already moving.");
        return;
    }

    if(!isDefined(level.e_gondola) || !isDefined(level.e_gondola.location))
        return;

    here = level.e_gondola.location;
    if(!flag("gondola_at_" + here))
    {
        self iprintln("^3The gondola is still settling. Try again in a moment.");
        return;
    }

    if(!is_player_valid(self))
    {
        self iprintln("^1You can't call the gondola while downed.");
        return;
    }

    other = "roof";
    if(here == "roof")
        other = "docks";

    triggers = getEntArray("gondola_call_trigger", "targetname");
    foreach(trig in triggers)
    {
        if(isDefined(trig) && isDefined(trig.script_string) && trig.script_string == other)
        {
            trig notify("trigger", self);
            self iprintln("^2Gondola sent to the " + other + ".");
            return;
        }
    }

    self iprintln("^1Could not find the gondola call button.");
}

// ---- Afterlife ----

MM_PrisonRefillLife(player)
{
    addFunc = MM_PrisonFunc("maps/mp/zombies/_zm_afterlife", "afterlife_add");
    if(!isDefined(addFunc) || !isDefined(player.lives))
        return false;

    player [[ addFunc ]]();
    return true;
}

MM_PrisonAfterlifeRefill()
{
    if(!self MM_PrisonReady(false))
        return;

    if(self MM_PrisonRefillLife(self))
        self iprintln("^2Afterlife life refilled.");
    else
        self iprintln("^1Afterlife is not available right now.");
}

MM_PrisonAfterlifeRefillAll()
{
    if(!self MM_PrisonReady(true))
        return;

    done = 0;
    foreach(player in getPlayers())
    {
        if(isDefined(player) && self MM_PrisonRefillLife(player))
            done++;
    }

    self iprintln("^2Afterlife life refilled for ^7" + done + "^2 player(s).");
}

MM_PrisonToggleInfMana()
{
    if(!self MM_PrisonReady(false))
        return;

    self scripts\zm\zm_modmenu::MM_Toggle("prmana", "Afterlife Infinite Mana", ::MM_PrisonInfManaLoop);
}

// The stock afterlife_reduce_mana() skips the drain when infinite_mana is set.
MM_PrisonInfManaLoop()
{
    self endon("disconnect");

    while(self scripts\zm\zm_modmenu::MM_IsOn("prmana"))
    {
        self.infinite_mana = 1;
        wait 0.5;
    }

    self.infinite_mana = 0;
}

// ---- Brutus ----

// Same notify the stock spawner (and its debug command) uses. The normal
// option respects the game's own Brutus limit; the other one ignores it.
MM_PrisonSpawnBrutus(ignoreLimit)
{
    if(!self MM_PrisonReady(true))
        return;

    if(!isDefined(level.brutus_spawners) || level.brutus_spawners.size < 1 || !isDefined(level.brutus_count))
    {
        self iprintln("^1Brutus is not available in this game mode.");
        return;
    }

    if(!ignoreLimit && level.brutus_count >= level.brutus_max_count)
    {
        self iprintln("^3Brutus limit reached (" + level.brutus_max_count + "). Use the ignore-limit option.");
        return;
    }

    level notify("spawn_brutus", 1);
    self iprintln("^2Brutus spawned.");
}

MM_PrisonKillBrutus()
{
    if(!self MM_PrisonReady(true))
        return;

    // MM_AliveZombies() deliberately skips bosses, so scan all enemies here.
    killed = 0;
    enemies = MM_AllEnemies();
    foreach(z in enemies)
    {
        if(!isDefined(z) || !isAlive(z))
            continue;
        if(!isDefined(z.is_brutus) || !z.is_brutus)
            continue;

        z doDamage(z.health + 666, z.origin);
        killed++;
    }

    if(killed > 0)
        self iprintln("^2Brutus killed: ^7" + killed);
    else
        self iprintln("^3No Brutus is alive right now.");
}

// ---- Golden Spork quest items ----

// Same weapon names and calls the stock spoon quest uses (zm_prison_spoon).
MM_PrisonGiveSpoon(spork)
{
    if(!self MM_PrisonReady(false))
        return;

    if(!flag_exists("spoon_obtained"))
    {
        self iprintln("^1The spoon quest is not available in this game mode.");
        return;
    }

    if(self hasWeapon("spork_zm_alcatraz"))
    {
        self iprintln("^3You already have the Golden Spork.");
        return;
    }

    if(spork)
    {
        self takeWeapon("spoon_zm_alcatraz");
        self takeWeapon("knife_zm_alcatraz");
        self giveWeapon("spork_zm_alcatraz");
        self set_player_melee_weapon("spork_zm_alcatraz");
        self setClientFieldToPlayer("spoon_visual_state", 3);
        self iprintln("^2Golden Spork given.");
        return;
    }

    if(self hasWeapon("spoon_zm_alcatraz"))
    {
        self iprintln("^3You already have the Spoon.");
        return;
    }

    self giveWeapon("spoon_zm_alcatraz");
    self set_player_melee_weapon("spoon_zm_alcatraz");
    self iprintln("^2Spoon given.");
}

// ---- Plane ----

// Finishes the plane craftable with the game's own complete_craftable(), the
// same end state as crafting every part: plane_built flag, VO and clientfield.
MM_PrisonBuildPlane()
{
    if(!self MM_PrisonReady(true))
        return;

    if(!flag_exists("plane_built"))
    {
        self iprintln("^1The plane is not available in this game mode.");
        return;
    }

    if(flag("plane_built"))
    {
        self iprintln("^3The plane is already built.");
        return;
    }

    found = false;
    if(isDefined(level.a_uts_craftables))
    {
        foreach(uts in level.a_uts_craftables)
        {
            if(isDefined(uts) && isDefined(uts.craftablestub) && isDefined(uts.craftablestub.name) && uts.craftablestub.name == "plane")
                found = true;
        }
    }

    completeFunc = MM_CraftablesFunc("complete_craftable");
    if(!found || !isDefined(completeFunc))
    {
        self iprintln("^1The plane craftable is not ready yet.");
        return;
    }

    [[ completeFunc ]]("plane");
    self iprintlnbold("^2Plane built.");
}

// The fuel cans use a separate stock craftable. Completing it calls Mob's
// native refuel callback instead of only setting a visual or quest flag.
MM_PrisonRefuelPlane()
{
    if(!self MM_PrisonReady(true))
        return;

    if(!flag_exists("plane_built") || !flag("plane_built"))
    {
        self iprintln("^1Build the plane first.");
        return;
    }

    found = false;
    if(isDefined(level.a_uts_craftables))
    {
        foreach(uts in level.a_uts_craftables)
        {
            if(isDefined(uts) && isDefined(uts.craftablestub) && isDefined(uts.craftablestub.name) && uts.craftablestub.name == "refuelable_plane")
                found = true;
        }
    }

    completeFunc = MM_CraftablesFunc("complete_craftable");
    if(!found || !isDefined(completeFunc))
    {
        self iprintln("^3The fuel craftable is already complete or not initialized.");
        return;
    }

    [[ completeFunc ]]("refuelable_plane");
    self iprintlnbold("^2Plane refueled.");
}

// ============================================================================
//  MAP-SPECIFIC TOOLS - TRANZIT / DIE RISE / BURIED
//  Map-only stock systems are resolved with getfunction() at runtime. This
//  keeps the shared menu script safe on maps that do not load those modules.
// ============================================================================

MM_MapToolName(mapName)
{
    switch(mapName)
    {
        case "zm_transit":  return "TranZit";
        case "zm_highrise": return "Die Rise";
        case "zm_buried":   return "Buried";
    }
    return mapName;
}

MM_MapToolReady(mapName, needHost)
{
    if(level.script != mapName)
    {
        self iprintln("^1This action is only available on " + MM_MapToolName(mapName) + ".");
        return false;
    }

    if(needHost && !self isHost())
    {
        self iprintln("^1This map action requires the host.");
        return false;
    }

    if(!flag("start_zombie_round_logic"))
    {
        self iprintln("^1Start the first round before using map tools.");
        return false;
    }

    return true;
}

MM_MapBuildableFunction(name)
{
    if(!isDefined(level.mm_map_buildable_funcs))
        level.mm_map_buildable_funcs = [];

    if(!isDefined(level.mm_map_buildable_funcs[name]))        level.mm_map_buildable_funcs[name] = getfunction("maps/mp/zombies/_zm_buildables", name);

    return level.mm_map_buildable_funcs[name];
}

// Mirrors Buried's stock buildbuildable() sequence: finish the selected
// station through the game, unregister it, and unspawn its loose pieces.
MM_MapBuildable(mapName, equipName)
{
    if(!self MM_MapToolReady(mapName, true))
        return;

    if(!isDefined(level.buildable_stubs) || level.buildable_stubs.size < 1)
    {
        self iprintln("^1No buildable stations are active in this area yet.");
        return;
    }

    finishFunc = MM_MapBuildableFunction("buildablestub_finish_build");
    removeFunc = MM_MapBuildableFunction("buildablestub_remove");
    unspawnFunc = MM_MapBuildableFunction("piece_unspawn");
    if(!isDefined(finishFunc) || !isDefined(removeFunc) || !isDefined(unspawnFunc))
    {
        self iprintln("^1The stock buildable system is not ready on this map.");
        return;
    }

    // The stock remove helper mutates the registry, so finish one station and
    // return immediately rather than continuing through the changed array.
    stubs = level.buildable_stubs;
    foreach(stub in stubs)
    {
        if(!isDefined(stub) || !isDefined(stub.equipname) || stub.equipname != equipName)
            continue;
        if(!isDefined(stub.buildablezone) || !isDefined(stub.buildablezone.pieces))
            continue;

        pieces = stub.buildablezone.pieces;
        stub [[ finishFunc ]](self);
        stub [[ removeFunc ]]();

        foreach(piece in pieces)
        {
            if(isDefined(piece))
                piece [[ unspawnFunc ]]();
        }

        if(isDefined(stub.model))
        {
            stub.model notsolid();
            stub.model show();
        }

        self iprintln("^2Completed buildable: ^7" + equipName);
        return;
    }

    self iprintln("^3Buildable not available here, already completed, or not enabled: ^7" + equipName);
}

// Fires the native switch trigger; do not set power_on manually, because the
// stock routines handle animations, power callbacks, doors and perks.
MM_MapPowerSwitch(mapName)
{
    if(!self MM_MapToolReady(mapName, true))
        return;

    if(flag_exists("power_on") && flag("power_on"))
    {
        self iprintln("^3Power is already on.");
        return;
    }

    if(mapName == "zm_transit" && isDefined(level.power_event_in_progress) && level.power_event_in_progress)
    {
        self iprintln("^3The TranZit reactor sequence is already running.");
        return;
    }

    triggerName = "use_elec_switch";
    if(mapName == "zm_transit")
        triggerName = "powerswitch_buildable_trigger_power";

    triggers = getEntArray(triggerName, "targetname");
    if(!isDefined(triggers) || triggers.size < 1 || !isDefined(triggers[0]))
    {
        if(mapName == "zm_transit")
            self iprintln("^1Build the Power Switch first, then use this option.");
        else
            self iprintln("^1The electric-switch trigger is not initialized yet.");
        return;
    }

    triggers[0] notify("trigger", self);
    if(mapName == "zm_transit")
        self iprintln("^2TranZit reactor started. The native power sequence takes about 30 seconds.");
    else
        self iprintln("^2Electric-switch activation requested.");
}

MM_BuriedOpenCell()
{
    if(!self MM_MapToolReady("zm_buried", true))
        return;

    cellDoor = getEnt("sloth_cell_door", "targetname");
    if(!isDefined(cellDoor))
    {
        self iprintln("^1Leroy's cell door is not present in this game mode.");
        return;
    }

    if(isDefined(level.cell_open) && level.cell_open)
    {
        self iprintln("^3Leroy's cell is already open.");
        return;
    }

    // Match Buried's own cell-open event path: notify the watcher and invoke
    // the map-installed jail animation callback.
    level notify("cell_open");
    if(isDefined(level.jail_open_door))
        [[ level.jail_open_door ]]();
    self iprintln("^2Leroy's cell opened.");
}

// Elevator floor arguments are zero-based in elevator_next_floor(); setting
// zero selects the first scripted stop (or the elevator's own start floor).
MM_HighriseSendElevators(floorIndex)
{
    if(!self MM_MapToolReady("zm_highrise", true))
        return;

    if(!isDefined(level.elevators))
    {
        self iprintln("^1Die Rise elevators are not initialized yet.");
        return;
    }

    keys = getarraykeys(level.elevators);
    sent = 0;
    foreach(key in keys)
    {
        elevator = level.elevators[key];
        if(!isDefined(elevator) || !isDefined(elevator.body))
            continue;

        elevator.body.force_starting_floor = floorIndex;
        elevator.body notify("forcego");
        sent++;
        wait 0.05;
    }

    if(sent > 0)
        self iprintln("^2Elevator dispatch sent: ^7" + sent);
    else
        self iprintln("^3No active elevators were found.");
}

// ============================================================================
//  ULTIMATE ZM MOD MENU - MAP-WIDE PARTS ESP
//  Included by zm_modmenu.gsc. Supports the stock Zombies craftable and
//  buildable registries used by Origins, Mob, TranZit, Die Rise and Buried.
// ============================================================================

MM_TogglePartsESP()
{
    self scripts\zm\zm_modmenu::MM_Toggle("partesp", "Parts ESP", ::MM_PartsESPLoop);
}

// Adds one live part model to the list (skips undefined models and duplicates).
// GSC arrays are passed by value, so the updated list is returned.
MM_PushPartModel(models, model)
{
    if(!isDefined(model) || !isDefined(model.origin))
        return models;

    foreach(existing in models)
    {
        if(existing == model)
            return models;
    }

    models[models.size] = model;
    return models;
}

// Return currently spawned part models from the stock game registries.
// The two stock systems store their world models in different places:
//   - _zm_craftables (Origins, Mob of the Dead):
//       level.zombie_include_craftables[].a_piecestubs[].piecespawn.model
//   - _zm_buildables (TranZit, Die Rise, Buried):
//       level.buildable_stubs[].buildablezone.pieces[].model
//       level.zombie_buildables[].buildablepieces[].generated_piece.model
// On the buildables maps, buildablepieces[] only holds the *template*, which
// has no model, so the spawned instances must be read from the places above.
MM_CollectMapPartModels()
{
    models = [];

    if(isDefined(level.zombie_include_craftables))
    {
        foreach(craftable in level.zombie_include_craftables)
        {
            if(!isDefined(craftable) || !isDefined(craftable.a_piecestubs))
                continue;

            foreach(piecestub in craftable.a_piecestubs)
            {
                if(!isDefined(piecestub) || !isDefined(piecestub.piecespawn))
                    continue;

                models = MM_PushPartModel(models, piecestub.piecespawn.model);
            }
        }
    }

    if(isDefined(level.buildable_stubs))
    {
        foreach(stub in level.buildable_stubs)
        {
            if(!isDefined(stub) || !isDefined(stub.buildablezone) || !isDefined(stub.buildablezone.pieces))
                continue;

            foreach(piece in stub.buildablezone.pieces)
            {
                if(!isDefined(piece))
                    continue;

                models = MM_PushPartModel(models, piece.model);
            }
        }
    }

    if(isDefined(level.zombie_buildables))
    {
        foreach(buildable in level.zombie_buildables)
        {
            if(!isDefined(buildable) || !isDefined(buildable.buildablepieces))
                continue;

            foreach(template in buildable.buildablepieces)
            {
                if(!isDefined(template))
                    continue;

                if(isDefined(template.generated_piece))
                    models = MM_PushPartModel(models, template.generated_piece.model);

                models = MM_PushPartModel(models, template.model);
            }
        }
    }

    return models;
}

MM_CreatePartESPDot()
{
    hud = newClientHudElem(self);
    hud.archived = 1;
    hud.foreground = false;
    hud.hideWhenInMenu = true;
    hud.sort = 1;
    hud.alpha = 0;
    hud.color = (0.0, 1.0, 1.0);
    hud setShader("white", 5, 5);
    hud setWaypoint(true, "white");
    return hud;
}

MM_PartsESPLoop()
{
    self endon("disconnect");

    // If the user switches the toggle off and on before cleanup runs, the
    // existing loop remains responsible for its HUD pool instead of spawning
    // a second one.
    if(isDefined(self.mmPartsESPActive) && self.mmPartsESPActive)
        return;

    self.mmPartsESPActive = true;
    maxDots = 24;
    huds = [];
    for(i = 0; i < maxDots; i++)
        huds[i] = self MM_CreatePartESPDot();

    self.mmPartsESPHuds = huds;

    for(;;)
    {
        if(!self scripts\zm\zm_modmenu::MM_IsOn("partesp"))
            break;

        parts = self MM_CollectMapPartModels();
        used = [];

        // Display the nearest 24 registered pieces, updating live as pieces
        // spawn, are picked up, are built, or are moved by map logic.
        for(slot = 0; slot < maxDots; slot++)
        {
            bestIdx = -1;
            bestDistance = 999999999;

            foreach(idx, model in parts)
            {
                if(isDefined(used[idx]))
                    continue;
                if(!isDefined(model) || !isDefined(model.origin))
                    continue;

                distanceNow = distancesquared(self.origin, model.origin);
                if(distanceNow < bestDistance)
                {
                    bestDistance = distanceNow;
                    bestIdx = idx;
                }
            }

            if(bestIdx < 0)
            {
                huds[slot].alpha = 0;
                continue;
            }

            used[bestIdx] = true;
            part = parts[bestIdx];
            if(!isDefined(part) || !isDefined(part.origin))
            {
                huds[slot].alpha = 0;
                continue;
            }

            markerPos = part.origin + (0, 0, 18);
            huds[slot].x = markerPos[0];
            huds[slot].y = markerPos[1];
            huds[slot].z = markerPos[2];
            huds[slot].alpha = 1;
        }

        wait 0.15;
    }

    foreach(hud in huds)
    {
        if(isDefined(hud))
            hud destroy();
    }

    self.mmPartsESPHuds = [];
    self.mmPartsESPActive = false;
}

// ============================================================================
//  V4 EXPANSION - BO2 FREE ROAM, MOVEMENT, MAP-AWARE REGISTRIES & ZOMBIE TOOLS
// ============================================================================

// Apply persistent menu state after every respawn. The stock ZM spawn path
// creates player_out_of_playable_area_monitor(); the delayed notify below
// stops that exact player's monitor when Free-Roam is enabled.
MM_ApplySpawnSettings()
{
    if(!isDefined(self.mmToggle))
        return;

    wait 0.10;

    self MM_EETrackerInit();

    if(self MM_IsOn("god"))
    {
        self enableInvulnerability();
        self MM_EnableGodBoundaryBypass();
    }
    else if(self MM_IsOn("noboundary"))
        self notify("stop_player_out_of_playable_area_monitor");

    if(self MM_IsOn("infsprint"))
        self setSprintDuration(9999);

    if(self MM_IsOn("thirdp"))
        self setClientThirdPerson(1);

    if(self MM_IsOn("speed"))
        self setMoveSpeedScale(2.0);

    if(self MM_IsOn("health"))
    {
        self setMaxHealth(99999);
        self.health = 99999;
    }
}

// The stock BO2 source checks kill_brush and player_volume entities from
// maps\mp\zombies\_zm::player_out_of_playable_area_monitor().
// Stopping that per-player monitor bypasses those map-boundary deaths.
ToggleNoDeathBarrier()
{
    on = self MM_Flip("noboundary", "Out-of-Map Death Monitor");
    if(on)
    {
        self notify("stop_player_out_of_playable_area_monitor");
        self iprintln("^2Out-of-map death monitor disabled for you.");
    }
    else
    {
        self thread maps\mp\zombies\_zm::player_out_of_playable_area_monitor();
        self iprintln("^1Out-of-map death monitor restored.");
    }
}

// Remember the most recent grounded point in an enabled player volume, then
// recover if the player falls far below that point.
ToggleVoidRecovery()
{
    self MM_Toggle("voidrecover", "Auto Void Recovery", ::MM_VoidRecoveryLoop);
}

MM_VoidRecoveryLoop()
{
    self endon("disconnect");
    self endon("mm_stop_voidrecover");

    safeOrigin = self.origin;

    for(;;)
    {
        if(self isOnGround() && self maps\mp\zombies\_zm::in_enabled_playable_area())
            safeOrigin = self.origin;

        if(self.origin[2] < safeOrigin[2] - 900)
        {
            self setOrigin(safeOrigin + (0, 0, 40));
            self setVelocity((0, 0, 0));
            self iprintln("^3Recovered from falling out of the map.");
            wait 0.75;
        }

        wait 0.10;
    }
}

MM_SetGravity(value)
{
    setDvar("g_gravity", value);
    self iprintln("Gravity set to " + value);
}

MM_SetMovementSpeed(scale)
{
    self.mmMoveScale = scale;
    self setMoveSpeedScale(scale);
    self iprintln("Movement speed set to " + scale + "x");
}

MM_SetNoclipSpeed(speed)
{
    self.mmNoclipSpeed = speed;
    self iprintln("Noclip speed set to " + speed);
}

ToggleInfiniteSprint()
{
    if(self MM_Toggle("infsprint", "Unlimited Sprint", ::MM_InfiniteSprintLoop))
        return;

    self setSprintDuration(4);
}

MM_InfiniteSprintLoop()
{
    self endon("disconnect");
    self endon("mm_stop_infsprint");

    for(;;)
    {
        self setSprintDuration(9999);
        wait 0.50;
    }
}

MM_TeleportForward(dist)
{
    pos = self MM_Forward(dist);
    self setOrigin(pos + (0, 0, 24));
    self setVelocity((0, 0, 0));
    self iprintln("Teleported forward " + dist);
}

MM_TeleportVertical(height)
{
    self setOrigin(self.origin + (0, 0, height));
    self setVelocity((0, 0, 0));
    self iprintln("Vertical teleport: " + height);
}

MM_SaveRoamPosition(slot)
{
    if(!isDefined(self.mmRoamPositions))
        self.mmRoamPositions = [];
    if(!isDefined(self.mmRoamAngles))
        self.mmRoamAngles = [];

    self.mmRoamPositions[slot] = self.origin;
    self.mmRoamAngles[slot] = self getPlayerAngles();
    self iprintln("^2Saved free-roam position " + (slot + 1));
}

MM_LoadRoamPosition(slot)
{
    if(!isDefined(self.mmRoamPositions) || !isDefined(self.mmRoamPositions[slot]))
    {
        self iprintln("^1That saved position is empty.");
        return;
    }

    self setOrigin(self.mmRoamPositions[slot] + (0, 0, 16));

    if(isDefined(self.mmRoamAngles) && isDefined(self.mmRoamAngles[slot]))
        self setPlayerAngles(self.mmRoamAngles[slot]);

    self setVelocity((0, 0, 0));
    self iprintln("^2Loaded free-roam position " + (slot + 1));
}

// Return to the nearest enabled player_volume on the current map.
MM_TeleportToNearestActiveVolume()
{
    volumes = getEntArray("player_volume", "script_noteworthy");
    if(!isDefined(volumes) || volumes.size < 1)
    {
        self iprintln("^1No player-volume markers exist on this map.");
        return;
    }

    best = undefined;
    bestDistance = 999999999;

    foreach(volume in volumes)
    {
        if(!isDefined(volume) || !isDefined(volume.origin) || !isDefined(volume.targetname))
            continue;

        if(!maps\mp\zombies\_zm_zonemgr::zone_is_enabled(volume.targetname))
            continue;

        d = distanceSquared(self.origin, volume.origin);
        if(d < bestDistance)
        {
            bestDistance = d;
            best = volume;
        }
    }

    if(!isDefined(best))
    {
        self iprintln("^1No enabled player-volume was found.");
        return;
    }

    self setOrigin(best.origin + (0, 0, 48));
    self setVelocity((0, 0, 0));
    self iprintln("^2Returned to the nearest active map area.");
}

// Build a menu from the actual weapon registries initialized by the current
// BO2 map. This makes the extra folder map-aware rather than assuming every
// weapon is loaded on every map.
MM_BuildRegisteredWeaponList()
{
    if(!isDefined(self.menuOpts["allguns"]))
        self.menuOpts["allguns"] = [];

    if(isDefined(level.zombie_weapons))
    {
        weaponKeys = getArrayKeys(level.zombie_weapons);
        foreach(weaponName in weaponKeys)
        {
            if(!isDefined(weaponName) || weaponName == "")
                continue;

            self MM_AddWeaponOpt("allguns", weaponName, weaponName);
        }
    }

    if(isDefined(level.zombie_weapons_upgraded))
    {
        upgradedKeys = getArrayKeys(level.zombie_weapons_upgraded);
        foreach(weaponName in upgradedKeys)
        {
            if(!isDefined(weaponName) || weaponName == "")
                continue;

            alreadyAdded = false;
            if(isDefined(self.menuOpts["allguns"]))
            {
                foreach(existing in self.menuOpts["allguns"])
                {
                    if(isDefined(existing.arg) && existing.arg == weaponName)
                    {
                        alreadyAdded = true;
                        break;
                    }
                }
            }

            if(!alreadyAdded)
                self MM_AddWeaponOpt("allguns", weaponName, weaponName);
        }
    }

    if(!isDefined(self.menuOpts["allguns"]) || self.menuOpts["allguns"].size < 1)
        self addMenuOpt("allguns", "No registered weapons found", ::MM_NoRegisteredEntry);
}

MM_BuildRegisteredPowerupList()
{
    count = 0;

    if(isDefined(level.zombie_powerups))
    {
        powerupKeys = getArrayKeys(level.zombie_powerups);
        foreach(powerupName in powerupKeys)
        {
            if(!isDefined(powerupName) || powerupName == "")
                continue;

            self addMenuOpt("powerups", "Spawn: " + powerupName, ::SpawnDrop, powerupName);
            count++;
        }
    }

    if(count < 1)
        self addMenuOpt("powerups", "No registered powerups found", ::MM_NoRegisteredEntry);
}

MM_NoRegisteredEntry()
{
    self iprintln("^1No registered entry is available on this map.");
}

// Find the closest standard zombie while leaving map-specific bosses alone.
MM_ClosestZombie()
{
    zombies = MM_AliveZombies();
    closest = undefined;
    bestDistance = 999999999;

    foreach(z in zombies)
    {
        if(!isDefined(z) || !isAlive(z))
            continue;

        d = distanceSquared(self.origin, z.origin);
        if(d < bestDistance)
        {
            bestDistance = d;
            closest = z;
        }
    }

    return closest;
}

MM_LeaveOneZombieAlive()
{
    zombies = MM_AliveZombies();
    if(zombies.size < 2)
    {
        self iprintln("^1There are not enough standard zombies to leave one alive.");
        return;
    }

    keep = self MM_ClosestZombie();
    killed = 0;

    foreach(z in zombies)
    {
        if(!isDefined(z) || z == keep || !isAlive(z))
            continue;

        z doDamage(z.health + 666, z.origin, self);
        killed++;
    }

    self iprintln("^2Left one standard zombie alive. Killed " + killed + ".");
}

MM_KillNearestZombie()
{
    z = self MM_ClosestZombie();
    if(!isDefined(z))
    {
        self iprintln("^1No standard zombie is available.");
        return;
    }

    z doDamage(z.health + 666, z.origin, self);
    self iprintln("^2Nearest zombie killed.");
}

MM_TeleportNearestZombie()
{
    z = self MM_ClosestZombie();
    if(!isDefined(z))
    {
        self iprintln("^1No standard zombie is available.");
        return;
    }

    z forceTeleport(self MM_Forward(100) + (0, 0, 24));
    self iprintln("^2Nearest zombie teleported to you.");
}

MM_TeleportNearestZombieToCrosshair()
{
    z = self MM_ClosestZombie();
    if(!isDefined(z))
    {
        self iprintln("^1No standard zombie is available.");
        return;
    }

    z forceTeleport(self MM_CrosshairPos() + (0, 0, 24));
    self iprintln("^2Nearest zombie teleported to crosshair.");
}

// ============================================================================
//  ZOMBIE EXPANSION - SPAWNING, AI, HEALTH, BOSS FILTERS
// ============================================================================

// Use the same spawn_zombie() entry point and registered spawn callbacks as
// stock BO2. The standard path mirrors _zm.gsc; special types use the stock
// dog/leaper spawner registries, so their native initialization still runs.
MM_SpawnZombieBatch(kind, requested)
{
    if(!isDefined(requested) || requested < 1)
        return;

    spawners = [];
    if(kind == "normal")
    {
        if(!isDefined(level.zombie_spawners) || level.zombie_spawners.size < 1
            || !isDefined(level.zombie_spawn_locations) || level.zombie_spawn_locations.size < 1)
        {
            self iprintln("^1Regular zombie spawn registry is not ready on this map.");
            return;
        }
        spawners = level.zombie_spawners;
    }
    else if(kind == "dog")
    {
        if(!isDefined(level.dog_spawners) || level.dog_spawners.size < 1)
        {
            self iprintln("^1Hellhounds are not registered on this map.");
            return;
        }
        spawners = level.dog_spawners;
    }
    else if(kind == "leaper")
    {
        if(!isDefined(level.leaper_spawners) || level.leaper_spawners.size < 1)
        {
            self iprintln("^1Denizens / Leapers are not registered on this map.");
            return;
        }
        spawners = level.leaper_spawners;
    }
    else
        return;

    // Respect the stock AI limit instead of flooding the server with actors.
    limit = 24;
    if(isDefined(level.zombie_ai_limit) && level.zombie_ai_limit > 0)
        limit = level.zombie_ai_limit;

    active = MM_AllEnemies().size;
    capacity = limit - active;
    if(capacity < 1)
    {
        self iprintln("^3Zombie AI limit reached (" + limit + ").");
        return;
    }

    count = requested;
    if(count > capacity)
        count = capacity;

    spawned = 0;
    for(i = 0; i < count; i++)
    {
        if(kind == "normal")
        {
            spawner = spawners[randomInt(spawners.size)];
            spawnPoint = level.zombie_spawn_locations[randomInt(level.zombie_spawn_locations.size)];
            ai = spawn_zombie(spawner, spawner.targetname, spawnPoint);
        }
        else
        {
            spawner = spawners[randomInt(spawners.size)];
            ai = spawn_zombie(spawner);
        }

        if(isDefined(ai))
            spawned++;
        wait 0.05;
    }

    self iprintln("^2Spawned " + spawned + " " + kind + " enemies. ^7(Available AI slots: " + (capacity - spawned) + ")");
}

MM_ShowZombieSpawnTypes()
{
    msg = "Regular: ";
    if(isDefined(level.zombie_spawners) && level.zombie_spawners.size > 0)
        msg += "YES";
    else
        msg += "NO";

    msg += " | Hellhounds: ";
    if(isDefined(level.dog_spawners) && level.dog_spawners.size > 0)
        msg += "YES";
    else
        msg += "NO";

    msg += " | Leapers: ";
    if(isDefined(level.leaper_spawners) && level.leaper_spawners.size > 0)
        msg += "YES";
    else
        msg += "NO";

    self iprintln(msg);
}

MM_ToggleZombiePacify()
{
    on = self MM_Flip("zpacify", "Regular Zombie AI");
    if(on)
    {
        level.mmZombiePacifyEnabled = true;
        if(!isDefined(level.mmZombiePacifyRunning) || !level.mmZombiePacifyRunning)
            level thread MM_ZombiePacifyLoop();
        self iprintln("^2Non-boss zombie AI disabled.");
    }
    else
    {
        level.mmZombiePacifyEnabled = false;
        self iprintln("^1Regular zombie AI restore requested.");
    }
}

MM_ZombiePacifyLoop()
{
    level endon("end_game");
    level.mmZombiePacifyRunning = true;

    while(isDefined(level.mmZombiePacifyEnabled) && level.mmZombiePacifyEnabled)
    {
        zombies = MM_AliveZombies();
        foreach(z in zombies)
        {
            if(!isDefined(z) || !isAlive(z) || MM_IsBoss(z))
                continue;

            // Preserve each actor's original ignoreall state, including dogs
            // and map-specific AI, instead of forcing every enemy to false.
            if(!isDefined(z.mmPacifyOriginalIgnore))
            {
                if(isDefined(z.ignoreall))
                    z.mmPacifyOriginalIgnore = z.ignoreall;
                else
                    z.mmPacifyOriginalIgnore = false;
            }
            z.ignoreall = true;
        }
        wait 0.2;
    }

    zombies = MM_AliveZombies();
    foreach(z in zombies)
    {
        if(!isDefined(z) || !isDefined(z.mmPacifyOriginalIgnore))
            continue;
        z.ignoreall = z.mmPacifyOriginalIgnore;
        z.mmPacifyOriginalIgnore = undefined;
    }

    level.mmZombiePacifyRunning = false;
}
MM_SetZombieHealth(amount)
{
    zombies = MM_AliveZombies();
    changed = 0;
    foreach(z in zombies)
    {
        if(!isDefined(z) || !isAlive(z) || MM_IsBoss(z))
            continue;
        z.maxhealth = amount;
        z.health = amount;
        changed++;
    }
    self iprintln("^2Set " + changed + " regular zombies to " + amount + " HP. ^7(Current enemies only.)");
}

MM_IsDog(z)
{
    if(!isDefined(z))
        return false;
    return (isDefined(z.animname) && z.animname == "zombie_dog")
        || (isDefined(z.targetname) && z.targetname == "zombie_dog");
}

MM_IsLeaper(z)
{
    if(!isDefined(z))
        return false;
    return (isDefined(z.is_leaper) && z.is_leaper)
        || (isDefined(z.animname) && z.animname == "leaper_zombie");
}

MM_KillZombieGroup(kind)
{
    enemies = MM_AllEnemies();
    killed = 0;
    foreach(z in enemies)
    {
        if(!isDefined(z) || !isAlive(z))
            continue;

        match = false;
        if(kind == "boss")
            match = MM_IsBoss(z);
        else if(kind == "dog")
            match = MM_IsDog(z);
        else if(kind == "leaper")
            match = MM_IsLeaper(z);
        else if(kind == "special")
            match = MM_IsBoss(z) || MM_IsDog(z) || MM_IsLeaper(z);

        if(!match)
            continue;

        z doDamage(z.health + 99999, z.origin, self);
        killed++;
    }

    self iprintln("^2Killed " + killed + " enemies in group: " + kind);
}

MM_ShowZombieGroupCounts()
{
    enemies = MM_AllEnemies();
    bosses = 0;
    dogs = 0;
    leapers = 0;
    foreach(z in enemies)
    {
        if(!isDefined(z) || !isAlive(z))
            continue;
        if(MM_IsBoss(z))
            bosses++;
        else if(MM_IsDog(z))
            dogs++;
        else if(MM_IsLeaper(z))
            leapers++;
    }

    self iprintln("^3BOSSES: ^7" + bosses + "  ^3HELLHOUNDS: ^7" + dogs + "  ^3LEAPERS: ^7" + leapers);
}

// ============================================================================
//  END V4 EXPANSION
// ============================================================================