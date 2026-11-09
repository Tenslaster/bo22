#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;

// -----------------------------------------------------------------------------
// Buried map-specific bot logic (zm_buried).
// Shared bot systems and generic quest helpers remain in zm_bo2_bots.gsc.
// Edit this file for behavior that belongs only to this map.
// -----------------------------------------------------------------------------

bot_quest_buried()
{
    stage = level._cur_stage_name;

    // Tower Snare: activate the three signs belonging to the already-built
    // tower route. The stock damage watcher accepts Galvaknuckles (tazer
    // knuckles) or a Bowie Knife and owns the sq_sign_damaged completion event.
    if(isdefined(stage) && stage == "ts")
    {
        // Match the route selected by the built tower. Maxis wins if both
        // flags are present because the stock final completion checks Maxis first.
        wanted_route = 1;
        if(!flag("sq_is_max_tower_built") && flag("sq_is_ric_tower_built"))
            wanted_route = 0;

        melee_name = undefined;
        current_melee = self get_player_melee_weapon();
        if(self hasweapon("tazer_knuckles_zm"))
        {
            melee_name = "tazer_knuckles_zm";
            self set_player_melee_weapon(melee_name);
        }
        else if(self hasweapon("bowie_knife_zm"))
        {
            melee_name = "bowie_knife_zm";
            self set_player_melee_weapon(melee_name);
        }
        else if(self hasweapon("knife_ballistic_bowie_zm"))
        {
            melee_name = "knife_ballistic_bowie_zm";
            self set_player_melee_weapon(melee_name);
        }
        else if(self hasweapon("knife_ballistic_bowie_upgraded_zm"))
        {
            melee_name = "knife_ballistic_bowie_upgraded_zm";
            self set_player_melee_weapon(melee_name);
        }
        else if(isdefined(current_melee) && (current_melee == "tazer_knuckles_zm" ||
                current_melee == "knife_ballistic_bowie_zm" ||
                current_melee == "knife_ballistic_bowie_upgraded_zm" ||
                current_melee == "bowie_knife_zm"))
            melee_name = current_melee;

        if(isdefined(melee_name))
        {
            signs = getentarray("sq_tunnel_sign", "targetname");
            foreach(sign in signs)
            {
                if(!isdefined(sign) || !isdefined(sign.origin) ||
                   (isdefined(sign.ts_sign_activated) && sign.ts_sign_activated))
                    continue;

                correct_sign = 0;
                if(wanted_route && is_true(sign.is_max_sign))
                    correct_sign = 1;
                else if(!wanted_route && is_true(sign.is_ric_sign))
                    correct_sign = 1;

                if(!correct_sign)
                    continue;

                if(distancesquared(self.origin, sign.origin) > 72 * 72)
                {
                    self scripts\zm\zm_bo2_bots::bot_quest_move_to(sign.origin, "bot_buried_tower_snare", 64, 7000);
                    return;
                }

                self.bot.is_objective_using = 1;
                self set_player_melee_weapon(melee_name);
                self lookat(sign.origin + (0, 0, 24));
                for(hit = 0; hit < 3 && !is_true(sign.ts_sign_activated); hit++)
                {
                    self pressmelee();
                    wait 0.45;
                }
                self clearlookat();
                self.bot.is_objective_using = undefined;
                return;
            }
        }
        return;
    }

    // Mined Games' amplifier stage: find all stock amplifier triggers, then
    // charge/break the amplifiers with the map-required Slow Gun.
    if(isdefined(stage) && stage == "mta")
    {
        amplifiers = getentarray("sq_amplifier", "targetname");
        if(isdefined(amplifiers))
        {
            foreach(amp in amplifiers)
            {
                if(!isdefined(amp) || !isdefined(amp.origin))
                    continue;

                if(isdefined(amp.amplifier_state) && amp.amplifier_state == "filled")
                    continue;

                if(isdefined(amp.amplifier_state) && amp.amplifier_state == "broken")
                    continue;

                if(distancesquared(self.origin, amp.origin) > 16384)
                {
                    self scripts\zm\zm_bo2_bots::bot_quest_move_to(amp.origin, "bot_buried_amp_find", 96, 6000);
                    return;
                }

                slowgun = undefined;
                if(self hasweapon("slowgun_zm"))
                    slowgun = "slowgun_zm";
                else if(self hasweapon("slowgun_upgraded_zm"))
                    slowgun = "slowgun_upgraded_zm";

                if(isdefined(slowgun))
                {
                    self.bot.is_objective_using = 1;
                    self switchtoweaponimmediate(slowgun);
                    deadline = gettime() + 5000;
                    while(isdefined(amp) && gettime() < deadline &&
                          (!isdefined(amp.amplifier_state) || amp.amplifier_state == "base"))
                    {
                        self lookat(amp.origin);
                        self pressattackbutton(0.1);
                        wait 0.15;
                    }
                    self.bot.is_objective_using = undefined;
                    self clearlookat();
                    return;
                }
            }
        }
        return;
    }

    // Ghost lantern: the map attaches its pickup trigger to the moving lantern.
    if(isdefined(level.vh_lantern) && isdefined(level.vh_lantern.t_pickup))
    {
        pickup = level.vh_lantern.t_pickup;
        if(isdefined(pickup.origin))
        {
            self scripts\zm\zm_bo2_bots::bot_quest_use_target(pickup, "bot_buried_ghost_lantern", 42, 4);
            return;
        }
    }

    // Fill the built oil lamp by fighting within the map's own lamp generator
    // area. Kill credit and charge counters are still handled by the stock code.
    if(isdefined(level.sq_lamp_generator_unitrig) && isdefined(level.sq_lamp_generator_unitrig.realorigin) &&
       !flag("ftl_lantern_charged"))
    {
        self scripts\zm\zm_bo2_bots::bot_quest_move_to(level.sq_lamp_generator_unitrig.realorigin, "bot_buried_lantern_defend", 180, 5000);
        return;
    }

    // Maxis route: save the unfinished Wisp state with a real Time Bomb while
    // the CTW stage is still active. Later, after the stock quest reaches TPO,
    // detonate the saved bomb; the stock restore callback sets
    // sq_wisp_saved_with_time_bomb and restarts the Wisp sequence.
    if(isdefined(stage) && stage == "ctw" && flag("sq_is_max_tower_built") &&
       !flag("sq_wisp_success") && !is_true(level.bot_buried_wisp_timebomb_saved) &&
       self hasweapon("time_bomb_zm"))
    {
        if(!isdefined(level.bot_buried_wisp_timebomb_owner) ||
           !isalive(level.bot_buried_wisp_timebomb_owner))
        {
            level.bot_buried_wisp_timebomb_owner = self;
            wisp_for_save = getent("sq_wisp", "targetname");
            if(isdefined(wisp_for_save) && isdefined(wisp_for_save.origin))
                self scripts\zm\zm_bo2_bots::bot_quest_move_to(wisp_for_save.origin, "bot_buried_wisp_timebomb_save", 120, 7000);
            self.bot.is_objective_using = 1;
            self switchtoweaponimmediate("time_bomb_zm");
            wait 0.25;
            self forcegrenadethrow();
            wait 0.9;
            self.bot.is_objective_using = undefined;
            if(isdefined(level.time_bomb_save_data) && isdefined(level.time_bomb_save_data.sq_data) &&
               isdefined(level.time_bomb_save_data.sq_data.wisp_stage_complete) &&
               !level.time_bomb_save_data.sq_data.wisp_stage_complete)
                level.bot_buried_wisp_timebomb_saved = 1;
            level.bot_buried_wisp_timebomb_owner = undefined;
        }
        return;
    }

    if(isdefined(stage) && stage == "tpo")
    {
        // Richtofen route: put the Time Bomb inside the map's valid volume.
        // Its native script captures the stage and creates a detonator.
        if(flag("sq_is_ric_tower_built") && !flag("sq_tpo_time_bomb_in_valid_location") &&
           self hasweapon("time_bomb_zm"))
        {
            timebomb_volume = getent("sq_tpo_timebomb_volume", "targetname");
            if(isdefined(timebomb_volume) && isdefined(timebomb_volume.origin))
            {
                bomb_model = undefined;
                if(isdefined(level.time_bomb_save_data) && isdefined(level.time_bomb_save_data.time_bomb_model))
                    bomb_model = level.time_bomb_save_data.time_bomb_model;

                if(!isdefined(bomb_model) || !isdefined(bomb_model.origin) || !bomb_model istouching(timebomb_volume))
                {
                    if(self scripts\zm\zm_bo2_bots::bot_quest_move_to(timebomb_volume.origin, "bot_buried_timebomb", 96, 8000))
                    {
                        self.bot.is_objective_using = 1;
                        self switchtoweaponimmediate("time_bomb_zm");
                        wait 0.25;
                        self forcegrenadethrow();
                        wait 0.75;
                        self.bot.is_objective_using = undefined;
                    }
                }
            }
            return;
        }

        // All four player entities must remain in the time-bomb volume at the
        // instant of detonation. Bots walk there; the local non-bot host is
        // moved there temporarily and restored as soon as stock logic ends
        // its all-player check. No quest flag is written by this helper.
        if(flag("sq_is_ric_tower_built") && flag("sq_tpo_time_bomb_in_valid_location"))
        {
            timebomb_volume = getent("sq_tpo_timebomb_volume", "targetname");
            if(isdefined(timebomb_volume) && isdefined(timebomb_volume.origin))
            {
                players_for_bomb = get_players();
                player_index = 0;
                offsets = array(( -18, -18, 0 ), ( 18, -18, 0 ), ( -18, 18, 0 ), ( 18, 18, 0 ));
                for(player_index = 0; player_index < players_for_bomb.size; player_index++)
                {
                    p_bomb = players_for_bomb[player_index];
                    if(!isdefined(p_bomb) || isdefined(p_bomb.pers["isbot"]))
                        continue;
                    if(!isdefined(level.bot_buried_tpo_host_player))
                    {
                        level.bot_buried_tpo_host_player = p_bomb;
                        level.bot_buried_tpo_host_origin = p_bomb.origin;
                        level.bot_buried_tpo_host_angles = p_bomb.angles;
                        p_bomb setorigin(timebomb_volume.origin + offsets[player_index]);
                        level thread bot_buried_tpo_restore_host();
                    }
                }

                self scripts\zm\zm_bo2_bots::bot_quest_move_to(timebomb_volume.origin, "bot_buried_tpo_all_players", 110, 7000);
                if(flag("sq_tpo_players_in_position_for_time_warp") && self hasweapon("time_bomb_detonator_zm") &&
                   !is_true(level.bot_buried_tpo_detonate_started))
                {
                    level.bot_buried_tpo_detonate_started = 1;
                    self notify("detonate");
                }
            }
            return;
        }

        // Maxis route: detonate only the previously saved, incomplete-Wisp
        // snapshot. The stock restore callback sets the actual quest flag.
        if(flag("sq_is_max_tower_built") && !flag("sq_wisp_saved_with_time_bomb") &&
           isdefined(level.time_bomb_save_data) && isdefined(level.time_bomb_save_data.sq_data) &&
           isdefined(level.time_bomb_save_data.sq_data.wisp_stage_complete) &&
           !level.time_bomb_save_data.sq_data.wisp_stage_complete &&
           self hasweapon("time_bomb_detonator_zm") && !is_true(level.bot_buried_wisp_detonate_started))
        {
            level.bot_buried_wisp_detonate_started = 1;
            self notify("detonate");
            return;
        }

        // Richtofen's timed 60-second corpse search: every spawned corpse has
        // its own native hold-use unitrigger. Search distinct bodies until the
        // stock callback awards the switch piece and sets sq_tpo_found_item.
        if(flag("sq_is_ric_tower_built") && !flag("sq_tpo_found_item"))
        {
            corpses = getentarray("sq_tpo_corpse_model", "targetname");
            foreach(corpse in corpses)
            {
                if(!isdefined(corpse) || !isdefined(corpse.origin) || !isdefined(corpse.unitrigger) ||
                   !isdefined(corpse.unitrigger.origin) || is_true(corpse.bot_auto_tpo_searched))
                    continue;
                if(isdefined(corpse.bot_auto_tpo_owner) && corpse.bot_auto_tpo_owner != self &&
                   isdefined(corpse.bot_auto_tpo_until) && gettime() < corpse.bot_auto_tpo_until &&
                   isalive(corpse.bot_auto_tpo_owner))
                    continue;

                corpse.bot_auto_tpo_owner = self;
                corpse.bot_auto_tpo_until = gettime() + 6000;
                if(self scripts\zm\zm_bo2_bots::bot_quest_hold_use_target(corpse.unitrigger, "bot_buried_tpo_search", 42, 1.7) &&
                   !flag("sq_tpo_found_item"))
                    corpse.bot_auto_tpo_searched = 1;
                corpse.bot_auto_tpo_owner = undefined;
                corpse.bot_auto_tpo_until = 0;
                return;
            }
        }
    }

    // Follow the live Wisp during the guillotine stage so that the normal
    // combat worker can kill nearby powered zombies for the stock quest logic.
    if(isdefined(stage) && stage == "ctw" && !flag("sq_wisp_success") &&
       !flag("sq_wisp_failed"))
    {
        wisp = getent("sq_wisp", "targetname");
        if(isdefined(wisp) && isdefined(wisp.origin))
        {
            if(distancesquared(self.origin, wisp.origin) > 65536)
                self scripts\zm\zm_bo2_bots::bot_quest_move_to(wisp.origin, "bot_buried_wisp_follow", 128, 5000);
            return;
        }
        return;
    }

    // Interact with the live Maxis light-board button sequence or the
    // Richtofen maze levers in the exact order exposed by the stock script.
    if(isdefined(stage) && stage == "ip" && !flag("sq_ip_puzzle_complete"))
    {
        if(flag("sq_is_max_tower_built"))
        {
            if(!isdefined(level.str_sq_bp_active_light) || level.str_sq_bp_active_light == "")
            {
                board = getent("sq_bp_board", "targetname");
                if(isdefined(board) && isdefined(board.origin))
                    self scripts\zm\zm_bo2_bots::bot_quest_use_target(board, "bot_buried_lightboard_start", 64, 3);
                return;
            }

            buttons = getstructarray("sq_bp_button", "targetname");
            foreach(button in buttons)
            {
                if(isdefined(button) && isdefined(button.script_string) &&
                   button.script_string == level.str_sq_bp_active_light &&
                   isdefined(button.trig) && isdefined(button.trig.origin))
                {
                    self scripts\zm\zm_bo2_bots::bot_quest_use_target(button.trig, "bot_buried_lightboard_button", 36, 2);
                    return;
                }
            }
        }
        else
        {
            levers = getentarray("sq_ml_lever", "targetname");
            best_lever = undefined;
            best_order = 9999;
            foreach(lever in levers)
            {
                if(!isdefined(lever) || !isdefined(lever.n_lever_order) ||
                   (isdefined(lever.is_flipped) && lever.is_flipped) ||
                   !isdefined(lever.trig) || !isdefined(lever.trig.origin))
                    continue;

                if(lever.n_lever_order < best_order)
                {
                    best_order = lever.n_lever_order;
                    best_lever = lever;
                }
            }

            if(isdefined(best_lever))
                self scripts\zm\zm_bo2_bots::bot_quest_use_target(best_lever.trig, "bot_buried_maze_lever", 36, 2);
        }

        return;
    }

    // The Fountain target stage is time limited. Start the fountain using its
    // stock trigger, then shoot live target models before their four-second
    // timeout. This is a real weapon hit, not an artificial success flag.
    if(isdefined(stage) && stage == "ows" && !flag("sq_ows_success"))
    {
        if(!flag("sq_ows_start"))
        {
            fountain = getstruct("sq_ows_fountain", "targetname");
            if(isdefined(fountain) && isdefined(fountain.origin))
            {
                point = spawnstruct();
                point.origin = fountain.origin;
                self scripts\zm\zm_bo2_bots::bot_quest_use_target(point, "bot_buried_fountain_start", 64, 3);
            }
            return;
        }

        script_models = getentarray("script_model", "classname");
        best_target = undefined;
        best_dist_sq = 999999999;
        foreach(target in script_models)
        {
            if(!isdefined(target) || !isdefined(target.origin))
                continue;
            if((!isdefined(target.modelname) || target.modelname != "p6_zm_bu_target") &&
               (!isdefined(target.model) || target.model != "p6_zm_bu_target"))
                continue;

            dist_sq = distancesquared(self.origin, target.origin);
            if(dist_sq < best_dist_sq)
            {
                best_dist_sq = dist_sq;
                best_target = target;
            }
        }

        if(isdefined(best_target))
        {
            self.bot.is_objective_using = 1;
            self lookat(best_target.origin);
            for(i = 0; i < 8 && isdefined(best_target); i++)
            {
                self pressattackbutton(0.1);
                wait 0.1;
            }
            self.bot.is_objective_using = undefined;
            self clearlookat();
        }
        return;
    }

    self bot_quest_buried_traverse();
}

bot_quest_buried_traverse()
{
    self endon("disconnect");
    self endon("death");
    level endon("end_game");

    if(!isdefined(self.bot) || is_true(self.bot.is_parkouring) ||
       is_true(self.bot.is_objective_using) || is_true(self.bot.is_building) ||
       is_true(self.bot.is_crafting) || is_true(self.bot.is_perk_buying) ||
       is_true(self.bot.is_buying) || is_true(self.bot.is_using_box) ||
       is_true(self.bot.is_reviving) || is_true(self.bot.is_selfreviving))
        return;

    if(isdefined(self.bot.buried_parkour_retry) && gettime() < self.bot.buried_parkour_retry)
        return;

    // Buried's Trample Steam launches horizontally. It is not a vertical
    // elevator, so only use it for a same-height gap with a real route beyond.
    if(!isdefined(self.current_equipment) || self.current_equipment != "equip_springpad_zm" ||
       !self isonground() || self isonladder() || self ismantling())
        return;

    target_origin = undefined;
    if(isdefined(level.bot_command_mode) && level.bot_command_mode == "follow")
    {
        commander = level.bot_commander;
        if(isdefined(commander) && isdefined(commander.origin) && isalive(commander) &&
           !isdefined(commander.bot) &&
           !(isdefined(commander.pers) && isdefined(commander.pers["isbot"])))
            target_origin = commander.origin;
        else
        {
            foreach(candidate in get_players())
            {
                if(!isdefined(candidate) || !isdefined(candidate.origin) || !isalive(candidate) ||
                   isdefined(candidate.bot) ||
                   (isdefined(candidate.pers) && isdefined(candidate.pers["isbot"])))
                    continue;
                target_origin = candidate.origin;
                break;
            }
        }
    }
    else if(self hasgoal("wander"))
        target_origin = self getgoal("wander");

    if(!isdefined(target_origin) ||
       abs(target_origin[2] - self.origin[2]) > 96 ||
       distancesquared(self.origin, target_origin) < 260 * 260 ||
       findpath(self.origin, target_origin, undefined, 0, 1))
    {
        self.bot.buried_parkour_retry = gettime() + 5000;
        return;
    }

    // Look for a plausible landing-side navigation node: same height, in the
    // direction of the final goal, and able to path onward to that goal.
    nodes = getnodesinradius(target_origin, 760, 0, 420, "any", 192);
    if(!isdefined(nodes) || nodes.size == 0)
    {
        self.bot.buried_parkour_retry = gettime() + 6000;
        return;
    }

    best_node = undefined;
    best_score = 999999999;
    current_target_dist = distancesquared(self.origin, target_origin);

    foreach(node in nodes)
    {
        if(!isdefined(node) || !isdefined(node.origin))
            continue;
        if(abs(node.origin[2] - self.origin[2]) > 96)
            continue;
        if(distancesquared(node.origin, target_origin) >= current_target_dist - 22500)
            continue;
        if(!check_point_in_playable_area(node.origin))
            continue;
        if(!findpath(node.origin, target_origin, undefined, 0, 1))
            continue;

        delta = node.origin - self.origin;
        horizontal_sq = delta[0] * delta[0] + delta[1] * delta[1];
        if(horizontal_sq < 220 * 220 || horizontal_sq > 1150 * 1150)
            continue;

        if(isdefined(level.zones))
        {
            zone = maps\mp\zombies\_zm_zonemgr::get_zone_from_position(node.origin + (0, 0, 32), 1);
            if(isdefined(zone) && !maps\mp\zombies\_zm_zonemgr::zone_is_enabled(zone))
                continue;
        }

        // A useful landing candidate should be across the missing route, not
        // simply another node on the bot's current connected nav island.
        if(findpath(self.origin, node.origin, undefined, 0, 1))
            continue;

        score = distancesquared(node.origin, target_origin) + horizontal_sq * 0.15;
        if(score < best_score)
        {
            best_score = score;
            best_node = node;
        }
    }

    if(!isdefined(best_node))
    {
        self.bot.buried_parkour_retry = gettime() + 9000;
        return;
    }

    self.bot.buried_parkour_retry = gettime() + 25000;
    // Keep this separate from is_objective_using: that flag makes the shared
    // wander controller delete the bot's normal movement goal.
    self.bot.is_parkouring = 1;

    // Use the stock equipment placement callback. The stock springpad thinker
    // creates its linked trigger and performs the actual horizontal launch.
    launch_angles = vectortoangles(best_node.origin - self.origin);
    self setplayerangles((0, launch_angles[1], 0));
    wait 0.05;
    self maps\mp\zombies\_zm_equipment::equipment_drop_to_planted("equip_springpad_zm", self);

    pad = undefined;
    deadline = gettime() + 6500;
    while(gettime() < deadline && isalive(self))
    {
        if(isdefined(self.buildablespringpad) &&
           isdefined(self.buildablespringpad.trigger) &&
           isdefined(self.buildablespringpad.trigger.origin))
        {
            pad = self.buildablespringpad;
            if(is_true(pad.is_armed))
                break;
        }
        wait 0.1;
    }

    launched = false;
    if(isdefined(pad) && isdefined(pad.trigger) && isdefined(pad.trigger.origin) &&
       is_true(pad.is_armed))
    {
        self addgoal(pad.trigger.origin, 12, 2, "bot_buried_springpad");
        launch_deadline = gettime() + 7000;
        while(gettime() < launch_deadline && isalive(self))
        {
            if(!isdefined(pad) || !isdefined(pad.trigger) || !isdefined(pad.trigger.origin))
                break;
            if(!self isonground())
            {
                launched = true;
                break;
            }
            wait 0.1;
        }
        self cancelgoal("bot_buried_springpad");
    }

    if(launched)
    {
        land_deadline = gettime() + 14000;
        while(gettime() < land_deadline && isalive(self) && !self isonground())
            wait 0.1;

        if(isalive(self) && self isonground())
        {
            if(findpath(self.origin, best_node.origin, undefined, 0, 1))
            {
                self addgoal(best_node.origin, 48, 2, "bot_buried_springpad_landing");
                move_deadline = gettime() + 7000;
                while(gettime() < move_deadline && isalive(self) &&
                      distancesquared(self.origin, best_node.origin) > 48 * 48)
                    wait 0.15;
                self cancelgoal("bot_buried_springpad_landing");
            }
            if(findpath(self.origin, target_origin, undefined, 0, 1))
            {
                self addgoal(target_origin, 72, 2, "bot_buried_springpad_target");
                move_deadline = gettime() + 8000;
                while(gettime() < move_deadline && isalive(self) &&
                      distancesquared(self.origin, target_origin) > 72 * 72)
                    wait 0.2;
                self cancelgoal("bot_buried_springpad_target");
            }
        }
    }

    self cancelgoal("bot_buried_springpad");
    self cancelgoal("bot_buried_springpad_landing");
    self cancelgoal("bot_buried_springpad_target");
    self.bot.is_parkouring = undefined;
}
bot_buried_tpo_restore_host()
{
    level endon("end_game");
    level waittill("sq_tpo_stop_checking_time_bomb_volume");
    if(isdefined(level.bot_buried_tpo_host_player) && isdefined(level.bot_buried_tpo_host_origin))
    {
        if(isdefined(level.bot_buried_tpo_host_player) && isalive(level.bot_buried_tpo_host_player))
        {
            level.bot_buried_tpo_host_player setorigin(level.bot_buried_tpo_host_origin);
            if(isdefined(level.bot_buried_tpo_host_angles))
                level.bot_buried_tpo_host_player setplayerangles(level.bot_buried_tpo_host_angles);
        }
    }
    level.bot_buried_tpo_host_player = undefined;
    level.bot_buried_tpo_host_origin = undefined;
    level.bot_buried_tpo_host_angles = undefined;
}
bot_buried_weapon_score_override(weapon)
{
	if(weapon == "time_bomb_zm" &&
	   ((isdefined(level._cur_stage_name) && level._cur_stage_name == "ctw" &&
	     flag("sq_is_max_tower_built") && !is_true(level.bot_buried_wisp_timebomb_saved)) ||
	    (isdefined(level._cur_stage_name) && level._cur_stage_name == "tpo" &&
	     flag("sq_is_ric_tower_built") && !flag("sq_tpo_time_bomb_in_valid_location"))))
		return 110;

	return undefined;
}

bot_buried_should_take_box_weapon(boxweapon)
{
	if(!isdefined(boxweapon) || boxweapon != "time_bomb_zm" || self hasweapon("time_bomb_zm"))
		return false;

	if(isdefined(level._cur_stage_name) && level._cur_stage_name == "ctw" &&
	   flag("sq_is_max_tower_built") && !is_true(level.bot_buried_wisp_timebomb_saved))
		return true;

	if(isdefined(level._cur_stage_name) && level._cur_stage_name == "tpo" &&
	   flag("sq_is_ric_tower_built") && !flag("sq_tpo_time_bomb_in_valid_location"))
		return true;

	return false;
}

