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
                piece = maps\mp\zombies\_zm_craftables::generate_piece(piecestub);
                piecestub.piecespawn = piece;
            }

            if(isDefined(piece) && isDefined(piece.model) && isDefined(piece.unitrigger))
            {
                self maps\mp\zombies\_zm_craftables::player_take_piece(piece);
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
    self MM_Toggle("origcollect", "Auto-Collect Shared Parts", ::MM_OriginsAutoCollectLoop);
}

MM_OriginsAutoCollectLoop()
{
    self endon("disconnect");

    while(self MM_IsOn("origcollect"))
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

    self MM_Toggle("nomud", "Ignore Mud Slowdown", ::MM_OriginsNoMudSlowLoop);
}

// The stock Origins movement monitor sets self.is_player_slowed and applies
// 0.6 (or 0.7 with Stamin-Up) while touching the mud. Restore normal speed for
// this player only; do not alter the map's shared slow-area entities.
MM_OriginsNoMudSlowLoop()
{
    self endon("disconnect");

    while(self MM_IsOn("nomud"))
    {
        if(isDefined(self.is_player_slowed) && self.is_player_slowed)
        {
            self.n_move_scale = 1.0;
            self setMoveSpeedScale(1.0);
        }
        wait 0.05;
    }
}
