#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;

// -----------------------------------------------------------------------------
// Mob of the Dead map-specific bot logic (zm_prison).
// Shared bot systems and generic quest helpers remain in zm_bo2_bots.gsc.
// Edit this file for behavior that belongs only to this map.
// -----------------------------------------------------------------------------

bot_quest_mob_plane()
{
    // Living bots must enter through the same stock Afterlife kill trigger as
    // human players before they can operate the map's electrical objectives.
    if(!self bot_mob_is_afterlife() && self bot_mob_afterlife_entry_think())
        return;

    if(self bot_quest_mob_sidequests())
        return;

    if(is_true(self.afterlife))
    {
        if(flag("quest_completed_thrice") && flag("spoon_obtained") && flag("warden_blundergat_obtained") &&
           is_true(level.bot_mob_final_nixie_started) && is_true(level.bot_mob_audio_started) &&
           !isdefined(level.m_headphones))
        {
            final_trigger = getent("plane_fly_afterlife_trigger", "script_noteworthy");
            if(isdefined(final_trigger) && !is_true(level.bot_quest_final_flight_claimed))
            {
                level.bot_quest_final_flight_claimed = 1;
                self scripts\zm\zm_bo2_bots::bot_quest_use_target(final_trigger, "bot_mob_final_flight", 72, 5, 1);
                if(!isdefined(level.final_flight_activated) || !level.final_flight_activated)
                    level.bot_quest_final_flight_claimed = undefined;
            }
        }
        return;
    }

    // Everyone who boarded the plane must return from the bridge by using a
    // stock electric-chair trigger. Different bots reserve different chairs.
    if(isdefined(level.characters_in_nml) && isdefined(self.character_name) &&
       isinarray(level.characters_in_nml, self.character_name))
    {
        best_trigger = undefined;
        best_distance = 999999999;

        for(i = 1; i <= 4; i++)
        {
            chair_trigger = getent("trigger_electric_chair_" + i, "targetname");
            if(!isdefined(chair_trigger) || !isdefined(chair_trigger.origin))
                continue;

            if(isdefined(chair_trigger.bot_auto_quest_owner) && chair_trigger.bot_auto_quest_owner != self &&
               isdefined(chair_trigger.bot_auto_quest_until) && gettime() < chair_trigger.bot_auto_quest_until &&
               isalive(chair_trigger.bot_auto_quest_owner))
                continue;

            dist_sq = distancesquared(self.origin, chair_trigger.origin);
            if(dist_sq < best_distance && findpath(self.origin, chair_trigger.origin, undefined, 0, 1))
            {
                best_trigger = chair_trigger;
                best_distance = dist_sq;
            }
        }

        if(isdefined(best_trigger))
        {
            best_trigger.bot_auto_quest_owner = self;
            best_trigger.bot_auto_quest_until = gettime() + 12000;
            self scripts\zm\zm_bo2_bots::bot_quest_use_target(best_trigger, "bot_mob_bridge_chair", 48, 4, 1);
        }

        return;
    }

    if(isdefined(self.on_a_plane) && self.on_a_plane)
        return;

    if(!isdefined(level.n_plane_fuel_count) || level.n_plane_fuel_count != 5)
        return;

    // The plane's native trigger starts the flight and accepts each passenger
    // until the departure sequence begins. Bots board independently.
    if(flag("plane_built") && (!flag("plane_is_away") || !flag("plane_departed")))
    {
        if(isdefined(level.characters_in_nml) && level.characters_in_nml.size >= 4)
            return;

        fly_trigger = getent("plane_fly_trigger", "targetname");
        if(isdefined(fly_trigger))
            self scripts\zm\zm_bo2_bots::bot_quest_use_target(fly_trigger, "bot_mob_plane_board", 72, 4);
    }
}

bot_mob_final_fight_think()
{
    if(!isdefined(level.final_flight_activated) || !level.final_flight_activated ||
       !flag("plane_crashed") || !isdefined(level.final_flight_players) ||
       level.final_flight_players.size < 2 || !isdefined(level.zombie_team) ||
       (isdefined(level.winner) && level.winner != ""))
        return false;

    // Wait until the native final-stage handler has assigned Arlington to the
    // zombie team. This avoids running against players who are still in Afterlife.
    arlington = undefined;
    players = get_players();
    foreach(player in players)
    {
        if(isdefined(player) && isdefined(player.character_name) && player.character_name == "Arlington")
        {
            arlington = player;
            break;
        }
    }

    if(!isdefined(arlington) || !isdefined(arlington.team) || arlington.team != level.zombie_team ||
       is_true(self.afterlife) || self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
        return false;

    is_weasel = (self == arlington);
    target = undefined;
    best_distance = 999999999;

    foreach(player in players)
    {
        if(!isdefined(player) || player == self || !isalive(player) ||
           is_true(player.afterlife) || player maps\mp\zombies\_zm_laststand::player_is_in_laststand())
            continue;

        if(is_weasel)
        {
            if(player.character_name == "Arlington")
                continue;
        }
        else if(player != arlington)
            continue;

        distance_sq = distancesquared(self.origin, player.origin);
        if(distance_sq < best_distance && findpath(self.origin, player.origin, undefined, 0, 1))
        {
            best_distance = distance_sq;
            target = player;
        }
    }

    if(!isdefined(target))
        return true;

    if(best_distance > 300 * 300)
    {
        self addgoal(target.origin, 120, 2, "bot_mob_final_fight_chase");
        wait 0.25;
        self cancelgoal("bot_mob_final_fight_chase");
    }

    // Prefer a loaded primary; keep changing weapons if the active one is empty.
    weapon = self getcurrentweapon();
    ammo = 0;
    if(isdefined(weapon) && weapon != "none")
        ammo = self getweaponammoclip(weapon) + self getweaponammostock(weapon);

    if(!isdefined(weapon) || weapon == "none" || ammo <= 0 ||
       weapon == "knife_zm" || weapon == "knife_ballistic_zm")
    {
        primaries = self getweaponslistprimaries();
        foreach(candidate in primaries)
        {
            if(!isdefined(candidate) || candidate == "none")
                continue;
            candidate_ammo = self getweaponammoclip(candidate) + self getweaponammostock(candidate);
            if(candidate_ammo > 0)
            {
                weapon = candidate;
                self switchtoweaponimmediate(weapon);
                break;
            }
        }
    }

    if(best_distance < 100 * 100)
    {
        self lookat(target.origin + (0, 0, 36));
        self pressmelee();
        wait 0.35;
    }
    else if(isdefined(weapon) && weapon != "none")
    {
        self lookat(target.origin + (0, 0, 36));
        // Use the stock Zombies sight trace instead of the MP-only bot helper.
        if(sighttracepassed(self geteyeapprox(), target.origin + (0, 0, 36), 0, self))
            self pressattackbutton(0.2);
        else
            self pressattackbutton(0.1);
        wait 0.25;
    }

    self clearlookat();
    return true;
}

bot_quest_mob_sidequests()
{
    // Spread the squad across the three native wolf-soul volumes. A short
    // lease lets each bot work a different catcher instead of all three
    // converging on the first uncharged one.
    if(!is_true(self.afterlife) && isdefined(level.soul_catchers) && isdefined(level.soul_catchers_vol))
    {
        best_catcher = undefined;
        best_volume = undefined;
        best_catcher_index = -1;
        best_distance = 999999999;

        for(i = 0; i < level.soul_catchers.size; i++)
        {
            catcher = level.soul_catchers[i];
            volume = level.soul_catchers_vol[i];
            if(!isdefined(catcher) || !isdefined(volume) || !isdefined(volume.origin) ||
               (isdefined(catcher.is_charged) && catcher.is_charged))
                continue;

            if(isdefined(catcher.bot_mob_soul_owner) && catcher.bot_mob_soul_owner != self &&
               isdefined(catcher.bot_mob_soul_owner_until) && gettime() < catcher.bot_mob_soul_owner_until &&
               isalive(catcher.bot_mob_soul_owner))
                continue;

            distance_sq = distancesquared(self.origin, volume.origin);
            if(distance_sq >= best_distance ||
               !findpath(self.origin, volume.origin, undefined, 0, 1))
                continue;

            best_catcher = catcher;
            best_volume = volume;
            best_catcher_index = i;
            best_distance = distance_sq;
        }

        if(isdefined(best_catcher))
        {
            best_catcher.bot_mob_soul_owner = self;
            best_catcher.bot_mob_soul_owner_until = gettime() + 15000;
            self scripts\zm\zm_bo2_bots::bot_quest_hold_in_volume(
                best_volume.origin, "bot_mob_wolf_souls_" + best_catcher_index, 230, 4.0);
            return true;
        }
    }

    // Once the three wolf catchers are charged, collect the real Hell's
    // Retriever from its native pickup trigger. The stock trigger grants the
    // player's current_tomahawk_weapon and emits the acquisition event used by
    // the Warden Blundergat quest.
    if(!is_true(self.afterlife) && flag("soul_catchers_charged") &&
       !self hasweapon("bouncing_tomahawk_zm") && !self hasweapon("upgraded_tomahawk_zm"))
    {
        retriever = getent("retriever_pickup_trigger", "script_noteworthy");
        if(isdefined(retriever) && isdefined(retriever.origin))
        {
            self scripts\zm\zm_bo2_bots::bot_quest_use_target(retriever, "bot_mob_retriever_pickup", 80, 4);
            return true;
        }
    }

    // Do map-native Afterlife power objectives before continuing the sidequests.
    if(is_true(self.afterlife) && self bot_mob_afterlife_panel_think())
        return true;

    // Mob's main Nixie code is entered with Afterlife electricity, not the
    // use button. Reserve one controller so several ghosts cannot over-rotate
    // the same tube while the stock notifier is checking the three digits.
    if(is_true(self.afterlife) && flag("quest_completed_thrice") &&
       flag("spoon_obtained") && flag("warden_blundergat_obtained") &&
       isdefined(level.a_important_codes) && isdefined(level.a_nixie_tube_code) &&
       !isdefined(level.m_headphones))
    {
        final_codes = array(386, 481, 101, 872);
        active_code = undefined;
        foreach(code in final_codes)
        {
            if(isinarray(level.a_important_codes, code))
            {
                active_code = code;
                break;
            }
        }

        if(isdefined(active_code))
        {
            if(isdefined(level.bot_mob_nixie_owner) && level.bot_mob_nixie_owner != self &&
               isdefined(level.bot_mob_nixie_owner_until) && gettime() < level.bot_mob_nixie_owner_until &&
               isalive(level.bot_mob_nixie_owner))
                return true;

            level.bot_mob_nixie_owner = self;
            level.bot_mob_nixie_owner_until = gettime() + 12000;
            level.bot_mob_final_nixie_started = 1;

            for(tube_index = 1; tube_index <= 3; tube_index++)
            {
                tube = getent("nixie_tube_" + tube_index, "targetname");
                if(!isdefined(tube) || !isdefined(tube.origin) ||
                   !isdefined(level.a_nixie_tube_code[tube_index]))
                    continue;

                // Split the required three-digit code locally; no map-only
                // function reference is needed from this shared bot module.
                if(tube_index == 1)
                    desired_digit = int((active_code - active_code % 100) / 100);
                else if(tube_index == 2)
                {
                    digit_remainder = active_code % 100;
                    digit_remainder = digit_remainder - active_code % 10;
                    desired_digit = int(digit_remainder / 10);
                }
                else
                    desired_digit = active_code % 10;

                current_digit = level.a_nixie_tube_code[tube_index];
                if(current_digit == desired_digit)
                    continue;

                // The stock afterlife script advances a tube when it receives
                // damage from lightning_hands_zm. Fire one pulse, then let the
                // next think re-read the live digit before sending another.
                if(isdefined(tube.bot_mob_nixie_next_shot) &&
                   gettime() < tube.bot_mob_nixie_next_shot)
                    return true;

                tube.bot_mob_nixie_next_shot = gettime() + 650;
                self scripts\zm\zm_bo2_bots::bot_quest_fire_at(
                    tube.origin, "lightning_hands_zm", "bot_mob_nixie_tube", 180, 1, 0.12);
                return true;
            }

            // The code is already correct; keep the same controller alive
            // while the stock notifier emits nixie_<code> and removes it.
            return true;
        }
    }

    // After the four Nixie codes are accepted, Mob plays the six audio logs
    // at scripted stop locations. Each log except the first has a touch volume
    // beneath the moving headset; walking into that volume advances the stock
    // stage. The headset disappears when the whole sequence is complete.
    if(is_true(self.afterlife) && flag("quest_completed_thrice") &&
       flag("spoon_obtained") && flag("warden_blundergat_obtained") &&
       isdefined(level.m_headphones) && isdefined(level.m_headphones.origin))
    {
        level.bot_mob_audio_started = 1;
        audio_trigger_origin = level.m_headphones.origin - vectorscale((0, 0, 1), 80.0);
        self scripts\zm\zm_bo2_bots::bot_quest_move_to(audio_trigger_origin, "bot_mob_audio_log", 24, 7000);
        return true;
    }

    // Spoon route: normal-world bots knock down the poster after wolf-charge
    // completion; Afterlife bots shock the spoon and retrieve it with a real
    // Tomahawk throw. Keep the two dimensions in separate branches.
    if(!flag("spoon_obtained") && flag("soul_catchers_charged"))
    {
        if(!is_true(self.afterlife))
        {
            poster = getent("poster", "targetname");
            if(isdefined(poster) && isdefined(poster.origin) && isdefined(poster.health) && poster.health > 0 &&
               (self hasweapon("bouncing_tomahawk_zm") || self hasweapon("upgraded_tomahawk_zm")))
            {
                if(self scripts\zm\zm_bo2_bots::bot_quest_move_to(poster.origin, "bot_mob_spoon_poster", 220, 8000))
                {
                    if(self hasweapon("upgraded_tomahawk_zm"))
                        self switchtoweaponimmediate("upgraded_tomahawk_zm");
                    else
                        self switchtoweaponimmediate("bouncing_tomahawk_zm");
                    wait 0.25;
                    self lookat(poster.origin);
                    self forcegrenadethrow();
                    wait 0.8;
                    self clearlookat();
                }
                return true;
            }
        }
        else
        {
            spoon = getent("zap_spoon", "targetname");
            if(isdefined(spoon) && isdefined(spoon.origin) && self hasweapon("lightning_hands_zm"))
            {
                self scripts\zm\zm_bo2_bots::bot_quest_fire_at(spoon.origin, "lightning_hands_zm", "bot_mob_spoon_shock", 180, 1, 0.12);
                return true;
            }

            pickup = getent("pickup_spoon", "targetname");
            if(isdefined(pickup) && isdefined(pickup.origin) &&
               (self hasweapon("bouncing_tomahawk_zm") || self hasweapon("upgraded_tomahawk_zm")))
            {
                if(self scripts\zm\zm_bo2_bots::bot_quest_move_to(pickup.origin, "bot_mob_spoon_pickup", 180, 8000))
                {
                    if(self hasweapon("upgraded_tomahawk_zm"))
                        self switchtoweaponimmediate("upgraded_tomahawk_zm");
                    else
                        self switchtoweaponimmediate("bouncing_tomahawk_zm");
                    wait 0.25;
                    self lookat(pickup.origin);
                    self forcegrenadethrow();
                    wait 0.8;
                    self clearlookat();
                }
                return true;
            }
        }
    }

    // Warden's Blundergat prerequisite: reveal one native skull with
    // Lightning Hands, allow its stock hide/reveal cycle to finish, then move
    // close and catch it with the actual Hell's Retriever.
    if(!flag("warden_blundergat_obtained") &&
       (self hasweapon("bouncing_tomahawk_zm") || self hasweapon("upgraded_tomahawk_zm")) &&
       is_true(self.afterlife))
    {
        tomahawk_weapon = "bouncing_tomahawk_zm";
        if(self hasweapon("upgraded_tomahawk_zm"))
            tomahawk_weapon = "upgraded_tomahawk_zm";

        if(isdefined(level.sq_bg_macguffins))
        {
            foreach(item in level.sq_bg_macguffins)
            {
                if(!isdefined(item) || !isdefined(item.origin))
                    continue;

                if(isdefined(item.bot_mob_macguffin_owner) && item.bot_mob_macguffin_owner != self &&
                   isdefined(item.bot_mob_macguffin_owner_until) && gettime() < item.bot_mob_macguffin_owner_until &&
                   isalive(item.bot_mob_macguffin_owner))
                    continue;

                item.bot_mob_macguffin_owner = self;
                item.bot_mob_macguffin_owner_until = gettime() + 15000;

                if(!isdefined(item.bot_mob_macguffin_revealed) || !item.bot_mob_macguffin_revealed)
                {
                    if(isdefined(item.bot_mob_macguffin_retry_until) &&
                       gettime() < item.bot_mob_macguffin_retry_until)
                        return true;

                    if(self hasweapon("lightning_hands_zm"))
                    {
                        item.bot_mob_macguffin_retry_until = gettime() + 2200;
                        item.bot_mob_macguffin_reveal_until = gettime() + 1900;
                        if(self scripts\zm\zm_bo2_bots::bot_quest_fire_at(
                            item.origin, "lightning_hands_zm", "bot_mob_macguffin_reveal", 180, 1, 0.12))
                            item.bot_mob_macguffin_revealed = 1;
                        else
                        {
                            item.bot_mob_macguffin_retry_until = gettime() + 2500;
                            item.bot_mob_macguffin_reveal_until = undefined;
                        }
                        return true;
                    }
                }

                if(isdefined(item.bot_mob_macguffin_reveal_until) &&
                   gettime() < item.bot_mob_macguffin_reveal_until)
                    return true;

                if(!self scripts\zm\zm_bo2_bots::bot_quest_move_to(
                    item.origin, "bot_mob_macguffin_approach", 72, 7000))
                {
                    item.bot_mob_macguffin_retry_until = gettime() + 3000;
                    item.bot_mob_macguffin_reveal_until = undefined;
                    item.bot_mob_macguffin_revealed = undefined;
                    return true;
                }

                self switchtoweaponimmediate(tomahawk_weapon);
                wait 0.2;
                self lookat(item.origin);
                self forcegrenadethrow();
                wait 0.35;
                self clearlookat();
                item.bot_mob_macguffin_retry_until = gettime() + 5000;
                item.bot_mob_macguffin_reveal_until = undefined;
                item.bot_mob_macguffin_revealed = undefined;
                return true;
            }
        }
    }

    if(!flag("warden_blundergat_obtained") && isdefined(level.sq_bg_macguffins) && level.sq_bg_macguffins.size == 0)
    {
        reward = getent("sq_bg_reward_pickup", "targetname");
        if(isdefined(reward) && isdefined(reward.origin))
        {
            self scripts\zm\zm_bo2_bots::bot_quest_use_target(reward, "bot_mob_blundergat_reward", 80, 4, 1);
            return true;
        }
    }

    return false;
}

// Find a map-native Afterlife interaction by the event its stock script
// publishes. The stock _zm_afterlife handler owns the damage callback.
bot_mob_afterlife_find_interact(event_name)
{
    interactions = getentarray("afterlife_interact", "targetname");
    foreach(interaction in interactions)
    {
        if(isdefined(interaction) && isdefined(interaction.origin) &&
           isdefined(interaction.script_string) && interaction.script_string == event_name)
            return interaction;
    }
    return undefined;
}

// Send a single Lightning Hands pulse to a stock damage-driven panel. The
// entity lease prevents the whole squad from repeatedly firing the same panel.
bot_mob_afterlife_zap_target(target, goal_name)
{
    if(!isdefined(target) || !isdefined(target.origin) ||
       !self hasweapon("lightning_hands_zm"))
        return false;

    now = gettime();
    if(isdefined(target.bot_mob_afterlife_zap_owner) &&
       target.bot_mob_afterlife_zap_owner != self &&
       isdefined(target.bot_mob_afterlife_zap_until) && now < target.bot_mob_afterlife_zap_until &&
       isalive(target.bot_mob_afterlife_zap_owner))
        return false;

    if(isdefined(target.bot_mob_afterlife_zap_owner) &&
       target.bot_mob_afterlife_zap_owner == self &&
       isdefined(target.bot_mob_afterlife_zap_next) && now < target.bot_mob_afterlife_zap_next)
        return true;

    target.bot_mob_afterlife_zap_owner = self;
    target.bot_mob_afterlife_zap_until = now + 10000;
    target.bot_mob_afterlife_zap_next = now + 1600;

    if(!self scripts\zm\zm_bo2_bots::bot_quest_fire_at(
        target.origin, "lightning_hands_zm", goal_name, 180, 1, 0.12))
    {
        target.bot_mob_afterlife_zap_owner = undefined;
        target.bot_mob_afterlife_zap_until = 0;
        target.bot_mob_afterlife_zap_next = 0;
        return false;
    }

    return true;
}

// Work on real Mob Afterlife targets in dependency order: opening power,
// lowering the Master Key, the three generator panels, docks, then laundry.
bot_mob_afterlife_panel_think()
{
    if(!self hasweapon("lightning_hands_zm"))
        return false;

    power_door = getent("powerup_door", "targetname");
    if(isdefined(power_door) &&
       (!isdefined(power_door.opened) || !power_door.opened))
    {
        target = self bot_mob_afterlife_find_interact("intro_powerup_activate");
        if(isdefined(target) && self bot_mob_afterlife_zap_target(target, "bot_mob_intro_power"))
            return true;
    }

    if(!is_true(level getclientfield("master_key_is_lowered")) &&
       isdefined(level.is_master_key_west))
    {
        if(is_true(level.is_master_key_west))
            pulley = getent("master_key_pulley_west", "targetname");
        else
            pulley = getent("master_key_pulley_east", "targetname");

        if(isdefined(pulley) && self bot_mob_afterlife_zap_target(pulley, "bot_mob_master_key_pulley"))
            return true;
    }

    if(!flag("generator_challenge_completed") &&
       isdefined(level.n_generator_panels_active) && level.n_generator_panels_active < 3)
    {
        for(panel_index = 1; panel_index <= 3; panel_index++)
        {
            panel = getent("generator_panel_" + panel_index, "targetname");
            if(!isdefined(panel) || !isdefined(panel.origin))
                continue;
            if(isdefined(panel.model) && panel.model == "p6_zm_al_power_station_panels_03")
                continue;

            if(self bot_mob_afterlife_zap_target(panel, "bot_mob_generator_panel"))
                return true;
        }
    }

    if(!flag("docks_outer_gate_open") && !flag("docks_gates_remain_open"))
    {
        docks_panel = getent("docks_panel", "targetname");
        if(isdefined(docks_panel) && self bot_mob_afterlife_zap_target(docks_panel, "bot_mob_docks_gate"))
            return true;
    }

    // The dryer remains disabled until the stock Afterlife switch event fires.
    if(!is_true(level getclientfield("dryer_stage")))
    {
        dryer_switch = self bot_mob_afterlife_find_interact("laundry_power_switch_afterlife");
        if(isdefined(dryer_switch) && self bot_mob_afterlife_zap_target(dryer_switch, "bot_mob_laundry_power"))
            return true;
    }

    return false;
}

// Mob's stock Afterlife kill points are registered as static unitrigger
// stubs. The unitrigger manager normally filters scripted test-client bots
// through is_player_valid(); explicitly allow bots on these specific stubs.
bot_mob_allow_afterlife_bot_triggers()
{
    triggers = getstructarray("afterlife_trigger", "targetname");
    if(!isdefined(triggers))
        return;

    foreach(trigger_struct in triggers)
    {
        if(isdefined(trigger_struct) && isdefined(trigger_struct.unitrigger_stub))
            trigger_struct.unitrigger_stub.ignore_player_valid = 1;
    }
}

// Check whether a real Mob objective still needs the ghost form. This stops
// bots from spending their Afterlife life after all electrical/ghost quests
// have already been completed.
bot_mob_afterlife_needs_entry()
{
    power_door = getent("powerup_door", "targetname");
    if(isdefined(power_door) && (!isdefined(power_door.opened) || !power_door.opened))
        return true;

    if(isdefined(level.is_master_key_west))
    {
        if(is_true(level.is_master_key_west))
            pulley = getent("master_key_pulley_west", "targetname");
        else
            pulley = getent("master_key_pulley_east", "targetname");

        if(isdefined(pulley) && isdefined(pulley.model) &&
           pulley.model != "p6_zm_al_power_station_panels_03")
            return true;
    }

    if(!flag("generator_challenge_completed") &&
       isdefined(level.n_generator_panels_active) && level.n_generator_panels_active < 3)
        return true;

    if(!flag("docks_outer_gate_open") && !flag("docks_gates_remain_open") &&
       isdefined(getent("docks_panel", "targetname")))
        return true;

    if(flag("soul_catchers_charged") && !flag("spoon_obtained"))
        return true;

    if(!flag("warden_blundergat_obtained") &&
       isdefined(level.sq_bg_macguffins) && level.sq_bg_macguffins.size > 0)
        return true;

    if(flag("quest_completed_thrice") && flag("spoon_obtained") &&
       flag("warden_blundergat_obtained") &&
       isdefined(level.a_important_codes) && level.a_important_codes.size > 0 &&
       !isdefined(level.m_headphones))
        return true;

    if(isdefined(level.m_headphones) && isdefined(level.m_headphones.origin))
        return true;

    return false;
}

// Use the real ZM_PRISON_AFTERLIFE_KILL unitrigger. Its stock callback
// consumes the life and starts Afterlife; the bot never edits those states.
// Mob's trigger is created by _zm_unitrigger and its callback owns the real
// life consumption / afterlife_laststand transition. Sending its native
// "trigger" notification avoids the unreliable bot look-at + use-button path.
// Activate the bot's actual per-player stock Afterlife unitrigger.
// Mob's callback consumes the life and starts Afterlife; the bot never edits
// those states or relies on scripted look-at/use-button input.
// Activate the bot's actual per-player stock Afterlife unitrigger.
// Mob's callback consumes the life and starts Afterlife; the bot never edits
// those states or relies on scripted look-at/use-button input.
bot_mob_activate_afterlife_trigger(trigger_struct, goal_name)
{
    if(!isdefined(trigger_struct) || !isdefined(trigger_struct.origin) ||
       !isdefined(trigger_struct.unitrigger_stub))
        return false;

    if(!isdefined(goal_name))
        goal_name = "bot_mob_afterlife_kill";

    stub = trigger_struct.unitrigger_stub;
    unitrigger_path = "maps/mp/zombies/_zm_unitrigger";
    unitrigger_trigger_func = getfunction(unitrigger_path, "unitrigger_trigger");
    unitrigger_build_func = getfunction(unitrigger_path, "build_trigger_from_unitrigger_stub");
    unitrigger_visibility_func = getfunction(unitrigger_path, "assess_and_apply_visibility");
    unitrigger_cleanup_func = getfunction(unitrigger_path, "cleanup_trigger");

    if(!isdefined(unitrigger_trigger_func) || !isdefined(unitrigger_build_func) ||
       !isdefined(unitrigger_visibility_func) || !isdefined(unitrigger_cleanup_func))
        return false;

    if(!findpath(self.origin, trigger_struct.origin, undefined, 0, 1))
        return false;

    // Stop inside the stock 36-unit use radius and the unitrigger manager's
    // 42-unit vertical scan band (which measures from player origin + 35).
    self addgoal(trigger_struct.origin, 20, 2, goal_name);
    deadline = gettime() + 10000;
    arrived = false;

    while(gettime() < deadline)
    {
        if(is_true(self.afterlife))
        {
            self cancelgoal(goal_name);
            return true;
        }

        if(!self bot_objective_can_run() ||
           !isdefined(trigger_struct) || !isdefined(trigger_struct.origin))
            break;

        if(distancesquared(self.origin, trigger_struct.origin) <= 20 * 20)
        {
            arrived = true;
            break;
        }

        wait 0.1;
    }

    self cancelgoal(goal_name);
    if(!arrived || is_true(self.afterlife))
        return is_true(self.afterlife);

    self.bot.is_objective_using = 1;
    player_num = self getentitynumber();

    if(!isdefined(level._unitriggers) || !isdefined(level._unitriggers.trigger_pool))
    {
        self.bot.is_objective_using = undefined;
        return false;
    }

    use_trigger = undefined;
    if(isdefined(stub.playertrigger) && isdefined(stub.playertrigger[player_num]))
        use_trigger = stub [[ unitrigger_trigger_func ]](self);

    current_trigger = level._unitriggers.trigger_pool[player_num];
    if(isdefined(current_trigger) && current_trigger != use_trigger)
        current_trigger [[ unitrigger_cleanup_func ]](current_trigger, self);

    // The stock manager keeps one active trigger per player. Rebuild its slot
    // with this exact Afterlife stub if a nearby perk/debris trigger occupied it.
    if(!isdefined(use_trigger))
    {
        use_trigger = stub [[ unitrigger_build_func ]](self);
        if(!isdefined(use_trigger))
        {
            self.bot.is_objective_using = undefined;
            return false;
        }
    }

    // Run the same visibility gate the stock manager uses; this also starts
    // the original afterlife_trigger_think callback on the trigger entity.
    if(!isdefined(use_trigger.thread_running) || !use_trigger.thread_running)
    {
        is_visible = use_trigger [[ unitrigger_visibility_func ]](use_trigger, stub, self, 0);
        if(!is_visible)
        {
            use_trigger [[ unitrigger_cleanup_func ]](use_trigger, self);
            self.bot.is_objective_using = undefined;
            return false;
        }
    }

    level._unitriggers.trigger_pool[player_num] = use_trigger;

    // The stock callback waits for round logic before listening for use.
    // Do not send the notification until that wait is over and its thread is ready.
    if(!flag("start_zombie_round_logic"))
    {
        self.bot.is_objective_using = undefined;
        return false;
    }

    wait 0.1;
    if(!is_true(self.afterlife) && isdefined(use_trigger.thread_running) &&
       use_trigger.thread_running)
    {
        use_trigger notify("trigger", self);
        wait 0.25;
    }

    self.bot.is_objective_using = undefined;
    return is_true(self.afterlife);
}

bot_mob_afterlife_entry_think()
{
    if(!isdefined(self.lives) || self.lives <= 0 ||
       self is_reviving_any() ||
       self maps\mp\zombies\_zm_laststand::player_is_in_laststand())
        return false;

    if(isdefined(self.bot_mob_afterlife_retry_until) &&
       gettime() < self.bot_mob_afterlife_retry_until)
        return false;

    if(!self bot_mob_afterlife_needs_entry())
        return false;

    self bot_mob_allow_afterlife_bot_triggers();

    triggers = getstructarray("afterlife_trigger", "targetname");
    if(!isdefined(triggers) || triggers.size == 0)
        return false;

    best_trigger = undefined;
    best_distance = 999999999;

    foreach(trigger_struct in triggers)
    {
        if(!isdefined(trigger_struct) || !isdefined(trigger_struct.origin) ||
           !isdefined(trigger_struct.unitrigger_stub))
            continue;

        // Reapply the bot exception here in case a round transition rebuilt
        // or re-registered the stock trigger stub.
        trigger_struct.unitrigger_stub.ignore_player_valid = 1;

        if(isdefined(trigger_struct.bot_mob_entry_owner) &&
           trigger_struct.bot_mob_entry_owner != self &&
           isdefined(trigger_struct.bot_mob_entry_until) &&
           gettime() < trigger_struct.bot_mob_entry_until &&
           isalive(trigger_struct.bot_mob_entry_owner))
            continue;

        distance_sq = distancesquared(self.origin, trigger_struct.origin);
        if(distance_sq >= best_distance ||
           !findpath(self.origin, trigger_struct.origin, undefined, 0, 1))
            continue;

        best_trigger = trigger_struct;
        best_distance = distance_sq;
    }

    if(!isdefined(best_trigger))
        return false;

    best_trigger.bot_mob_entry_owner = self;
    best_trigger.bot_mob_entry_until = gettime() + 15000;

    if(self bot_mob_activate_afterlife_trigger(best_trigger, "bot_mob_afterlife_kill"))
    {
        self.bot_mob_afterlife_retry_until = undefined;
        best_trigger.bot_mob_entry_owner = undefined;
        best_trigger.bot_mob_entry_until = undefined;
        return true;
    }

    // The stock trigger did not consume the bot's life; release the claim so
    // another bot can try a different entrance while this bot waits briefly.
    self.bot_mob_afterlife_retry_until = gettime() + 3000;
    best_trigger.bot_mob_entry_owner = undefined;
    best_trigger.bot_mob_entry_until = undefined;
    return false;
}

bot_mob_is_cell_block(origin)
{
	cell_1 = (1548.58, 10476.6, 1336.13);
	cell_2 = (1425.54, 9251.54, 1336.13);
	cell_3 = (1474.05, 9555.64, 1336.13);

	if(distance(origin, cell_1) < 100)
		return true;
	
	if(distance(origin, cell_2) < 100)
		return true;
	
	if(distance(origin, cell_3) < 100)
		return true;

	return false;
}
bot_mob_is_afterlife()
{
	return getdvar("mapname") == "zm_prison" && is_true(self.afterlife);
}

bot_mob_grant_shield(current_weapon)
{
	self scripts\zm\zm_bo2_bots::bot_grant_map_shield("alcatraz_shield_zm", current_weapon);
}

