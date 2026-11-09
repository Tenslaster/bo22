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
    // Keep Easter-egg trigger ownership single-leader. In wander mode each bot
    // may solve its own Trample Steam gap; in follow mode only the leader
    // deploys a pad so the whole squad does not stack on the same launch point.
    quest_leader = self bot_buried_claim_quest_lead();
    if(!isdefined(level.bot_command_mode) || level.bot_command_mode != "follow" || quest_leader)
        self bot_quest_buried_traverse();

    if(!quest_leader)
        return;

    if(!is_true(self.bot.buried_runtime_started))
    {
        self.bot.buried_runtime_started = 1;
        self thread bot_buried_runtime_watch();
    }

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

    // Mined Games is route-specific in the stock script:
    // Maxis breaks every amplifier with the Subwoofer; Richtofen fills every
    // amplifier with 25 Slow Gun hits. Treating both routes as Slow Gun is a
    // dead end because the stock stage accepts either all-broken or all-filled.
    if(isdefined(stage) && stage == "mta")
    {
        if(flag("sq_is_max_tower_built"))
            self bot_buried_mta_maxis();
        else if(flag("sq_is_ric_tower_built"))
            self bot_buried_mta_richtofen();
        return;
    }

    // Ghost lantern: first use a real frag/sticky impact to make the stock
    // lantern crash. Only after its native pickup trigger appears do we collect
    // the buildable piece through the stock player_take_piece callback.
    if(isdefined(level.vh_lantern))
    {
        if(isdefined(level.vh_lantern.t_pickup) && isdefined(level.vh_lantern.t_pickup.origin))
        {
            self scripts\zm\zm_bo2_bots::bot_quest_use_target(
                level.vh_lantern.t_pickup, "bot_buried_ghost_lantern", 42, 4);
            return;
        }

        if(isdefined(level.vh_lantern.m_lantern) && isdefined(level.vh_lantern.m_lantern.origin))
        {
            if(!self bot_buried_throw_grenade_at(level.vh_lantern.m_lantern.origin,
                "bot_buried_ghost_lantern_shot", 1100))
            {
                self scripts\zm\zm_bo2_bots::bot_quest_move_to(
                    level.vh_lantern.m_lantern.origin, "bot_buried_ghost_lantern_approach", 420, 5000);
            }
            return;
        }
    }

    // Fuel the ghost lamp using the real map kill watcher. On Maxis, player
    // kills do not increment the stock fuel counter, so deploy the Subwoofer
    // beside the lamp area and let its native non-player damage create fuel.
    // Richtofen's ghost kills are credited by the stock watcher while the
    // lantern carrier remains inside the same radius.
    if(isdefined(stage) && stage == "ftl" && !flag("ftl_lantern_charged") &&
       isdefined(level.sq_lamp_generator_unitrig) &&
       isdefined(level.sq_lamp_generator_unitrig.realorigin))
    {
        self scripts\zm\zm_bo2_bots::bot_quest_move_to(
            level.sq_lamp_generator_unitrig.realorigin, "bot_buried_lantern_defend", 220, 6500);

        if(flag("sq_is_max_tower_built") &&
           self has_player_equipment("equip_subwoofer_zm") &&
           (!isdefined(level.bot_buried_lamp_subwoofer_at) ||
            distancesquared(level.bot_buried_lamp_subwoofer_at,
                level.sq_lamp_generator_unitrig.realorigin) > 96 * 96))
        {
            if(self scripts\zm\zm_bo2_bots::bot_quest_deploy_equipment(
                "equip_subwoofer_zm", level.sq_lamp_generator_unitrig.realorigin,
                "bot_buried_lamp_subwoofer"))
                level.bot_buried_lamp_subwoofer_at = level.sq_lamp_generator_unitrig.realorigin;
        }
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
            // Maxis uses the vehicle Wisp; Richtofen uses the sq_wisp entity.
            wisp_for_save = level.vh_wisp;
            if(isdefined(wisp_for_save) && isdefined(wisp_for_save.origin))
                self scripts\zm\zm_bo2_bots::bot_quest_move_to(
                    wisp_for_save.origin, "bot_buried_wisp_timebomb_save", 160, 8000);
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

                self bot_buried_tpo_gather_team(timebomb_volume);
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

    // Catch the live Wisp during the Guillotine stage. Richtofen's stock
    // watcher requires Vulture Aid and a player within 64 units of each Wisp
    // waypoint before its 12-second timeout. Maxis instead needs nearby zombies
    // for the moving Wisp's energy watcher; stay close enough for kills to help.
    if(isdefined(stage) && stage == "ctw" && !flag("sq_wisp_success") &&
       !flag("sq_wisp_failed"))
    {
        if(flag("sq_is_max_tower_built") && isdefined(level.vh_wisp) &&
           isdefined(level.vh_wisp.origin))
        {
            if(distancesquared(self.origin, level.vh_wisp.origin) > 180 * 180)
                self scripts\zm\zm_bo2_bots::bot_quest_move_to(
                    level.vh_wisp.origin, "bot_buried_maxis_wisp_support", 180, 6500);
            return;
        }

        wisp = getent("sq_wisp", "targetname");
        if(isdefined(wisp) && isdefined(wisp.origin))
        {
            if(!self hasperk("specialty_nomotionsensor"))
                self maps\mp\zombies\_zm_perks::give_perk("specialty_nomotionsensor", 0);

            self scripts\zm\zm_bo2_bots::bot_quest_move_to(
                wisp.origin, "bot_buried_ric_wisp_touch", 48, 8500);
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
            // The stock script spawns a trigger at level.t_start. The board
            // itself is only a script_model and cannot receive use input.
            if(!isdefined(level.str_sq_bp_active_light) || level.str_sq_bp_active_light == "")
            {
                if(isdefined(level.t_start) && isdefined(level.t_start.origin))
                    self scripts\zm\zm_bo2_bots::bot_quest_use_target(
                        level.t_start, "bot_buried_lightboard_start", 30, 2);
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
            // The stock maze puzzle assigns each spawned lever a randomized
            // n_lever_order. Its interaction records the current global index,
            // so the lever for the next index must be pulled next.
            levers = getentarray("sq_ml_lever", "targetname");
            best_lever = undefined;
            next_order = isdefined(level.sq_ml_curr_lever) ? level.sq_ml_curr_lever : 0;
            foreach(lever in levers)
            {
                if(!isdefined(lever) || !isdefined(lever.n_lever_order) ||
                   lever.n_lever_order != next_order ||
                   (isdefined(lever.is_flipped) && lever.is_flipped) ||
                   !isdefined(lever.trig) || !isdefined(lever.trig.origin))
                    continue;

                best_lever = lever;
                break;
            }

            if(isdefined(best_lever))
                self scripts\zm\zm_bo2_bots::bot_quest_use_target(
                    best_lever.trig, "bot_buried_maze_lever_" + next_order, 34, 1);
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

        self bot_buried_ows_shoot_active_targets();
        return;
    }

}

// -----------------------------------------------------------------------------
// Buried autonomous action layer.
// All objectives below activate stock map triggers or use real player weapons.
// Completion remains owned by the original map scripts.
// -----------------------------------------------------------------------------

bot_buried_mta_maxis()
{
    if(flag("sq_amplifiers_broken"))
        return;

    amps = getentarray("sq_amplifier", "targetname");
    if(!isdefined(amps) || amps.size == 0)
        return;

    foreach(amp in amps)
    {
        if(!isdefined(amp) || !isdefined(amp.origin))
            continue;
        if(isdefined(amp.amplifier_state) && amp.amplifier_state == "broken")
            continue;

        if(distancesquared(self.origin, amp.origin) > 104 * 104)
        {
            self scripts\zm\zm_bo2_bots::bot_quest_move_to(
                amp.origin, "bot_buried_mta_maxis_discover", 96, 6500);
            return;
        }

        if(!self has_player_equipment("equip_subwoofer_zm"))
        {
            self.bot.buried_need_subwoofer = 1;
            return;
        }

        self.bot.buried_need_subwoofer = undefined;

        if(!isdefined(self.buildablesubwoofer) ||
           !isdefined(self.buildablesubwoofer.origin) ||
           distancesquared(self.buildablesubwoofer.origin, amp.origin) > 300 * 300)
        {
            if(!isdefined(self.bot.buried_mta_deploy_after) ||
               gettime() >= self.bot.buried_mta_deploy_after)
            {
                self.bot.buried_mta_deploy_after = gettime() + 7000;
                self scripts\zm\zm_bo2_bots::bot_quest_deploy_equipment(
                    "equip_subwoofer_zm", amp.origin, "bot_buried_mta_maxis_subwoofer");
            }
        }

        return;
    }
}

bot_buried_mta_richtofen()
{
    if(flag("sq_amplifiers_on"))
        return;

    amps = getentarray("sq_amplifier", "targetname");
    if(!isdefined(amps) || amps.size == 0)
        return;

    slowgun = undefined;
    if(self hasweapon("slowgun_zm"))
        slowgun = "slowgun_zm";
    else if(self hasweapon("slowgun_upgraded_zm"))
        slowgun = "slowgun_upgraded_zm";

    if(!isdefined(slowgun))
    {
        self.bot.buried_need_slowgun = 1;
        return;
    }

    self.bot.buried_need_slowgun = undefined;

    foreach(amp in amps)
    {
        if(!isdefined(amp) || !isdefined(amp.origin))
            continue;
        if(isdefined(amp.amplifier_state) && amp.amplifier_state == "filled")
            continue;
        if(isdefined(amp.amplifier_state) && amp.amplifier_state == "broken")
            continue;

        if(distancesquared(self.origin, amp.origin) > 600 * 600)
        {
            self scripts\zm\zm_bo2_bots::bot_quest_move_to(
                amp.origin, "bot_buried_mta_ric_discover", 110, 7500);
            return;
        }

        // Each amplifier needs 25 damage events from the Slow Gun.
        self scripts\zm\zm_bo2_bots::bot_quest_fire_at(
            amp.origin, slowgun, "bot_buried_mta_ric_charge", 720, 34, 0.12);
        return;
    }
}

bot_buried_throw_grenade_at(target_origin, goal_name, max_range)
{
    if(!isdefined(target_origin))
        return false;

    if(!isdefined(max_range) || max_range < 128)
        max_range = 900;

    if(!self bot_objective_can_run())
        return false;

    if(is_true(self.bot.is_throwing_grenade) || self isthrowinggrenade())
        return false;

    if(isdefined(self.bot.buried_grenade_retry) &&
       gettime() < self.bot.buried_grenade_retry)
        return false;

    if(distancesquared(self.origin, target_origin) > max_range * max_range)
    {
        if(!self scripts\zm\zm_bo2_bots::bot_quest_move_to(
            target_origin, goal_name + "_approach", max_range * 0.7, 7000))
            return false;
    }

    weapon = undefined;
    if(self getweaponammoclip("frag_grenade_zm") +
       self getweaponammostock("frag_grenade_zm") > 0)
        weapon = "frag_grenade_zm";
    else if(self getweaponammoclip("sticky_grenade_zm") +
            self getweaponammostock("sticky_grenade_zm") > 0)
        weapon = "sticky_grenade_zm";

    if(!isdefined(weapon))
    {
        self.bot.buried_grenade_retry = gettime() + 2500;
        return false;
    }

    if(!sighttracepassed(self geteyeapprox(), target_origin + (0, 0, 24), 0, self))
    {
        self.bot.buried_grenade_retry = gettime() + 1200;
        return false;
    }

    self.bot.is_throwing_grenade = 1;
    self.bot.is_objective_using = 1;
    self.bot.buried_grenade_retry = gettime() + 9000;

    self throwgrenade(weapon, target_origin);

    deadline = gettime() + 2200;
    while(gettime() < deadline && isalive(self) && self isthrowinggrenade())
        wait 0.05;

    self.bot.is_throwing_grenade = undefined;
    self.bot.is_objective_using = undefined;
    return true;
}

// The native FTL counter listens for deaths near the lamp. Maxis needs
// non-player damage, so the Subwoofer is used as the stock kill source.
bot_buried_lamp_support()
{
    if(flag("ftl_lantern_charged"))
        return true;

    if(!isdefined(level.sq_lamp_generator_unitrig))
        return false;

    lamp_origin = undefined;
    if(isdefined(level.sq_lamp_generator_unitrig.realorigin))
        lamp_origin = level.sq_lamp_generator_unitrig.realorigin;
    else if(isdefined(level.sq_lamp_generator_unitrig.origin))
        lamp_origin = level.sq_lamp_generator_unitrig.origin;

    if(!isdefined(lamp_origin))
        return false;

    if(distancesquared(self.origin, lamp_origin) > 220 * 220)
    {
        self scripts\zm\zm_bo2_bots::bot_quest_move_to(
            lamp_origin, "bot_buried_lamp_support_area", 210, 8000);
        return false;
    }

    if(flag("sq_is_max_tower_built") &&
       self has_player_equipment("equip_subwoofer_zm"))
    {
        if(!isdefined(self.buildablesubwoofer) ||
           !isdefined(self.buildablesubwoofer.origin) ||
           distancesquared(self.buildablesubwoofer.origin, lamp_origin) > 256 * 256)
        {
            if(!isdefined(self.bot.buried_lamp_deploy_after) ||
               gettime() >= self.bot.buried_lamp_deploy_after)
            {
                self.bot.buried_lamp_deploy_after = gettime() + 8000;
                self scripts\zm\zm_bo2_bots::bot_quest_deploy_equipment(
                    "equip_subwoofer_zm", lamp_origin, "bot_buried_lamp_subwoofer");
            }
        }
    }

    return false;
}

// The Richtofen path grants Vulture Aid to the bot before it touches the
// moving Wisp. The stock watcher checks the perk and a 64-unit distance.
bot_buried_ric_wisp_touch()
{
    wisp = getent("sq_wisp", "targetname");

    if(!isdefined(wisp) || !isdefined(wisp.origin))
        return false;

    if(!self hasperk("specialty_nomotionsensor"))
        self maps\mp\zombies\_zm_perks::give_perk("specialty_nomotionsensor", 0);

    self scripts\zm\zm_bo2_bots::bot_quest_move_to(
        wisp.origin, "bot_buried_ric_wisp_touch", 48, 8500);

    return distancesquared(self.origin, wisp.origin) <= 48 * 48;
}

bot_buried_maxis_wisp_support()
{
    if(!isdefined(level.vh_wisp) || !isdefined(level.vh_wisp.origin))
        return false;

    if(distancesquared(self.origin, level.vh_wisp.origin) > 180 * 180)
        self scripts\zm\zm_bo2_bots::bot_quest_move_to(
            level.vh_wisp.origin, "bot_buried_maxis_wisp_support", 180, 6500);

    return true;
}

// Select the exact live Maxis bulb button. This routine is used after the
// stock start trigger has activated the random ten-second light sequence.
bot_buried_lightboard_current_button()
{
    if(!isdefined(level.str_sq_bp_active_light) ||
       level.str_sq_bp_active_light == "")
        return undefined;

    buttons = getstructarray("sq_bp_button", "targetname");

    if(!isdefined(buttons))
        return undefined;

    foreach(button in buttons)
    {
        if(!isdefined(button) || !isdefined(button.script_string))
            continue;

        if(button.script_string != level.str_sq_bp_active_light)
            continue;

        if(!isdefined(button.trig) || !isdefined(button.trig.origin))
            continue;

        return button;
    }

    return undefined;
}

bot_buried_press_lightboard_button()
{
    button = self bot_buried_lightboard_current_button();

    if(!isdefined(button))
        return false;

    return self scripts\zm\zm_bo2_bots::bot_quest_use_target(
        button.trig, "bot_buried_lightboard_" + button.script_string, 30, 1);
}

// Each spawned Richtofen lever has a stock randomized n_lever_order. The
// puzzle records the global index at the exact instant each lever is used.
// Pressing a lever out of order records the wrong index and resets on the next
// maze permutation, so always target sq_ml_curr_lever.
bot_buried_maze_next_lever()
{
    if(!isdefined(level.sq_ml_curr_lever))
        return undefined;

    levers = getentarray("sq_ml_lever", "targetname");

    if(!isdefined(levers))
        return undefined;

    foreach(lever in levers)
    {
        if(!isdefined(lever) || !isdefined(lever.n_lever_order))
            continue;

        if(lever.n_lever_order != level.sq_ml_curr_lever)
            continue;

        if(isdefined(lever.is_flipped) && lever.is_flipped)
            continue;

        if(!isdefined(lever.trig) || !isdefined(lever.trig.origin))
            continue;

        return lever;
    }

    return undefined;
}

bot_buried_press_maze_next_lever()
{
    lever = self bot_buried_maze_next_lever();

    if(!isdefined(lever))
        return false;

    return self scripts\zm\zm_bo2_bots::bot_quest_use_target(
        lever.trig, "bot_buried_maze_order_" + lever.n_lever_order, 34, 1);
}

// OWS targets are script_models and are destroyed by their native damage
// watcher. Re-scan every tick, since several targets can spawn in one second.
bot_buried_is_ows_target(target)
{
    if(!isdefined(target) || !isdefined(target.origin))
        return false;

    if(isdefined(target.modelname) && target.modelname == "p6_zm_bu_target")
        return true;

    if(isdefined(target.model) && target.model == "p6_zm_bu_target")
        return true;

    return false;
}

bot_buried_find_ows_target()
{
    models = getentarray("script_model", "classname");

    if(!isdefined(models))
        return undefined;

    best = undefined;
    best_dist = 999999999;

    foreach(model in models)
    {
        if(!self bot_buried_is_ows_target(model))
            continue;

        if(isdefined(model.bot_buried_ows_retry) &&
           gettime() < model.bot_buried_ows_retry)
            continue;

        dist = distancesquared(self.origin, model.origin);

        if(dist < best_dist)
        {
            best = model;
            best_dist = dist;
        }
    }

    return best;
}

bot_buried_ows_shoot_active_targets()
{
    weapon = self scripts\zm\zm_bo2_bots::bot_quest_primary_weapon();

    if(!isdefined(weapon))
        return false;

    target = self bot_buried_find_ows_target();

    if(!isdefined(target))
        return false;

    // Do not run toward a flying target: the native target expires after
    // four seconds. Use a real hitscan shot from the current position.
    if(distancesquared(self.origin, target.origin) > 2700 * 2700)
    {
        target.bot_buried_ows_retry = gettime() + 400;
        return false;
    }

    target.bot_buried_ows_retry = gettime() + 650;

    self scripts\zm\zm_bo2_bots::bot_quest_fire_at(
        target.origin, weapon, "bot_buried_ows_shot", 2800, 4, 0.10);

    return true;
}

// Move every bot into the valid time-bomb brush. The stock Richtofen
// controller checks all four player entities simultaneously; moving only the
// quest leader can never satisfy the original four-player condition.
bot_buried_tpo_gather_team(volume)
{
    if(!isdefined(volume) || !isdefined(volume.origin))
        return false;

    players = get_players();

    if(!isdefined(players) || players.size == 0)
        return false;

    offsets = array(
        ( -22, -22, 0 ),
        ( 22, -22, 0 ),
        ( -22, 22, 0 ),
        ( 22, 22, 0 )
    );

    bot_index = 0;

    foreach(player in players)
    {
        if(!isdefined(player) || !isdefined(player.origin) || !isalive(player))
            continue;

        if(isdefined(player.bot))
        {
            offset = offsets[bot_index % offsets.size];
            player addgoal(volume.origin + offset, 220, 2, "bot_buried_tpo_team");
            player.bot.buried_tpo_goal_active = 1;
            bot_index++;
        }
    }

    if(!isdefined(level.bot_buried_tpo_release_thread) ||
       !level.bot_buried_tpo_release_thread)
    {
        level.bot_buried_tpo_release_thread = 1;
        level thread bot_buried_tpo_team_release();
    }

    all_ready = true;

    foreach(player in players)
    {
        if(!isdefined(player) || !isdefined(player.origin) || !isalive(player))
            continue;

        if(!player istouching(volume))
        {
            all_ready = false;
            break;
        }
    }

    return all_ready;
}

bot_buried_tpo_team_release()
{
    level endon("end_game");

    level waittill("sq_tpo_stop_checking_time_bomb_volume");

    players = get_players();

    if(isdefined(players))
    {
        foreach(player in players)
        {
            if(!isdefined(player) || !isdefined(player.bot))
                continue;

            if(is_true(player.bot.buried_tpo_goal_active))
                player cancelgoal("bot_buried_tpo_team");

            player.bot.buried_tpo_goal_active = undefined;
        }
    }

    level.bot_buried_tpo_release_thread = undefined;
}

// Route-specific box selection. The generic bot weapon picker calls these
// callbacks and still uses the stock Mystery Box grant routine.
bot_buried_weapon_score_override(weapon)
{
    if(!isdefined(weapon))
        return undefined;

    stage = level._cur_stage_name;

    if(weapon == "time_bomb_zm" &&
       ((isdefined(stage) && stage == "ctw" &&
         flag("sq_is_max_tower_built") &&
         !is_true(level.bot_buried_wisp_timebomb_saved)) ||
        (isdefined(stage) && stage == "tpo" &&
         flag("sq_is_ric_tower_built") &&
         !flag("sq_tpo_time_bomb_in_valid_location"))))
        return 120;

    if((weapon == "slowgun_zm" || weapon == "slowgun_upgraded_zm") &&
       isdefined(stage) && stage == "mta" &&
       flag("sq_is_ric_tower_built") && !flag("sq_amplifiers_on"))
        return 115;

    if((weapon == "tazer_knuckles_zm" || weapon == "bowie_knife_zm" ||
        weapon == "knife_ballistic_bowie_zm") &&
       isdefined(stage) && stage == "ts" &&
       !self bot_buried_has_sign_melee())
        return 110;

    return undefined;
}

bot_buried_should_take_box_weapon(boxweapon)
{
    if(!isdefined(boxweapon) || self hasweapon(boxweapon))
        return false;

    stage = level._cur_stage_name;

    if(boxweapon == "time_bomb_zm" &&
       ((isdefined(stage) && stage == "ctw" &&
         flag("sq_is_max_tower_built") &&
         !is_true(level.bot_buried_wisp_timebomb_saved)) ||
        (isdefined(stage) && stage == "tpo" &&
         flag("sq_is_ric_tower_built") &&
         !flag("sq_tpo_time_bomb_in_valid_location"))))
        return true;

    if((boxweapon == "slowgun_zm" || boxweapon == "slowgun_upgraded_zm") &&
       isdefined(stage) && stage == "mta" &&
       flag("sq_is_ric_tower_built") && !flag("sq_amplifiers_on"))
        return true;

    if((boxweapon == "tazer_knuckles_zm" || boxweapon == "bowie_knife_zm" ||
        boxweapon == "knife_ballistic_bowie_zm") &&
       isdefined(stage) && stage == "ts")
        return true;

    return false;
}

// Runtime state watcher: reset local retry timers when the stock stage changes.
// It does not advance the quest or write any native completion flag.
bot_buried_runtime_watch()
{
    self endon("disconnect");
    self endon("death");
    self endon("bot_relife");
    level endon("end_game");

    last_stage = undefined;

    for(;;)
    {
        wait 0.5;

        current_stage = level._cur_stage_name;

        if(!isdefined(current_stage))
            continue;

        if(!isdefined(last_stage) || last_stage != current_stage)
        {
            self.bot.buried_stage_entered = gettime();
            self.bot.buried_stage_name = current_stage;
            self.bot.buried_retry_stage = undefined;
            self.bot.buried_retry_after = undefined;
            self.bot.buried_grenade_retry = undefined;
            self.bot.buried_entity_retry = undefined;
            last_stage = current_stage;
        }

        if(isdefined(level.bot_buried_quest_owner) &&
           level.bot_buried_quest_owner != self &&
           (!isalive(level.bot_buried_quest_owner) ||
            !isdefined(level.bot_buried_quest_owner_until) ||
            gettime() >= level.bot_buried_quest_owner_until))
        {
            level.bot_buried_quest_owner = undefined;
            level.bot_buried_quest_owner_until = undefined;
        }

        if(current_stage == "mta")
        {
            if(flag("sq_is_max_tower_built"))
                self.bot.buried_need_subwoofer = !self has_player_equipment("equip_subwoofer_zm");
            else
                self.bot.buried_need_slowgun = !(self hasweapon("slowgun_zm") ||
                    self hasweapon("slowgun_upgraded_zm"));
        }
    }
}

bot_buried_has_sign_melee()
{
    return self hasweapon("tazer_knuckles_zm") ||
           self hasweapon("bowie_knife_zm") ||
           self hasweapon("knife_ballistic_bowie_zm") ||
           self hasweapon("knife_ballistic_bowie_upgraded_zm");
}

bot_buried_stage_debug_name()
{
    if(!isdefined(level._cur_stage_name))
        return "waiting";

    return level._cur_stage_name;
}

bot_buried_route_debug_name()
{
    if(flag("sq_is_max_tower_built"))
        return "Maxis";

    if(flag("sq_is_ric_tower_built"))
        return "Richtofen";

    return "Undecided";
}

bot_buried_stage_state_debug()
{
    stage = level._cur_stage_name;

    if(!isdefined(stage))
        return "Waiting for sidequest";

    if(stage == "mta")
        return "Amp filled: " + self bot_buried_amp_count_state("filled") +
               " / broken: " + self bot_buried_amp_count_state("broken");

    if(stage == "gl")
        return isdefined(level.vh_lantern.t_pickup) ? "Lantern crashed" : "Lantern airborne";

    if(stage == "ftl")
        return "Lamp fuel: " + (isdefined(level.sq_ftl_lantern_fuel) ?
               level.sq_ftl_lantern_fuel : 0) + "/10";

    if(stage == "ctw")
        return flag("sq_wisp_success") ? "Wisp complete" : "Wisp active";

    if(stage == "ip")
        return flag("sq_ip_puzzle_complete") ? "Puzzle complete" : "Puzzle active";

    if(stage == "ows")
        return flag("sq_ows_success") ? "Targets complete" : "Targets active";

    if(stage == "tpo")
        return flag("sq_tpo_found_item") ? "Switch acquired" : "Time Bomb / search";

    return stage;
}

bot_buried_amp_count_state(state_name)
{
    amps = getentarray("sq_amplifier", "targetname");
    count = 0;

    if(!isdefined(amps))
        return 0;

    foreach(amp in amps)
    {
        if(!isdefined(amp))
            continue;

        if(isdefined(amp.amplifier_state) && amp.amplifier_state == state_name)
            count++;
    }

    return count;
}

// Wisp selector handles the two different stock entity types.
bot_buried_get_wisp()
{
    if(flag("sq_is_max_tower_built"))
        return level.vh_wisp;

    return getent("sq_wisp", "targetname");
}

bot_buried_touch_wisp()
{
    wisp = self bot_buried_get_wisp();

    if(!isdefined(wisp) || !isdefined(wisp.origin))
        return false;

    if(flag("sq_is_ric_tower_built") && !self hasperk("specialty_nomotionsensor"))
        self maps\mp\zombies\_zm_perks::give_perk("specialty_nomotionsensor", 0);

    if(flag("sq_is_max_tower_built"))
    {
        if(distancesquared(self.origin, wisp.origin) > 180 * 180)
            self scripts\zm\zm_bo2_bots::bot_quest_move_to(
                wisp.origin, "bot_buried_maxis_wisp", 180, 6500);
    }
    else
    {
        if(distancesquared(self.origin, wisp.origin) > 48 * 48)
            self scripts\zm\zm_bo2_bots::bot_quest_move_to(
                wisp.origin, "bot_buried_ric_wisp", 48, 8500);
    }

    return true;
}

bot_buried_lantern_available()
{
    return isdefined(level.vh_lantern) &&
           isdefined(level.vh_lantern.m_lantern) &&
           isdefined(level.vh_lantern.m_lantern.origin);
}

bot_buried_lantern_pickup_available()
{
    return isdefined(level.vh_lantern) &&
           isdefined(level.vh_lantern.t_pickup) &&
           isdefined(level.vh_lantern.t_pickup.origin);
}

bot_buried_find_unsearched_corpse()
{
    corpses = getentarray("sq_tpo_corpse_model", "targetname");

    if(!isdefined(corpses))
        return undefined;

    best = undefined;
    best_dist = 999999999;

    foreach(corpse in corpses)
    {
        if(!isdefined(corpse) || !isdefined(corpse.origin) ||
           !isdefined(corpse.unitrigger) ||
           !isdefined(corpse.unitrigger.origin))
            continue;

        if(is_true(corpse.bot_auto_tpo_searched))
            continue;

        if(isdefined(corpse.bot_auto_tpo_owner) &&
           corpse.bot_auto_tpo_owner != self &&
           isdefined(corpse.bot_auto_tpo_until) &&
           gettime() < corpse.bot_auto_tpo_until &&
           isalive(corpse.bot_auto_tpo_owner))
            continue;

        dist = distancesquared(self.origin, corpse.origin);

        if(dist < best_dist)
        {
            best = corpse;
            best_dist = dist;
        }
    }

    return best;
}

bot_buried_search_next_corpse()
{
    if(flag("sq_tpo_found_item"))
        return true;

    corpse = self bot_buried_find_unsearched_corpse();

    if(!isdefined(corpse))
        return false;

    corpse.bot_auto_tpo_owner = self;
    corpse.bot_auto_tpo_until = gettime() + 7000;

    used = self scripts\zm\zm_bo2_bots::bot_quest_hold_use_target(
        corpse.unitrigger, "bot_buried_tpo_search", 42, 1.65);

    if(used)
        corpse.bot_auto_tpo_searched = 1;

    corpse.bot_auto_tpo_owner = undefined;
    corpse.bot_auto_tpo_until = 0;

    return used;
}

// Local objective release used when a weapon swap, death, or interrupted
// navigation exits an interaction unexpectedly.
bot_buried_release_objective(goal_name)
{
    if(isdefined(goal_name))
        self cancelgoal(goal_name);

    self clearlookat();
    self.bot.is_objective_using = undefined;
    self.bot.is_throwing_grenade = undefined;
}

bot_buried_objective_ready()
{
    if(!isdefined(self.bot) || !isalive(self))
        return false;

    if(is_true(self.bot.is_building) ||
       is_true(self.bot.is_crafting) ||
       is_true(self.bot.is_buying) ||
       is_true(self.bot.is_using_box) ||
       is_true(self.bot.is_reviving) ||
       is_true(self.bot.is_selfreviving) ||
       is_true(self.bot.is_throwing_grenade))
        return false;

    if(self isreloading() || self isswitchingweapons() || self isthrowinggrenade())
        return false;

    return self bot_objective_can_run();
}

bot_buried_request_buildable_refresh()
{
    self.bot.buildable_scan_after = 0;
    self.bot.craftable_scan_after = 0;
    self.bot.quest_scan_after = 0;
}

// A route's stock completion flag is only read here. Bots never set these
// flags; they wait for original map scripts to confirm the actual action.
bot_buried_mta_route_complete()
{
    if(flag("sq_is_max_tower_built"))
        return flag("sq_amplifiers_broken");

    if(flag("sq_is_ric_tower_built"))
        return flag("sq_amplifiers_on");

    return false;
}

bot_buried_tpo_ready_for_detonation()
{
    return flag("sq_tpo_players_in_position_for_time_warp") &&
           self hasweapon("time_bomb_detonator_zm") &&
           !is_true(level.bot_buried_tpo_detonate_started);
}

bot_buried_maxis_snapshot_ready()
{
    if(!isdefined(level.time_bomb_save_data) ||
       !isdefined(level.time_bomb_save_data.sq_data) ||
       !isdefined(level.time_bomb_save_data.sq_data.wisp_stage_complete))
        return false;

    return !level.time_bomb_save_data.sq_data.wisp_stage_complete &&
           isdefined(level.time_bomb_save_data.time_bomb_model) &&
           isdefined(level.time_bomb_save_data.time_bomb_model.origin);
}

bot_buried_maxis_wisp_save()
{
    if(!self hasweapon("time_bomb_zm"))
        return false;

    if(!isdefined(level.vh_wisp) || !isdefined(level.vh_wisp.origin))
        return false;

    if(distancesquared(self.origin, level.vh_wisp.origin) > 160 * 160)
    {
        self scripts\zm\zm_bo2_bots::bot_quest_move_to(
            level.vh_wisp.origin, "bot_buried_maxis_wisp_bomb", 160, 8000);
        return false;
    }

    self.bot.is_objective_using = 1;
    self switchtoweaponimmediate("time_bomb_zm");
    wait 0.3;
    self forcegrenadethrow();
    wait 0.9;
    self.bot.is_objective_using = undefined;

    if(self bot_buried_maxis_snapshot_ready())
    {
        level.bot_buried_wisp_timebomb_saved = 1;
        return true;
    }

    return false;
}

bot_buried_request_vulture_aid()
{
    if(self hasperk("specialty_nomotionsensor"))
        return true;

    self maps\mp\zombies\_zm_perks::give_perk("specialty_nomotionsensor", 0);
    return self hasperk("specialty_nomotionsensor");
}

bot_buried_mta_target_valid(amp)
{
    if(!isdefined(amp) || !isdefined(amp.origin))
        return false;

    if(!isdefined(amp.amplifier_state))
        return true;

    return amp.amplifier_state == "base";
}

bot_buried_tpo_timebomb_valid()
{
    if(!isdefined(level.time_bomb_save_data) ||
       !isdefined(level.time_bomb_save_data.time_bomb_model) ||
       !isdefined(level.time_bomb_save_data.time_bomb_model.origin))
        return false;

    volume = getent("sq_tpo_timebomb_volume", "targetname");

    if(!isdefined(volume))
        return false;

    return level.time_bomb_save_data.time_bomb_model istouching(volume);
}

// Additional conservative stage checks. Each helper returns false while the
// stock stage is still active; the caller simply tries again on the next tick.
bot_buried_bt_complete()
{
    return flag("sq_is_max_tower_built") || flag("sq_is_ric_tower_built");
}

bot_buried_gl_complete()
{
    return flag("sq_gl_lantern_aquired");
}

bot_buried_ftl_complete()
{
    return flag("ftl_lantern_charged");
}

bot_buried_ip_complete()
{
    return flag("sq_ip_puzzle_complete");
}

bot_buried_ows_complete()
{
    return flag("sq_ows_success");
}

bot_buried_tpo_complete()
{
    return flag("sq_tpo_generator_powered");
}

bot_buried_ts_complete()
{
    return flag("sq_sign_damaged");
}

bot_buried_ctw_complete()
{
    return flag("sq_wisp_success");
}

// Squad leader lease. A bot claims ownership only while alive; a replacement
// leader can take over as soon as the old lease expires.
bot_buried_claim_quest_lead()
{
    now = gettime();

    if(isdefined(level.bot_buried_quest_owner) &&
       level.bot_buried_quest_owner != self &&
       isalive(level.bot_buried_quest_owner) &&
       isdefined(level.bot_buried_quest_owner_until) &&
       now < level.bot_buried_quest_owner_until)
        return false;

    level.bot_buried_quest_owner = self;
    level.bot_buried_quest_owner_until = now + 30000;
    return true;
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
