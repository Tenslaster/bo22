// ============================================================================
//  ULTIMATE ZM MOD MENU  -  Plutonium T6 (Black Ops II Zombies)  -  v3.6
//  Install: %localappdata%\Plutonium\storage\t6\scripts\zm\zm_modmenu.gsc
//
//  Controls (menu closed):  AIM + MELEE ............ open menu
//  Controls (menu open)  :  Action Slot 1 / 2 ...... scroll up / down
//                           JUMP .................... select
//                           MELEE ................... back / close
//  Spectator (any time)  :  G (bind g "+actionslot 3" once) enter / leave
//                           (also in Personal Mods)
//
//  Maps: TranZit / Nuketown / Die Rise / Mob of the Dead / Buried / Origins
//  Every weapon / drop / perk entry is checked against what the current map
//  has loaded, so nothing is given that the map does not know.
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

    if(self isHost())
        self.hasMenu = true;

    firstSpawn = true;
    for(;;)
    {
        if(isDefined(self.hasMenu) && self.hasMenu)
        {
            self MM_GrantMenu();
            if(firstSpawn)
            {
                self iprintlnbold("^2ULTIMATE ZM MENU LOADED");
                self iprintln("^7Aim + Melee: open | Slot 1/2: scroll | Jump: select | Melee: back | F6: bot mode | F7: teleport bots | G: spectator");
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

    self.menuRows = [];
    for(i = 0; i < 9; i++)
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

MM_SpectatorKeyListener()
{
    self endon("disconnect");
    self endon("stop_menu_input");

    for(;;)
    {
        self waittill("mm_spec");

        // Slot 3 is not used by the menu, but ignore it while the menu is open.
        if(isDefined(self.menuOpen) && self.menuOpen)
            continue;

        if(self MM_Gate("spec", 500))
            self thread ToggleSpectator();
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

    // Spectator hotkey (bind g "+actionslot 3" in the console once).
    self notifyOnPlayerCommand("mm_spec", "+actionslot 3");
    self thread MM_SpectatorKeyListener();

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
        case "personal":       return "PERSONAL MODS";
        case "weapons":        return "WEAPON MODS";
        case "mapweapons":     return "MAP WEAPONS";
        case "guns":           return "MORE GUNS";
        case "lobby":          return "SPAWNS & LOBBY";
        case "zombies":        return "ZOMBIE MANIPULATION";
        case "vision":         return "AIMBOT & ESP";
        case "origins":        return "ORIGINS TOOLS";
        case "prison":         return "MOB OF THE DEAD TOOLS";
        case "transit":        return "TRANZIT TOOLS";
        case "highrise":       return "DIE RISE TOOLS";
        case "buried":         return "BURIED TOOLS";
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

    maxRows = 9;
    first = 0;
    if(total > maxRows)
    {
        first = self.menuCursor - 4;
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
    self addSubMenu("main", "Personal Mods", "personal");
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
    if(self isHost())
        self addSubMenu("main", "Players Menu", "players");

    // --- PERSONAL ---
    self addToggleOpt("personal", "God Mode", ::ToggleGodMode, "god");
    self addToggleOpt("personal", "Noclip", ::ToggleNoclip, "noclip");
    self addToggleOpt("personal", "Spectator Mode (Free Cam)", ::ToggleSpectator, "spectate");
    self addMenuOpt("personal", "Leave Spectator At Camera", ::SpectatorExitHere);
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
    self addMenuOpt("personal", "+100,000 Points", ::GivePoints);
    self addToggleOpt("personal", "Infinite Points", ::ToggleInfPoints, "infpoints");
    self addMenuOpt("personal", "Save Position", ::SavePosition);
    self addMenuOpt("personal", "Load Position", ::LoadPosition);
    self addMenuOpt("personal", "Teleport To Crosshair", ::TeleportToCrosshair);
    self addMenuOpt("personal", "Suicide", ::DoSuicide);

    // --- WEAPONS ---
    self addToggleOpt("weapons", "Infinite Ammo", ::ToggleInfAmmo, "infammo");
    self addMenuOpt("weapons", "Pack-A-Punch Current", ::PapCurrentWeapon);
    self addMenuOpt("weapons", "Pack-A-Punch ALL Guns", ::PapAllWeapons);
    self addMenuOpt("weapons", "Max Ammo Current", ::FillCurrentAmmo);
    self addMenuOpt("weapons", "Max Ammo ALL", ::FillAllAmmo);
    self addSubMenu("weapons", "More Guns (PaP)", "guns");
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
    self addMenuOpt("weapons", "Give All Perks", ::GiveAllPerks);
    self addMenuOpt("weapons", "Remove All Perks", ::RemoveAllPerks);
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
    self addMenuOpt("zombies", "Kill All Zombies", ::KillAllZombies);
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
        self addMenuOpt("origins", "Collect All Shared Parts", ::MM_OriginsCollectAllSharedParts);
        self addToggleOpt("origins", "Auto-Collect Shared Parts", ::MM_OriginsToggleAutoCollect, "origcollect");
        self addMenuOpt("origins", "Force All Four Staff Upgrades", ::MM_OriginsUpgradeAllStaffs);
        self addMenuOpt("origins", "Turn On All Generators (Pack-a-Punch)", ::MM_OriginsTurnOnAllGenerators);
        self addToggleOpt("origins", "Ignore Mud Slowdown", ::MM_OriginsToggleNoMudSlow, "nomud");
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
        self addMenuOpt("player_actions", "Give All Perks", ::ActionGivePerks);
        self addMenuOpt("player_actions", "Give +100k Points", ::ActionPoints);
        self addMenuOpt("player_actions", "Revive", ::ActionRevive);
        self addMenuOpt("player_actions", "Teleport To Them", ::ActionTeleportTo);
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
    p MM_SpectatorExit(true);

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
    for(;;)
    {
        self enableInvulnerability();   // re-applied because revives clear it
        wait 0.5;
    }
}

ToggleNoclip()
{
    if(self MM_Toggle("noclip", "Noclip", ::NoclipLoop))
        return;
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
    self iprintln("Noclip: Attack = forward | Frag = up | Tactical = down");

    for(;;)
    {
        if(self attackButtonPressed())
            obj.origin = obj.origin + (anglesToForward(self getPlayerAngles()) * 40);
        if(self fragButtonPressed())
            obj.origin = obj.origin + (0, 0, 25);
        if(self secondaryOffhandButtonPressed())
            obj.origin = obj.origin - (0, 0, 25);
        wait 0.05;
    }
}

MM_NoclipCleanup(obj)
{
    self waittill_any("disconnect", "mm_stop_noclip");
    if(isDefined(obj))
        obj delete();
}

// ---- Spectator (free cam) ----
// Hides you, makes you untouchable and detaches the camera so you can fly
// anywhere. Leaving puts you back where you started (or at the camera).
// Fly with the move stick, Jump = up, Frag = down, Attack = fast.

ToggleSpectator()
{
    if(self MM_IsOn("spectate"))
        self MM_SpectatorExit(false);
    else
        self MM_SpectatorEnter();
}

SpectatorExitHere()
{
    if(!self MM_IsOn("spectate"))
    {
        self iprintln("^3You are not spectating.");
        return;
    }
    self MM_SpectatorExit(true);
}

MM_SpectatorEnter()
{
    if(self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
    {
        self iprintln("^1Cannot spectate while downed.");
        return;
    }

    // Noclip and spectator both link the player, so only one at a time.
    if(self MM_IsOn("noclip"))
    {
        self.mmToggle["noclip"] = false;
        self notify("mm_stop_noclip");
        self unlink();
    }

    self.mmToggle["spectate"] = true;
    self.mmSpecOrigin = self.origin;
    self.mmSpecAngles = self getPlayerAngles();
    self thread SpectatorLoop();
    self iprintln("Spectator ^2ON ^7- Stick: fly | Jump: up | Frag: down | Attack: fast | G: leave");
}

SpectatorLoop()
{
    self endon("disconnect");
    self endon("mm_stop_spectate");

    obj = spawn("script_origin", self.origin);
    obj.angles = self.angles;
    self playerLinkTo(obj);
    self thread MM_SpectatorCleanup(obj);

    self hide();
    self.ignoreme = true;
    self enableInvulnerability();
    self disableWeapons();

    for(;;)
    {
        wait 0.05;

        // Hold still while the menu is open (Jump selects entries there).
        if(isDefined(self.menuOpen) && self.menuOpen)
            continue;

        speed = 18;
        if(self attackButtonPressed())
            speed = 50;

        ang = self getPlayerAngles();
        mv = self getNormalizedMovement();
        move = (anglesToForward(ang) * (mv[0] * speed)) + (anglesToRight(ang) * (mv[1] * speed));

        if(self jumpButtonPressed())
            move = move + (0, 0, speed);
        if(self fragButtonPressed())
            move = move - (0, 0, speed);

        obj.origin = obj.origin + move;
    }
}

MM_SpectatorCleanup(obj)
{
    self waittill_any("disconnect", "mm_stop_spectate");
    if(isDefined(obj))
        obj delete();
}

MM_SpectatorExit(atCamera)
{
    if(!self MM_IsOn("spectate"))
        return;

    self.mmToggle["spectate"] = false;
    self unlink();
    self notify("mm_stop_spectate");

    if(!atCamera && isDefined(self.mmSpecOrigin))
    {
        self setOrigin(self.mmSpecOrigin);
        self setPlayerAngles(self.mmSpecAngles);
    }

    // Restore anything the other toggles control.
    if(!self MM_IsOn("invis"))
        self show();
    self.ignoreme = self MM_IsOn("ignore");
    if(!self MM_IsOn("god"))
        self disableInvulnerability();
    self enableWeapons();

    self iprintln("Spectator ^1OFF");
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

// Gives every perk that has a machine on the current map.
MM_GivePerks()
{
    machines = getEntArray("zombie_vending", "targetname");
    foreach(m in machines)
    {
        perk = m.script_noteworthy;
        if(!isDefined(perk))
            continue;
        if(self hasPerk(perk))
            continue;
        self maps\mp\zombies\_zm_perks::give_perk(perk, false);
        wait 0.25;
    }
}

GiveAllPerks()
{
    self MM_GivePerks();
    self iprintln("All perks ^2given");
}

RemoveAllPerks()
{
    machines = getEntArray("zombie_vending", "targetname");
    foreach(m in machines)
    {
        perk = m.script_noteworthy;
        if(isDefined(perk) && self hasPerk(perk))
            self notify(perk + "_stop");
    }
    self iprintln("Perks removed");
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

    if(!isDefined(level.mm_map_buildable_funcs[name]))
        level.mm_map_buildable_funcs[name] = getfunction("maps/mp/zombies/_zm_buildables", name);

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
