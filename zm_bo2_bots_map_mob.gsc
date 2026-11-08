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
    // First Mob sidequest prerequisite: fill the stock wolf soul catchers by
    // killing zombies inside each catcher's native volume.
    if(!is_true(self.afterlife) && isdefined(level.soul_catchers) && isdefined(level.soul_catchers_vol))
    {
        for(i = 0; i < level.soul_catchers.size; i++)
        {
            catcher = level.soul_catchers[i];
            volume = level.soul_catchers_vol[i];
            if(!isdefined(catcher) || !isdefined(volume) || !isdefined(volume.origin))
                continue;
            if(!isdefined(catcher.is_charged) || !catcher.is_charged)
            {
                self scripts\zm\zm_bo2_bots::bot_quest_hold_in_volume(volume.origin, "bot_mob_wolf_souls", 230, 4.0);
                return true;
            }
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

    // Mob's final Nixie sequence begins only after all three plane trips and
    // the two sidequest prerequisites. The four stock codes are solved by
    // advancing the three real tube counters; the game's notifier raises the
    // corresponding nixie_<code> events and removes each code when accepted.
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
            level.bot_mob_final_nixie_started = 1;
            for(tube_index = 1; tube_index <= 3; tube_index++)
            {
                tube = getent("nixie_tube_" + tube_index, "targetname");
                if(!isdefined(tube) || !isdefined(tube.origin) ||
                   !isdefined(level.a_nixie_tube_code[tube_index]))
                    continue;

                // Inline the stock Nixie digit split. This avoids linking a
                // map-script helper that is not exported in some Plutonium builds.
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
                clicks = (desired_digit - current_digit + 10) % 10;

                for(click_index = 0; click_index < clicks; click_index++)
                {
                    before_digit = level.a_nixie_tube_code[tube_index];
                    self scripts\zm\zm_bo2_bots::bot_quest_use_target(tube, "bot_mob_nixie_tube", 32, 1, 1);
                    wait 0.25;
                    if(!isdefined(level.a_nixie_tube_code[tube_index]) ||
                       level.a_nixie_tube_code[tube_index] == before_digit)
                        break;
                }
            }
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
               self hasweapon("bouncing_tomahawk_zm"))
            {
                if(self scripts\zm\zm_bo2_bots::bot_quest_move_to(poster.origin, "bot_mob_spoon_poster", 220, 8000))
                {
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
                self scripts\zm\zm_bo2_bots::bot_quest_fire_at(spoon.origin, "lightning_hands_zm", "bot_mob_spoon_shock", 700, 8, 0.1);
                return true;
            }

            pickup = getent("pickup_spoon", "targetname");
            if(isdefined(pickup) && isdefined(pickup.origin) && self hasweapon("bouncing_tomahawk_zm"))
            {
                if(self scripts\zm\zm_bo2_bots::bot_quest_move_to(pickup.origin, "bot_mob_spoon_pickup", 180, 8000))
                {
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

    // Warden's Blundergat prerequisite: reveal each Afterlife macguffin with
    // Lightning Hands, then catch it with a real thrown Hell's Retriever.
    if(!flag("warden_blundergat_obtained") && self hasweapon("bouncing_tomahawk_zm") && is_true(self.afterlife))
    {
        if(isdefined(level.sq_bg_macguffins))
        {
            foreach(item in level.sq_bg_macguffins)
            {
                if(!isdefined(item) || !isdefined(item.origin))
                    continue;
                if(self hasweapon("lightning_hands_zm"))
                {
                    self scripts\zm\zm_bo2_bots::bot_quest_fire_at(item.origin, "lightning_hands_zm", "bot_mob_macguffin_reveal", 700, 5, 0.1);
                    wait 0.4;
                }
                self switchtoweaponimmediate("bouncing_tomahawk_zm");
                wait 0.2;
                self lookat(item.origin);
                self forcegrenadethrow();
                wait 1.0;
                self clearlookat();
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

