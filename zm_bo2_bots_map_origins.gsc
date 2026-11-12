#include common_scripts\utility;
#include maps\mp\_utility;
#include maps\mp\zombies\_zm_utility;

bot_origins_install_capture_zone_hook()
{
    if(isdefined(level.bot_origins_capture_zone_hooked) &&
       level.bot_origins_capture_zone_hooked)
        return true;

    capture_players_func = getfunction(
        "maps/mp/zm_tomb_capture_zones", "get_players_in_capture_zone");

    if(!isdefined(capture_players_func))
        return false;

    // Keep the stock filter for human players, but count living Origins bots.
    replacefunc(capture_players_func, ::bot_origins_get_players_in_capture_zone);
    level.bot_origins_capture_zone_hooked = 1;
    return true;
}

bot_origins_get_players_in_capture_zone()
{
    players_in_zone = [];
    players = get_players();

    foreach(player in players)
    {
        if(!isdefined(player) || !isdefined(player.origin))
            continue;

        valid_player = is_player_valid(player);

        if(!valid_player && isdefined(player.pers) && isdefined(player.pers["isbot"]))
        {
            valid_player = isalive(player) &&
                           isdefined(player.sessionstate) && player.sessionstate == "playing" &&
                           !player maps\mp\zombies\_zm_laststand::player_is_in_laststand() &&
                           !player is_reviving_any();
        }

        if(valid_player &&
           distance2dsquared(player.origin, self.origin) < 48400 &&
           player.origin[2] > self.origin[2] - 20)
            players_in_zone[players_in_zone.size] = player;
    }

    return players_in_zone;
}

bot_origins_hold_generator_zone(zone)
{
    if(!isdefined(zone) || !isdefined(zone.origin))
        return false;

    goal_name = "bot_origins_generator_anchor";
    goal_mode = "";
    hold_deadline = gettime() + 180000;

    // Keep the movement/quest lock separate from the combat-action lock.
    // The bot must continue shooting while it defends the generator.
    self.bot.is_holding_generator = 1;

    // The stock capture radius is 220 units in 2D and excludes players whose
    // Z is more than 20 units below the zone origin. Stay inside 180 units.
    // Initial captures end when ownership flips; recaptures must keep
    // defenders inside even though the generator is still player-controlled.
    while(isalive(self) && gettime() < hold_deadline &&
          (flag("zone_capture_in_progress") || zone ent_flag("zone_contested")) &&
          (zone ent_flag("zone_contested") || !zone ent_flag("player_controlled")))
    {
        distance_sq = distance2dsquared(self.origin, zone.origin);
        below_floor = self.origin[2] <= zone.origin[2] - 20;

        if(distance_sq > 180 * 180 || below_floor)
        {
            if(goal_mode != "move")
            {
                self addgoal(zone.origin, 145, 1, goal_name);
                goal_mode = "move";
            }
        }
        else if(goal_mode != "hold")
        {
            self addgoal(zone.origin, 180, 1, goal_name);
            goal_mode = "hold";
        }

        wait 0.2;
    }

    self cancelgoal(goal_name);
    self.bot.is_holding_generator = undefined;

    if(zone ent_flag("player_controlled"))
    {
        if(isdefined(level.bot_origins_generator_target) &&
           level.bot_origins_generator_target == zone)
            level.bot_origins_generator_target = undefined;
        if(isdefined(level.bot_origins_generator_owner) &&
           level.bot_origins_generator_owner == self)
            level.bot_origins_generator_owner = undefined;
        level.bot_origins_generator_owner_until = 0;
        level.bot_origins_generator_start_wait_until = 0;
        return true;
    }

    if(!flag("zone_capture_in_progress") && !zone ent_flag("zone_contested"))
    {
        if(isdefined(level.bot_origins_generator_target) &&
           level.bot_origins_generator_target == zone)
            level.bot_origins_generator_target = undefined;
        if(isdefined(level.bot_origins_generator_owner) &&
           level.bot_origins_generator_owner == self)
            level.bot_origins_generator_owner = undefined;
        level.bot_origins_generator_owner_until = 0;
        level.bot_origins_generator_start_wait_until = gettime() + 2500;
    }

    return false;
}

// -----------------------------------------------------------------------------
// Origins map-specific bot logic (zm_tomb).
// Shared bot systems and generic quest helpers remain in zm_bo2_bots.gsc.
// Edit this file for behavior that belongs only to this map.
// -----------------------------------------------------------------------------

// -----------------------------------------------------------------------------
// Origins opening and squad progression helpers.
// The stock map owns the actual pickup, capture, craft and teleport callbacks;
// these routines navigate bots to those real triggers instead of faking flags.
// -----------------------------------------------------------------------------

// Origins-only stock file. A direct file::function reference is resolved when the
// script loads, so it fails with "Unresolved external" on every map that does not
// ship _zm_weap_one_inch_punch. getfunction() resolves it at runtime instead and
// returns undefined when the file is not loaded.
bot_origins_punch_func(name)
{
    if(!isdefined(level.bot_origins_punch_funcs))
        level.bot_origins_punch_funcs = [];
    if(!isdefined(level.bot_origins_punch_funcs[name]))
        level.bot_origins_punch_funcs[name] = getfunction("maps/mp/zombies/_zm_weap_one_inch_punch", name);
    return level.bot_origins_punch_funcs[name];
}

bot_origins_spawn_private_shovel()
{
    // The stock map spawns a finite number of shovel entities. With more
    // scripted bots than available pickups, a bot can otherwise wait forever
    // after another player has claimed the last real shovel. Create one
    // additional stock-style pickup for this bot only when no map shovel
    // remains; the native shovel trigger still awards dig_vars and handles
    // the pickup exactly as it does for a normal player.
    if(isdefined(self.bot_origins_private_shovel) &&
       isdefined(self.bot_origins_private_shovel.origin))
    {
        if(isdefined(level._unitriggers) && isdefined(level._unitriggers.trigger_stubs))
        {
            foreach(existing_stub in level._unitriggers.trigger_stubs)
            {
                if(isdefined(existing_stub) &&
                   isdefined(existing_stub.e_shovel) &&
                   existing_stub.e_shovel == self.bot_origins_private_shovel &&
                   (!isdefined(existing_stub.registered) || existing_stub.registered))
                    return existing_stub;
            }
        }

        self.bot_origins_private_shovel delete();
        self.bot_origins_private_shovel = undefined;
    }

    generate_shovel_func = getfunction("maps/mp/zm_tomb_dig", "generate_shovel_unitrigger");
    if(!isdefined(generate_shovel_func))
        return undefined;

    m_shovel = spawn("script_model", self.origin);
    if(!isdefined(m_shovel))
        return undefined;

    m_shovel.angles = self.angles;
    m_shovel setmodel("p6_zm_tm_shovel");
    self.bot_origins_private_shovel = m_shovel;

    self [[ generate_shovel_func ]](m_shovel);

    if(isdefined(level._unitriggers) && isdefined(level._unitriggers.trigger_stubs))
    {
        foreach(new_stub in level._unitriggers.trigger_stubs)
        {
            if(isdefined(new_stub) && isdefined(new_stub.e_shovel) &&
               new_stub.e_shovel == m_shovel)
            {
                new_stub.ignore_player_valid = 1;
                return new_stub;
            }
        }
    }

    m_shovel delete();
    self.bot_origins_private_shovel = undefined;
    return undefined;
}

bot_quest_origins_shovel()
{
    // Match the fields normally initialized by the stock player-connect hook.
    if(!isdefined(self.dig_vars))
        self.dig_vars = [];

    if(!isdefined(self.dig_vars["has_shovel"]))
        self.dig_vars["has_shovel"] = 0;
    if(!isdefined(self.dig_vars["has_upgraded_shovel"]))
        self.dig_vars["has_upgraded_shovel"] = 0;
    if(!isdefined(self.dig_vars["has_helmet"]))
        self.dig_vars["has_helmet"] = 0;
    if(!isdefined(self.dig_vars["n_spots_dug"]))
        self.dig_vars["n_spots_dug"] = 0;
    if(!isdefined(self.dig_vars["n_losing_streak"]))
        self.dig_vars["n_losing_streak"] = 0;

    if(self.dig_vars["has_shovel"])
    {
        self.bot_origins_private_shovel = undefined;
        return false;
    }

    if(!isdefined(level._unitriggers) || !isdefined(level._unitriggers.trigger_stubs))
        return false;

    best_stub = undefined;
    best_shovel = undefined;
    best_distance = 999999999;

    foreach(stub in level._unitriggers.trigger_stubs)
    {
        if(!isdefined(stub) || !isdefined(stub.e_shovel) ||
           !isdefined(stub.e_shovel.origin) || !isdefined(stub.origin))
            continue;

        if(isdefined(stub.registered) && !stub.registered)
            continue;

        // Reserve a specific physical shovel so all bots do not chase the same
        // per-player trigger and leave the others standing without a pickup.
        if(isdefined(stub.bot_origins_shovel_owner) &&
           stub.bot_origins_shovel_owner != self &&
           isdefined(stub.bot_origins_shovel_owner_until) &&
           gettime() < stub.bot_origins_shovel_owner_until &&
           isalive(stub.bot_origins_shovel_owner))
            continue;

        distance_sq = distancesquared(self.origin, stub.e_shovel.origin);
        if(distance_sq >= best_distance ||
           !findpath(self.origin, stub.e_shovel.origin, undefined, 0, 1))
            continue;

        best_stub = stub;
        best_shovel = stub.e_shovel;
        best_distance = distance_sq;
    }

    // If all original pickup entities have already been consumed, generate a
    // private copy with the same stock trigger callback for this remaining bot.
    if(!isdefined(best_stub) || !isdefined(best_shovel))
    {
        best_stub = self bot_origins_spawn_private_shovel();
        if(isdefined(best_stub) && isdefined(best_stub.e_shovel) &&
           isdefined(best_stub.e_shovel.origin))
            best_shovel = best_stub.e_shovel;
    }

    if(!isdefined(best_stub) || !isdefined(best_shovel))
        return false;

    best_stub.ignore_player_valid = 1;
    best_stub.bot_origins_shovel_owner = self;
    best_stub.bot_origins_shovel_owner_until = gettime() + 15000;

    if(distancesquared(self.origin, best_shovel.origin) > 36 * 36)
    {
        arrived = self scripts\zm\zm_bo2_bots::bot_quest_move_to(
            best_shovel.origin, "bot_origins_shovel_pickup", 30, 9000);

        if(!arrived)
        {
            best_stub.bot_origins_shovel_owner = undefined;
            best_stub.bot_origins_shovel_owner_until = 0;
            return false;
        }
    }

    self.bot.is_objective_using = 1;
    self lookat(best_stub.origin);

    unitrigger_trigger_func = getfunction("maps/mp/zombies/_zm_unitrigger", "unitrigger_trigger");

    // Give the stock unitrigger manager a moment to create this bot's trigger,
    // then notify that trigger directly if scripted use input is not dispatched.
    for(i = 0; i < 16; i++)
    {
        if(!isalive(self) || self.dig_vars["has_shovel"] ||
           !isdefined(best_stub.e_shovel))
            break;

        if(!self isonground() || self isonladder() || self ismantling())
        {
            wait 0.1;
            continue;
        }

        player_trigger = undefined;
        if(isdefined(unitrigger_trigger_func))
            player_trigger = best_stub [[ unitrigger_trigger_func ]](self);

        if(isdefined(player_trigger) &&
           isdefined(player_trigger.thread_running) &&
           player_trigger.thread_running &&
           player_trigger.parent_player == self)
        {
            player_trigger notify("trigger", self);
            wait 0.2;
        }
        else
        {
            self pressusebutton(0.2);
            wait 0.15;
        }
    }

    self clearlookat();
    self.bot.is_objective_using = undefined;

    if(isdefined(best_stub))
    {
        best_stub.bot_origins_shovel_owner = undefined;
        best_stub.bot_origins_shovel_owner_until = 0;
    }

    // Return true only when the native shovel callback actually gave the bot
    // the shovel. A failed attempt must not block generator/dig objectives.
    return self.dig_vars["has_shovel"];
}

bot_quest_origins_generators()
{
    if(!flag("capture_zones_init_done") || !isdefined(level.zone_capture) ||
       !isdefined(level.zone_capture.zones))
        return false;

    // Service contested generators before checking all_zones_captured.
    // This also handles a generator that zombies are trying to recapture.
    active_zone = undefined;

    if(flag("zone_capture_in_progress") &&
       isdefined(level.bot_origins_generator_target) &&
       isdefined(level.bot_origins_generator_target.origin) &&
       !level.bot_origins_generator_target ent_flag("player_controlled"))
        active_zone = level.bot_origins_generator_target;

    zone_keys = getarraykeys(level.zone_capture.zones);
    if(!isdefined(active_zone))
    {
        foreach(zone_key in zone_keys)
        {
            zone = level.zone_capture.zones[zone_key];
            if(isdefined(zone) && isdefined(zone.origin) && zone ent_flag("zone_contested"))
            {
                active_zone = zone;
                break;
            }
        }
    }

    if(isdefined(active_zone) && isdefined(active_zone.origin))
    {
        self bot_origins_hold_generator_zone(active_zone);
        return true;
    }

    if(flag("zone_capture_in_progress"))
        return true;

    if(flag("all_zones_captured"))
        return false;

    if(isdefined(level.bot_origins_generator_target))
    {
        if(level.bot_origins_generator_target ent_flag("player_controlled"))
        {
            level.bot_origins_generator_target = undefined;
            level.bot_origins_generator_owner = undefined;
            level.bot_origins_generator_owner_until = 0;
            level.bot_origins_generator_start_wait_until = 0;
        }
        else if(isdefined(level.bot_origins_generator_start_wait_until) &&
                gettime() >= level.bot_origins_generator_start_wait_until)
        {
            level.bot_origins_generator_target = undefined;
            level.bot_origins_generator_owner = undefined;
            level.bot_origins_generator_owner_until = 0;
            level.bot_origins_generator_start_wait_until = 0;
        }
    }

    if(isdefined(level.bot_origins_generator_owner) &&
       level.bot_origins_generator_owner == self &&
       isdefined(level.bot_origins_generator_start_wait_until) &&
       gettime() < level.bot_origins_generator_start_wait_until)
        return true;

    if(isdefined(level.bot_origins_generator_owner) && level.bot_origins_generator_owner != self &&
       isalive(level.bot_origins_generator_owner) && isdefined(level.bot_origins_generator_owner_until) &&
       gettime() < level.bot_origins_generator_owner_until)
        return false;

    get_cost_func = getfunction("maps/mp/zm_tomb_capture_zones", "get_generator_capture_start_cost");
    if(isdefined(get_cost_func))
        cost = [[ get_cost_func ]]();
    else
        cost = 200 * get_players().size;

    if(!isdefined(self.score) || self.score < cost)
        return false;

    best_zone = undefined;
    best_distance = 999999999;

    foreach(zone_key in zone_keys)
    {
        zone = level.zone_capture.zones[zone_key];
        if(!isdefined(zone) || !isdefined(zone.origin) ||
           zone ent_flag("player_controlled") || zone ent_flag("zone_contested"))
            continue;

        distance_sq = distancesquared(self.origin, zone.origin);
        if(distance_sq >= best_distance ||
           !findpath(self.origin, zone.origin, undefined, 0, 1))
            continue;

        best_zone = zone;
        best_distance = distance_sq;
    }

    if(!isdefined(best_zone))
        return false;

    level.bot_origins_generator_owner = self;
    level.bot_origins_generator_target = best_zone;
    level.bot_origins_generator_owner_until = gettime() + 15000;

    arrived = self scripts\zm\zm_bo2_bots::bot_quest_move_to(
        best_zone.origin, "bot_origins_generator_activate", 64, 12000);

    if(!arrived ||
       !isdefined(self.score) || self.score < cost ||
       distancesquared(self.origin, best_zone.origin) > 72 * 72)
    {
        level.bot_origins_generator_owner = undefined;
        level.bot_origins_generator_target = undefined;
        level.bot_origins_generator_owner_until = 0;
        return false;
    }

    self.bot.is_objective_using = 1;
    self lookat(best_zone.origin + (0, 0, 16));

    if(!flag("zone_capture_in_progress") &&
       !best_zone ent_flag("zone_contested") &&
       !best_zone ent_flag("player_controlled"))
        best_zone notify("start_generator_capture", self);

    self clearlookat();
    self.bot.is_objective_using = undefined;

    start_deadline = gettime() + 2500;
    while(gettime() < start_deadline &&
          !flag("zone_capture_in_progress") &&
          !best_zone ent_flag("zone_contested") &&
          !best_zone ent_flag("player_controlled"))
        wait 0.1;

    if(!flag("zone_capture_in_progress") &&
       !best_zone ent_flag("zone_contested") &&
       !best_zone ent_flag("player_controlled"))
    {
        level.bot_origins_generator_owner = undefined;
        level.bot_origins_generator_target = undefined;
        level.bot_origins_generator_owner_until = 0;
        level.bot_origins_generator_start_wait_until = gettime() + 1000;
        return false;
    }

    level.bot_origins_generator_start_wait_until = gettime() + 5000;
    level.bot_origins_generator_owner_until = gettime() + 180000;
    return self bot_origins_hold_generator_zone(best_zone);
}

bot_quest_origins_dig_ice_staff_parts()
{
    if(!isdefined(self.dig_vars) ||
       !isdefined(self.dig_vars["has_shovel"]) || !self.dig_vars["has_shovel"])
        return false;

    // Origins only spawns Ice Staff dig mounds while snow weather is on.
    if(!isdefined(level.weather_snow) || level.weather_snow <= 0 ||
       !isdefined(level.ice_staff_pieces) || level.ice_staff_pieces.size == 0 ||
       !isdefined(level.a_dig_spots))
        return false;

    best_spot = undefined;
    best_distance = 999999999;

    foreach(spot in level.a_dig_spots)
    {
        if(!isdefined(spot) || !isdefined(spot.origin) ||
           !isdefined(spot.str_zone) || !isdefined(spot.m_dig) ||
           !isdefined(spot.m_dig.origin))
            continue;

        if(isdefined(spot.dug) && spot.dug)
            continue;

        if(isdefined(spot.bot_origins_dig_retry_until) &&
           gettime() < spot.bot_origins_dig_retry_until)
            continue;

        if(isdefined(spot.bot_origins_dig_owner) && spot.bot_origins_dig_owner != self &&
           isdefined(spot.bot_origins_dig_owner_until) &&
           gettime() < spot.bot_origins_dig_owner_until &&
           isalive(spot.bot_origins_dig_owner))
            continue;

        // Stock dig_spot_get_staff_piece uses these same zone substrings.
        has_staff_for_zone = false;
        foreach(staff_piece in level.ice_staff_pieces)
        {
            if(isdefined(staff_piece) && isdefined(staff_piece.zone_substr) &&
               issubstr(spot.str_zone, staff_piece.zone_substr))
            {
                has_staff_for_zone = true;
                break;
            }
        }

        if(!has_staff_for_zone)
            continue;

        distance_sq = distancesquared(self.origin, spot.origin);
        if(distance_sq >= best_distance ||
           !findpath(self.origin, spot.origin, undefined, 0, 1))
            continue;

        best_spot = spot;
        best_distance = distance_sq;
    }

    if(!isdefined(best_spot))
        return false;

    best_spot.bot_origins_dig_owner = self;
    best_spot.bot_origins_dig_owner_until = gettime() + 12000;

    // The stock mound-use trigger is centered 20 units above the dig spot.
    if(distancesquared(self.origin, best_spot.origin) > 64 * 64)
    {
        arrived = self scripts\zm\zm_bo2_bots::bot_quest_move_to(
            best_spot.origin, "bot_origins_ice_staff_dig", 64, 9000);

        if(!arrived)
        {
            best_spot.bot_origins_dig_owner = undefined;
            best_spot.bot_origins_dig_owner_until = 0;
            best_spot.bot_origins_dig_retry_until = gettime() + 2500;
            return true;
        }
    }

    if(!isdefined(best_spot.m_dig) || !isdefined(best_spot.m_dig.origin) ||
       (isdefined(best_spot.dug) && best_spot.dug))
    {
        best_spot.bot_origins_dig_owner = undefined;
        best_spot.bot_origins_dig_owner_until = 0;
        return true;
    }

    self.bot.is_objective_using = 1;
    trigger_origin = best_spot.origin + (0, 0, 20);
    self lookat(trigger_origin);

    // The original waittill_dug callback picks the reward and reveals the
    // Ice Staff part, updating all stock counters and trigger state.
    for(i = 0; i < 12; i++)
    {
        if(!isalive(self) || !isdefined(best_spot.m_dig) ||
           (isdefined(best_spot.dug) && best_spot.dug))
            break;

        if(!self isonground() || self isonladder() || self ismantling())
        {
            wait 0.1;
            continue;
        }

        self pressusebutton(0.2);
        wait 0.2;
    }

    self clearlookat();
    self.bot.is_objective_using = undefined;

    if(isdefined(best_spot.dug) && best_spot.dug)
    {
        best_spot.bot_origins_dig_retry_until = undefined;
        best_spot.bot_origins_dig_owner = undefined;
        best_spot.bot_origins_dig_owner_until = 0;
    }
    else
    {
        best_spot.bot_origins_dig_owner = undefined;
        best_spot.bot_origins_dig_owner_until = 0;
        best_spot.bot_origins_dig_retry_until = gettime() + 2500;
    }

    return true;
}

bot_quest_origins_chamber_door()
{
    if(flag("chamber_entrance_opened"))
        return false;

    door_position = getstruct("chamber_entrance_position", "targetname");
    if(!isdefined(door_position) || !isdefined(door_position.has_vinyl) || !door_position.has_vinyl ||
       !isdefined(door_position.trigger) || !isdefined(door_position.trigger.origin))
        return false;

    if(isdefined(level.bot_origins_chamber_door_wait_until) &&
       gettime() < level.bot_origins_chamber_door_wait_until)
        return true;

    if(isdefined(door_position.gramophone_model) && !isdefined(level.bot_origins_chamber_door_wait_until))
    {
        // A human or another bot may have placed the record just before this
        // worker started. Give the stock six-second door animation time first.
        level.bot_origins_chamber_door_wait_until = gettime() + 8000;
        return true;
    }

    // Do not try to place the chamber record while the shared gramophone is
    // already installed on one of the Crazy Place portals.
    if(flag("gramophone_placed") && !isdefined(door_position.gramophone_model))
        return false;

    used = self scripts\zm\zm_bo2_bots::bot_quest_use_target(door_position.trigger, "bot_origins_chamber_door", 48, 1);
    if(used)
        level.bot_origins_chamber_door_wait_until = gettime() + 8000;
    return used;
}

bot_origins_point_is_in_chamber(origin)
{
    if(!isdefined(origin))
        return false;

    // Match the stock zm_tomb_chamber::is_point_in_chamber test locally.
    // The struct is absent on other maps, so return false without creating
    // an Origins-only external dependency when this shared file is loaded.
    if(!isdefined(level.s_chamber_center))
    {
        level.s_chamber_center = getstruct("chamber_center", "targetname");
        if(!isdefined(level.s_chamber_center) || !isdefined(level.s_chamber_center.script_float))
            return false;
        level.s_chamber_center.radius_sq = level.s_chamber_center.script_float * level.s_chamber_center.script_float;
    }

    return distance2dsquared(level.s_chamber_center.origin, origin) < level.s_chamber_center.radius_sq;
}

// Return the element portal index needed to reach an unfinished staff puzzle
// whose actual map target is inside the Crazy Place. Stock indices: fire=1,
// air=2, lightning=3, water/ice=4.
bot_quest_origins_required_chamber_portal()
{
    if(self hasweapon("staff_air_zm"))
    {
        if(!flag("air_puzzle_1_complete") && isdefined(level.a_ceiling_rings))
        {
            foreach(ring in level.a_ceiling_rings)
            {
                if(isdefined(ring) && isdefined(ring.origin) && self bot_origins_point_is_in_chamber(ring.origin))
                    return 2;
            }
        }

        if(!flag("air_puzzle_2_complete"))
        {
            smoke_positions = getstructarray("puzzle_smoke_origin", "targetname");
            foreach(smoke in smoke_positions)
            {
                if(isdefined(smoke) && isdefined(smoke.origin) && (!isdefined(smoke.solved) || !smoke.solved) &&
                   self bot_origins_point_is_in_chamber(smoke.origin))
                    return 2;
            }
        }
    }

    if(self hasweapon("staff_water_zm"))
    {
        if(!flag("ice_puzzle_1_complete"))
        {
            ice_gem = getent("ice_chamber_gem", "targetname");
            if(isdefined(ice_gem) && isdefined(ice_gem.origin) && self bot_origins_point_is_in_chamber(ice_gem.origin))
                return 4;

            if(isdefined(level.unsolved_tiles))
            {
                foreach(tile in level.unsolved_tiles)
                {
                    if(isdefined(tile) && isdefined(tile.origin) && self bot_origins_point_is_in_chamber(tile.origin))
                        return 4;
                }
            }
        }

        if(!flag("ice_puzzle_2_complete"))
        {
            stones = getstructarray("puzzle_stone_water", "targetname");
            foreach(stone in stones)
            {
                if(isdefined(stone) && isdefined(stone.e_model) && isdefined(stone.e_model.origin) &&
                   self bot_origins_point_is_in_chamber(stone.e_model.origin))
                    return 4;
            }
        }
    }

    if(self hasweapon("staff_lightning_zm"))
    {
        if(!flag("electric_puzzle_1_complete"))
        {
            keys = getstructarray("piano_key", "script_noteworthy");
            foreach(key in keys)
            {
                if(isdefined(key) && isdefined(key.origin) && self bot_origins_point_is_in_chamber(key.origin))
                    return 3;
            }
        }

        if(!flag("electric_puzzle_2_complete") && isdefined(level.electric_relays))
        {
            foreach(relay in level.electric_relays)
            {
                if(isdefined(relay) && isdefined(relay.trigger_stub) && isdefined(relay.trigger_stub.origin) &&
                   self bot_origins_point_is_in_chamber(relay.trigger_stub.origin))
                    return 3;
            }
        }
    }

    if(self hasweapon("staff_fire_zm"))
    {
        if(!flag("fire_puzzle_1_complete") && isdefined(level.sacrifice_volumes))
        {
            foreach(volume in level.sacrifice_volumes)
            {
                if(isdefined(volume) && isdefined(volume.origin) && self bot_origins_point_is_in_chamber(volume.origin))
                    return 1;
            }
        }

        if(!flag("fire_puzzle_2_complete"))
        {
            torches = getstructarray("church_torch_target", "script_noteworthy");
            foreach(torch in torches)
            {
                if(isdefined(torch) && isdefined(torch.origin) && self bot_origins_point_is_in_chamber(torch.origin))
                    return 1;
            }
        }
    }

    return 0;
}

// Move the single stock gramophone to the selected element's actual stargate
// position, wait for the stock portal enable flag, then use its real pad.
bot_quest_origins_enter_chamber(portal_index)
{
    if(self bot_origins_point_is_in_chamber(self.origin))
        return false;

    positions = getstructarray("stargate_gramophone_pos", "targetname");
    if(!isdefined(positions) || positions.size == 0)
        return false;

    chosen = undefined;
    if(isdefined(portal_index) && portal_index > 0)
    {
        foreach(pos in positions)
        {
            if(isdefined(pos) && isdefined(pos.script_int) && pos.script_int == portal_index)
                chosen = pos;
        }
    }
    else
    {
        foreach(pos in positions)
        {
            if(!isdefined(pos) || !isdefined(pos.script_int) || !isdefined(pos.has_vinyl) || !pos.has_vinyl)
                continue;
            if(flag("enable_teleporter_" + pos.script_int))
            {
                chosen = pos;
                break;
            }
            if(!isdefined(chosen))
                chosen = pos;
        }
    }

    if(!isdefined(chosen) || !isdefined(chosen.script_int) || !isdefined(chosen.has_vinyl) || !chosen.has_vinyl)
        return false;

    portal_index = chosen.script_int;
    if(!isdefined(level.bot_origins_gramophone_owner) || level.bot_origins_gramophone_owner == self ||
       !isalive(level.bot_origins_gramophone_owner) || !isdefined(level.bot_origins_gramophone_owner_until) ||
       gettime() >= level.bot_origins_gramophone_owner_until)
    {
        level.bot_origins_gramophone_owner = self;
        level.bot_origins_gramophone_owner_until = gettime() + 9000;
    }
    else
        return false;

    if(!flag("enable_teleporter_" + portal_index))
    {
        // A different portal (or the chamber entrance) may currently hold the
        // one shared gramophone. Pick it up using the corresponding native
        // trigger before placing it on this element's portal.
        if(flag("gramophone_placed"))
        {
            source = undefined;
            foreach(pos in positions)
                if(isdefined(pos) && isdefined(pos.gramophone_model) && isdefined(pos.origin) &&
                   isdefined(pos.script_int) && pos.script_int != portal_index)
                {
                    source = pos;
                    break;
                }

            if(!isdefined(source))
            {
                door_position = getstruct("chamber_entrance_position", "targetname");
                if(isdefined(door_position) && isdefined(door_position.gramophone_model) && isdefined(door_position.origin))
                    source = door_position;
            }

            if(isdefined(source))
            {
                point = spawnstruct();
                point.origin = source.origin;
                self scripts\zm\zm_bo2_bots::bot_quest_use_target(point, "bot_origins_gramophone_retrieve", 56, 1);
                level.bot_origins_gramophone_owner_until = gettime() + 9000;
                return true;
            }

            level.bot_origins_gramophone_owner = undefined;
            level.bot_origins_gramophone_owner_until = 0;
            return false;
        }

        if(!isdefined(chosen.gramophone_model))
        {
            point = spawnstruct();
            point.origin = chosen.origin;
            self scripts\zm\zm_bo2_bots::bot_quest_use_target(point, "bot_origins_gramophone_place", 56, 1);
            level.bot_origins_gramophone_owner_until = gettime() + 9000;
            return true;
        }

        // The native map script is still completing the portal animation.
        level.bot_origins_gramophone_owner_until = gettime() + 9000;
        return true;
    }

    pads = getstructarray("trigger_teleport_pad", "targetname");
    foreach(pad in pads)
    {
        if(!isdefined(pad) || !isdefined(pad.script_int) || pad.script_int != portal_index ||
           !isdefined(pad.trigger_stub) || !isdefined(pad.trigger_stub.origin))
            continue;

        self.bot_origins_chamber_portal_id = portal_index;
        self scripts\zm\zm_bo2_bots::bot_quest_use_target(pad.trigger_stub, "bot_origins_enter_crazy_place", 36, 2);
        level.bot_origins_gramophone_owner_until = gettime() + 9000;
        return true;
    }

    return false;
}

bot_quest_origins_exit_chamber()
{
    if(!self bot_origins_point_is_in_chamber(self.origin) || !isdefined(level.a_teleport_exit_triggers) ||
       !isdefined(level.a_teleport_exits))
        return false;

    portal_index = 0;
    if(isdefined(self.bot_origins_chamber_portal_id) && self.bot_origins_chamber_portal_id > 0)
        portal_index = self.bot_origins_chamber_portal_id;

    if(portal_index <= 0 || !isdefined(level.a_teleport_exit_triggers[portal_index]) ||
       !isdefined(level.a_teleport_exit_triggers[portal_index].trigger_stub) ||
       !isdefined(level.a_teleport_exits[portal_index]))
    {
        for(i = 1; i <= 4; i++)
        {
            if(isdefined(level.a_teleport_exit_triggers[i]) &&
               isdefined(level.a_teleport_exit_triggers[i].trigger_stub) &&
               isdefined(level.a_teleport_exits[i]))
            {
                portal_index = i;
                break;
            }
        }
    }

    if(portal_index <= 0 || !isdefined(level.a_teleport_exit_triggers[portal_index]) ||
       !isdefined(level.a_teleport_exit_triggers[portal_index].trigger_stub) ||
       !isdefined(level.a_teleport_exits[portal_index]) || !isdefined(level.a_teleport_exits[portal_index].origin))
        return false;

    exit_trigger = level.a_teleport_exit_triggers[portal_index].trigger_stub;
    exit_portal = level.a_teleport_exits[portal_index];
    self scripts\zm\zm_bo2_bots::bot_quest_use_target(exit_trigger, "bot_origins_chamber_exit_trigger", 36, 1);
    self scripts\zm\zm_bo2_bots::bot_quest_move_to(exit_portal.origin, "bot_origins_chamber_exit_portal", 90, 9000);

    deadline = gettime() + 5000;
    while(self bot_origins_point_is_in_chamber(self.origin) && gettime() < deadline && isalive(self))
        wait 0.2;

    if(!self bot_origins_point_is_in_chamber(self.origin))
        self.bot_origins_chamber_portal_id = undefined;
    return true;
}

bot_quest_origins_staff_puzzles()
{
    chamber_portal = self bot_quest_origins_required_chamber_portal();
    if(chamber_portal > 0 && !self bot_origins_point_is_in_chamber(self.origin))
    {
        self bot_quest_origins_enter_chamber(chamber_portal);
        // Yield this objective slot while another bot gathers the required
        // vinyl or the native gramophone/portal animation completes.
        return true;
    }
    if(isdefined(level.bot_origins_staff_puzzle_owner) && level.bot_origins_staff_puzzle_owner != self &&
       isdefined(level.bot_origins_staff_puzzle_owner_until) && gettime() < level.bot_origins_staff_puzzle_owner_until &&
       isalive(level.bot_origins_staff_puzzle_owner))
        return false;

    level.bot_origins_staff_puzzle_owner = self;
    level.bot_origins_staff_puzzle_owner_until = gettime() + 12000;
    did_work = false;

    // AIR 1: the ring's own script_int is the correct quadrant. Fire only the
    // required number of real Wind Staff hits; the stock ring code sets flag.
    if(!flag("air_puzzle_1_complete") && self hasweapon("staff_air_zm") && isdefined(level.a_ceiling_rings))
    {
        foreach(ring in level.a_ceiling_rings)
        {
            if(!isdefined(ring) || !isdefined(ring.origin) || !isdefined(ring.position) || !isdefined(ring.script_int))
                continue;
            turns = (ring.script_int - ring.position + 4) % 4;
            for(i = 0; i < turns && !flag("air_puzzle_1_complete"); i++)
            {
                self scripts\zm\zm_bo2_bots::bot_quest_fire_at(ring.origin, "staff_air_zm", "bot_origins_air_ring", 720, 1, 0.1);
                wait 0.22;
            }
        }
        did_work = true;
    }

    // AIR 2: direct each detector toward the destination marker. The stock
    // puzzle judges the weapon direction, not the bot's position alone.
    if(!flag("air_puzzle_2_complete") && self hasweapon("staff_air_zm"))
    {
        smoke_positions = getstructarray("puzzle_smoke_origin", "targetname");
        smoke_dest = getstruct("puzzle_smoke_dest", "targetname");
        foreach(smoke in smoke_positions)
        {
            if(!isdefined(smoke) || !isdefined(smoke.solved) || smoke.solved || !isdefined(smoke.origin) || !isdefined(smoke.detector_brush))
                continue;
            if(!isdefined(smoke_dest) || !isdefined(smoke_dest.origin) || !isdefined(smoke.detector_brush.origin))
                break;
            smoke_direction = vectornormalize(smoke_dest.origin - smoke.origin);
            shoot_origin = smoke.detector_brush.origin - vectorscale(smoke_direction, 180);
            aim_point = smoke.detector_brush.origin + vectorscale(smoke_direction, 500);
            if(distancesquared(self.origin, shoot_origin) > 150 * 150)
            {
                self scripts\zm\zm_bo2_bots::bot_quest_move_to(shoot_origin, "bot_origins_air_smoke", 105, 9000);
                did_work = true;
                break;
            }
            self.bot.is_objective_using = 1;
            self switchtoweaponimmediate("staff_air_zm");
            wait 0.2;
            attempts = 0;
            while(!smoke.solved && attempts < 16 && isalive(self))
            {
                self lookat(aim_point);
                self pressattackbutton(0.12);
                wait 0.18;
                attempts++;
            }
            self.bot.is_objective_using = undefined;
            self clearlookat();
            did_work = true;
            break;
        }
    }

    // ICE 1: expose the current ternary-gem value on the matching ceiling
    // tile. Never shoot a mismatched tile because the stock script resets all.
    if(!flag("ice_puzzle_1_complete") && self hasweapon("staff_water_zm") && isdefined(level.unsolved_tiles))
    {
        ice_gem = getent("ice_chamber_gem", "targetname");
        matching = undefined;
        if(isdefined(ice_gem) && isdefined(ice_gem.value) && ice_gem.value >= 0)
        {
            foreach(tile in level.unsolved_tiles)
            {
                if(isdefined(tile) && isdefined(tile.origin) && isdefined(tile.showing_tile_side) && tile.showing_tile_side &&
                   isdefined(tile.value) && tile.value == ice_gem.value)
                {
                    matching = tile;
                    break;
                }
            }
        }
        if(isdefined(matching))
        {
            before_count = level.unsolved_tiles.size;
            self scripts\zm\zm_bo2_bots::bot_quest_fire_at(matching.origin, "staff_water_zm", "bot_origins_ice_tile", 720, 1, 0.1);
            wait 0.35;
            if(level.unsolved_tiles.size < before_count)
                did_work = true;
        }
        else if(isdefined(ice_gem) && isdefined(ice_gem.origin))
        {
            self scripts\zm\zm_bo2_bots::bot_quest_fire_at(ice_gem.origin, "staff_water_zm", "bot_origins_ice_gem", 720, 1, 0.1);
            did_work = true;
        }
    }

    // ICE 2: freeze each stone with the Water Staff, then break it with an
    // ordinary bullet weapon. The native stone script owns the completion flag.
    if(flag("ice_puzzle_1_complete") && !flag("ice_puzzle_2_complete") && self hasweapon("staff_water_zm"))
    {
        stones = getstructarray("puzzle_stone_water", "targetname");
        foreach(stone in stones)
        {
            if(!isdefined(stone) || !isdefined(stone.origin) || !isdefined(stone.e_model) || !isdefined(stone.e_model.origin))
                continue;
            if(distancesquared(self.origin, stone.e_model.origin) > 650 * 650)
            {
                self scripts\zm\zm_bo2_bots::bot_quest_move_to(stone.e_model.origin, "bot_origins_ice_stone", 170, 9000);
                did_work = true;
                break;
            }
            self scripts\zm\zm_bo2_bots::bot_quest_fire_at(stone.e_model.origin, "staff_water_zm", "bot_origins_ice_freeze", 720, 1, 0.12);
            wait 0.35;
            primary = self bot_origins_robot_bullet_weapon();
            if(isdefined(primary) && isdefined(stone.e_model) && isdefined(stone.e_model.origin))
                self scripts\zm\zm_bo2_bots::bot_quest_fire_at(stone.e_model.origin, primary, "bot_origins_ice_shatter", 720, 7, 0.1);
            did_work = true;
            break;
        }
    }

    // ELECTRIC 1: play each of the three stock chords in the specified order.
    // Firing the keys with the Lightning Staff produces the piano_key_played events.
    if(!flag("electric_puzzle_1_complete") && self hasweapon("staff_lightning_zm"))
    {
        chord_names = array("a_minor", "e_minor", "d_minor");
        keys = getstructarray("piano_key", "script_noteworthy");
        foreach(chord_name in chord_names)
        {
            chord = getstruct("piano_chord_" + chord_name, "script_noteworthy");
            if(!isdefined(chord) || !isdefined(chord.script_string))
                continue;
            notes = strtok(chord.script_string, " ");
            if(notes.size != 3)
                continue;
            foreach(note in notes)
            {
                chosen_key = undefined;
                foreach(key in keys)
                {
                    if(isdefined(key) && isdefined(key.script_string) && key.script_string == note)
                    {
                        chosen_key = key;
                        break;
                    }
                }
                if(isdefined(chosen_key) && isdefined(chosen_key.origin))
                {
                    self scripts\zm\zm_bo2_bots::bot_quest_fire_at(chosen_key.origin, "staff_lightning_zm", "bot_origins_piano_key", 720, 1, 0.1);
                    wait 0.16;
                }
            }
            wait 4.4;
            if(flag("electric_puzzle_1_complete"))
                break;
        }
        did_work = true;
    }

    // ELECTRIC 2: route electricity through every relay in the game's actual
    // connection graph. Each use increments the live relay position by one.
    if(flag("electric_puzzle_1_complete") && !flag("electric_puzzle_2_complete"))
    {
        relays = level.electric_relays;
        if(isdefined(relays))
        {
            relay_names = array("elec", "ice", "village", "air", "start", "tank_platform", "ruins");
            desired = array(0, 3, 2, 2, 1, 0, 2);
            for(i = 0; i < relay_names.size && !flag("electric_puzzle_2_complete"); i++)
            {
                relay = relays[relay_names[i]];
                if(!isdefined(relay) || !isdefined(relay.position) || !isdefined(relay.trigger_stub) || !isdefined(relay.trigger_stub.origin))
                    continue;
                attempts = 0;
                while(relay.position != desired[i] && attempts < 4 && !flag("electric_puzzle_2_complete"))
                {
                    before_pos = relay.position;
                    self scripts\zm\zm_bo2_bots::bot_quest_use_target(relay.trigger_stub, "bot_origins_electric_relay", 28, 1);
                    wait 0.25;
                    if(relay.position == before_pos)
                        break;
                    attempts++;
                }
            }
            did_work = true;
        }
    }

    // FIRE 1: occupy every unfinished sacrifice pad. Squad combat kills in
    // the chamber are counted by the map until each stock volume is satisfied.
    if(!flag("fire_puzzle_1_complete") && self hasweapon("staff_fire_zm") && isdefined(level.sacrifice_volumes))
    {
        foreach(volume in level.sacrifice_volumes)
        {
            if(isdefined(volume) && isdefined(volume.origin) &&
               (!isdefined(volume.b_gods_pleased) || !volume.b_gods_pleased))
            {
                self scripts\zm\zm_bo2_bots::bot_quest_hold_in_volume(volume.origin, "bot_origins_fire_sacrifice", 170, 3.5);
                did_work = true;
                break;
            }
        }
    }

    // FIRE 2: ignite only correct, still-unlit church torches with the Fire
    // Staff. The stock explosion callback verifies every torch and completes it.
    if(flag("fire_puzzle_1_complete") && !flag("fire_puzzle_2_complete") && self hasweapon("staff_fire_zm"))
    {
        torches = getstructarray("church_torch_target", "script_noteworthy");
        foreach(torch in torches)
        {
            if(!isdefined(torch) || !isdefined(torch.origin) ||
               !isdefined(torch.b_correct_torch) || !torch.b_correct_torch)
                continue;

            now = gettime();
            if(isdefined(torch.bot_origins_fire_torch_retry_until) &&
               now < torch.bot_origins_fire_torch_retry_until)
                continue;

            fired = self scripts\zm\zm_bo2_bots::bot_quest_fire_at(
                torch.origin, "staff_fire_zm", "bot_origins_fire_torch", 720, 1, 0.12);

            if(fired)
            {
                // A torch's stock flame expires after 15 seconds; refresh
                // slightly before that if the puzzle has not completed.
                torch.bot_origins_fire_torch_retry_until = gettime() + 13000;
                did_work = true;
                break;
            }
        }
    }

    level.bot_origins_staff_puzzle_owner = undefined;
    level.bot_origins_staff_puzzle_owner_until = 0;

    if(self bot_origins_point_is_in_chamber(self.origin) &&
       self bot_quest_origins_required_chamber_portal() == 0)
    {
        self bot_quest_origins_exit_chamber();
        return true;
    }
    return did_work;
}

bot_quest_origins_crypt_gems()
{
    if(!isdefined(level.gem_start_pos) || !isdefined(level.a_elemental_staffs) || !flag("chamber_entrance_opened"))
        return false;

    weapon = undefined;
    gem_name = undefined;
    start_name = undefined;
    final_name = undefined;

    if(self hasweapon("staff_fire_zm"))
    {
        weapon = "staff_fire_zm";
        gem_name = "crypt_gem_fire";
        start_name = "fire_orb_exit_path";
        final_name = "fire_orb_plinth_final";
    }
    else if(self hasweapon("staff_air_zm"))
    {
        weapon = "staff_air_zm";
        gem_name = "crypt_gem_air";
        start_name = "air_orb_exit_path";
        final_name = "air_orb_plinth_final";
    }
    else if(self hasweapon("staff_water_zm"))
    {
        weapon = "staff_water_zm";
        gem_name = "crypt_gem_ice";
        start_name = "ice_orb_exit_path";
        final_name = "ice_orb_plinth_final";
    }
    else if(self hasweapon("staff_lightning_zm"))
    {
        weapon = "staff_lightning_zm";
        gem_name = "crypt_gem_elec";
        start_name = "lightning_orb_exit_path";
        final_name = "lightning_orb_plinth_final";
    }

    if(!isdefined(weapon))
        return false;

    complete_flag = "staff_";
    if(gem_name == "crypt_gem_fire")
        complete_flag = "staff_fire_zm_upgrade_unlocked";
    else if(gem_name == "crypt_gem_air")
        complete_flag = "staff_air_zm_upgrade_unlocked";
    else if(gem_name == "crypt_gem_ice")
        complete_flag = "staff_water_zm_upgrade_unlocked";
    else
        complete_flag = "staff_lightning_zm_upgrade_unlocked";

    if(flag(complete_flag))
        return false;

    if(!isdefined(level.bot_origins_crypt_owner) || !isalive(level.bot_origins_crypt_owner) ||
       !isdefined(level.bot_origins_crypt_owner_until) || gettime() > level.bot_origins_crypt_owner_until)
    {
        level.bot_origins_crypt_owner = self;
        level.bot_origins_crypt_owner_until = gettime() + 12000;
    }
    else if(level.bot_origins_crypt_owner != self)
        return false;

    main_disc = getent("crypt_puzzle_disc_main", "targetname");
    start = getstruct(start_name, "targetname");
    final_pos = getstruct(final_name, "targetname");
    if(!isdefined(main_disc) || !isdefined(main_disc.position) || !isdefined(start) || !isdefined(start.origin) ||
       !isdefined(final_pos) || !isdefined(final_pos.origin))
    {
        level.bot_origins_crypt_owner = undefined;
        level.bot_origins_crypt_owner_until = 0;
        return false;
    }

    // The stock worker does not create the orb until the original crystal is
    // hit by its matching elemental staff. Store its exact spawn point and
    // element index before the native script deletes that entity.
    if(!isdefined(level.bot_origins_crypt_gem_pos))
        level.bot_origins_crypt_gem_pos = [];
    if(!isdefined(level.bot_origins_crypt_gem_element))
        level.bot_origins_crypt_gem_element = [];

    gem = getent(gem_name, "targetname");
    if(isdefined(gem) && isdefined(gem.origin) && isdefined(gem.script_int))
    {
        level.bot_origins_crypt_gem_pos[gem_name] = final_pos.origin;
        level.bot_origins_crypt_gem_element[gem_name] = gem.script_int;
        if(distancesquared(self.origin, gem.origin) > 650 * 650)
        {
            self scripts\zm\zm_bo2_bots::bot_quest_move_to(gem.origin, "bot_origins_crypt_gem", 150, 9000);
            level.bot_origins_crypt_owner_until = gettime() + 12000;
            return true;
        }

        self scripts\zm\zm_bo2_bots::bot_quest_fire_at(gem.origin, weapon, "bot_origins_crypt_gem_shot", 720, 1, 0.12);
        level.bot_origins_crypt_owner_until = gettime() + 12000;
        return true;
    }

    // Each gem has a different disc offset. Rotate every outer disc until it
    // matches the live main-disc position plus that element's offset.
    wanted = (main_disc.position + level.gem_start_pos[gem_name]) % 4;
    discs = getentarray("crypt_puzzle_disc", "script_noteworthy");
    foreach(disc in discs)
    {
        if(!isdefined(disc) || !isdefined(disc.position) || !isdefined(disc.target))
            continue;
        if(isdefined(disc.targetname) && disc.targetname == "crypt_puzzle_disc_main")
            continue;
        if(disc.position == wanted)
            continue;

        levers = getentarray(disc.target, "targetname");
        selected_lever = undefined;
        selected_dist = 999999999;
        foreach(lever in levers)
        {
            if(!isdefined(lever) || !isdefined(lever.trigger_stub) || !isdefined(lever.trigger_stub.origin))
                continue;
            d = distancesquared(self.origin, lever.trigger_stub.origin);
            if(d < selected_dist && findpath(self.origin, lever.trigger_stub.origin, undefined, 0, 1))
            {
                selected_lever = lever;
                selected_dist = d;
            }
        }

        if(isdefined(selected_lever))
        {
            attempts = 0;
            while(disc.position != wanted && attempts < 4 && isalive(self))
            {
                // Wait for any previous lever rotation to finish. The stock
                // callback has a lever animation plus a disc movement delay.
                rotation_deadline = gettime() + 3000;
                while(flag("disc_rotation_active") && gettime() < rotation_deadline)
                    wait 0.1;

                if(flag("disc_rotation_active"))
                    break;

                before = disc.position;
                self scripts\zm\zm_bo2_bots::bot_quest_use_target(selected_lever.trigger_stub, "bot_origins_crypt_disc", 40, 1);
                wait 1.2;
                attempts++;
            }
        }
        if(disc.position != wanted)
        {
            level.bot_origins_crypt_owner = undefined;
            level.bot_origins_crypt_owner_until = 0;
            return false;
        }
    }

    // The stock orb only leaves the Crazy Place while a player looks at its
    // exit-path start for a continuous second. Do that, then fire the matching
    // elemental staff at its actual final crypt plinth.
    if(distancesquared(self.origin, start.origin) > 190 * 190)
    {
        self scripts\zm\zm_bo2_bots::bot_quest_move_to(start.origin, "bot_origins_crypt_orb_start", 150, 9000);
        level.bot_origins_crypt_owner_until = gettime() + 12000;
        return true;
    }

    self.bot.is_objective_using = 1;
    self lookat(start.origin);
    wait 1.35;
    self clearlookat();
    self.bot.is_objective_using = undefined;

    // The stock orb then traverses the crypt path and waits for the disc
    // alignment. Keep the shared puzzle lock while that state machine runs;
    // another bot rotating the same discs mid-flight would deadlock the orb.
    deadline = gettime() + 30000;
    while(!flag(complete_flag) && gettime() < deadline && isalive(self))
    {
        // The stock worker deletes the moving orb and creates a new model at
        // the final crypt plinth. Keep ownership alive while that path runs.
        level.bot_origins_crypt_owner_until = gettime() + 12000;

        if(isdefined(level.bot_origins_crypt_gem_pos[gem_name]) &&
           isdefined(level.bot_origins_crypt_gem_element[gem_name]))
        {
            orb_models = getentarray("script_model", "classname");
            foreach(orb in orb_models)
            {
                if(!isdefined(orb) || !isdefined(orb.origin) || !isdefined(orb.script_int) ||
                   orb.script_int != level.bot_origins_crypt_gem_element[gem_name])
                    continue;
                if(distancesquared(orb.origin, level.bot_origins_crypt_gem_pos[gem_name]) > 150 * 150)
                    continue;

                self scripts\zm\zm_bo2_bots::bot_quest_fire_at(orb.origin, weapon, "bot_origins_crypt_orb_charge", 720, 1, 0.12);
                break;
            }
        }
        wait 0.35;
    }

    level.bot_origins_crypt_owner = undefined;
    level.bot_origins_crypt_owner_until = 0;
    return flag(complete_flag);
}

bot_quest_origins_punch_souls()
{
    if(!self hasweapon("one_inch_punch_zm") ||
       (isdefined(self.n_ee_punch_souls) && self.n_ee_punch_souls >= 20))
        return false;

    if(!self bot_origins_point_is_in_chamber(self.origin))
    {
        self bot_quest_origins_enter_chamber(0);
        return true;
    }

    center = getstruct("chamber_center", "targetname");
    if(!isdefined(center) || !isdefined(center.origin))
        return false;

    if(!self bot_origins_point_is_in_chamber(self.origin))
    {
        self scripts\zm\zm_bo2_bots::bot_quest_move_to(center.origin, "bot_origins_punch_souls", 260, 9000);
        return true;
    }

    self set_player_melee_weapon("one_inch_punch_zm");
    zombies = getaispeciesarray(level.zombie_team, "all");
    target = undefined;
    best_distance = 999999999;
    foreach(zombie in zombies)
    {
        if(!isdefined(zombie) || !isalive(zombie) || !isdefined(zombie.origin) ||
           !is_true(zombie.has_soul) || !is_true(zombie.completed_emerging_into_playable_area) ||
           is_true(zombie.is_mechz))
            continue;
        distance_sq = distancesquared(self.origin, zombie.origin);
        if(distance_sq < best_distance && findpath(self.origin, zombie.origin, undefined, 0, 1))
        {
            best_distance = distance_sq;
            target = zombie;
        }
    }

    if(!isdefined(target))
    {
        self scripts\zm\zm_bo2_bots::bot_quest_hold_in_volume(center.origin, "bot_origins_punch_souls_wait", 300, 1.5);
        return true;
    }

    if(best_distance > 60 * 60)
    {
        self scripts\zm\zm_bo2_bots::bot_quest_move_to(target.origin, "bot_origins_punch_soul_target", 48, 5000);
        return true;
    }

    self.bot.origins_punch_last_soul_target = target.origin;

    self.bot.is_objective_using = 1;
    self lookat(target.origin + (0, 0, 24));
    self pressmelee();
    wait 0.45;
    self clearlookat();
    self.bot.is_objective_using = undefined;

    if(isdefined(self.n_ee_punch_souls) && self.n_ee_punch_souls >= 20 &&
       !isdefined(self.bot.origins_punch_tablet_hint))
        self.bot.origins_punch_tablet_hint = self.bot.origins_punch_last_soul_target;

    return true;
}

bot_quest_origins_main_steps()
{
    if(flag("ee_souls_absorbed"))
    {
        self.bot.is_origins_soul_holding = undefined;
        self cancelgoal("bot_origins_soul_chamber_hold");
    }

    // Step 3: activate a real fire-link unitrigger during the three-robot
    // round, then hit the damage target with the Beacon during its window.
    if(flag("three_robot_round") && !flag("ee_mech_zombie_hole_opened"))
    {
        if(!isdefined(level.bot_origins_firelink_next_press) ||
           gettime() >= level.bot_origins_firelink_next_press)
        {
            buttons = getentarray("fire_link_button", "targetname");
            foreach(button in buttons)
            {
                if(isdefined(button) && isdefined(button.origin))
                {
                    self scripts\zm\zm_bo2_bots::bot_quest_use_target(button, "bot_origins_fire_link", 24, 1);
                    level.bot_origins_firelink_next_press = gettime() + 6000;
                    return true;
                }
            }
        }

        if(self hasweapon("beacon_zm"))
        {
            hole = getent("fire_link_damage", "targetname");
            if(isdefined(hole) && isdefined(hole.origin))
            {
                self scripts\zm\zm_bo2_bots::bot_quest_fire_at(hole.origin, "beacon_zm", "bot_origins_fire_link_shot", 700, 1, 0.1);
                return true;
            }
        }
        return true;
    }

    // Step 5: the biplane accepts damage only from a player while Zombie Blood
    // is active. Do not waste shots before the power-up is actually running.
    if(!flag("ee_maxis_drone_retrieved") && isdefined(self.zombie_vars) &&
       isdefined(self.zombie_vars["zombie_powerup_zombie_blood_on"]) && self.zombie_vars["zombie_powerup_zombie_blood_on"])
    {
        plane = getent("zombie_blood_biplane", "targetname");
        primary = self scripts\zm\zm_bo2_bots::bot_quest_primary_weapon();
        if(isdefined(plane) && isdefined(plane.origin) && isdefined(primary))
        {
            self bot_origins_shoot_blood_plane(plane, primary);
            return true;
        }
    }

    // The Zombie Blood pilot drops the Maxis drone after the plane is destroyed.
    // The stock unitrigger pickup clears ee_quadrotor_disabled and sets the real
    // ee_maxis_drone_retrieved flag; it is a separate prerequisite for the later
    // Samantha portal sequence.
    if(!flag("ee_maxis_drone_retrieved"))
    {
        quadrotor = getent("quadrotor_pickup", "targetname");
        if(isdefined(quadrotor) && isdefined(quadrotor.origin))
        {
            self scripts\zm\zm_bo2_bots::bot_quest_use_target(quadrotor, "bot_origins_drone_pickup", 48, 4);
            return true;
        }
    }

    // Step 6: earn 20 real Crazy Place souls, then touch the tablet
    // spawned by the stock callback for this specific player.
    if(!flag("ee_all_players_upgraded_punch") &&
       (!isdefined(self.b_punch_upgraded) || !self.b_punch_upgraded))
    {
        if(!self hasweapon("one_inch_punch_zm") && !self hasweapon("one_inch_punch_upgraded_zm"))
        {
            if(!isdefined(self.one_inch_punch_flag_has_been_init))
            {
                punch_attack = bot_origins_punch_func("one_inch_punch_melee_attack");
                if(isdefined(punch_attack))
                    self thread [[ punch_attack ]]();
            }
        }

        if(self hasweapon("one_inch_punch_zm") || self hasweapon("one_inch_punch_upgraded_zm"))
        {
            if(self hasweapon("one_inch_punch_zm"))
                self set_player_melee_weapon("one_inch_punch_zm");
            else if(self hasweapon("one_inch_punch_upgraded_zm"))
                self set_player_melee_weapon("one_inch_punch_upgraded_zm");

            if(!isdefined(self.n_ee_punch_souls) || self.n_ee_punch_souls < 20)
            {
                if(self bot_quest_origins_punch_souls())
                    return true;
            }

            if(isdefined(self.n_ee_punch_souls) && self.n_ee_punch_souls >= 20)
            {
                if(!isdefined(self.bot.origins_punch_tablet_hint))
                {
                    if(isdefined(self.bot.origins_punch_last_soul_target))
                        self.bot.origins_punch_tablet_hint = self.bot.origins_punch_last_soul_target;
                    else
                        self.bot.origins_punch_tablet_hint = self.origin;
                }

                tablets = getentarray("script_model", "classname");
                best_tablet = undefined;
                best_tablet_dist = 999999999;

                foreach(tablet in tablets)
                {
                    if(!isdefined(tablet) || !isdefined(tablet.origin))
                        continue;

                    if((!isdefined(tablet.modelname) || tablet.modelname != "p6_zm_tm_tablet") &&
                       (!isdefined(tablet.model) || tablet.model != "p6_zm_tm_tablet"))
                        continue;

                    if(isdefined(tablet.owner) && tablet.owner != self)
                        continue;

                    if(isdefined(tablet.bot_origins_punch_owner) &&
                       tablet.bot_origins_punch_owner != self &&
                       isdefined(tablet.bot_origins_punch_owner_until) &&
                       gettime() < tablet.bot_origins_punch_owner_until &&
                       isalive(tablet.bot_origins_punch_owner))
                        continue;

                    // The native tablet sits 50 units above the zombie that
                    // gave this player soul number 20. Use a tight 2D match.
                    d = distance2dsquared(tablet.origin, self.bot.origins_punch_tablet_hint);
                    if(d > 80 * 80 || d >= best_tablet_dist)
                        continue;

                    best_tablet = tablet;
                    best_tablet_dist = d;
                }

                if(isdefined(best_tablet))
                {
                    best_tablet.bot_origins_punch_owner = self;
                    best_tablet.bot_origins_punch_owner_until = gettime() + 30000;
                    self.bot.origins_punch_tablet_entity = best_tablet;

                    self scripts\zm\zm_bo2_bots::bot_quest_move_to(
                        best_tablet.origin, "bot_origins_punch_tablet", 8, 12000);

                    if(is_true(self.b_punch_upgraded))
                    {
                        best_tablet.bot_origins_punch_owner = undefined;
                        best_tablet.bot_origins_punch_owner_until = 0;
                        self.bot.origins_punch_tablet_entity = undefined;
                        self.bot.origins_punch_tablet_hint = undefined;
                    }

                    return true;
                }

                // The stock tablet may spawn on the next server frame. Do not
                // advance the quest or fabricate a tablet while it appears.
                return true;
            }
        }
    }

    // Step 7: remain in the Crazy Place while squad kills count toward the
    // 100-soul portal requirement. The map callback, not the bot, increments it.
    if(flag("ee_sam_portal_active") && !flag("ee_souls_absorbed"))
    {
        if(!self bot_origins_point_is_in_chamber(self.origin))
        {
            self.bot.is_origins_soul_holding = undefined;
            self cancelgoal("bot_origins_soul_chamber_hold");
            self bot_quest_origins_enter_chamber(0);
            return true;
        }

        center = getstruct("chamber_center", "targetname");
        if(!isdefined(center) || !isdefined(center.origin))
            return true;

        // A persistent anchor keeps bots in the kill volume while the stock
        // step-7 callback counts chamber zombie deaths. Combat remains enabled.
        self.bot.is_origins_soul_holding = 1;
        if(!self hasgoal("bot_origins_soul_chamber_hold"))
            self addgoal(center.origin, 300, 1, "bot_origins_soul_chamber_hold");

        return true;
    }

    // Step 8 portal interaction is handled in bot_quest_origins().
    return false;
}

// Scripted bots cannot press the player's two-button action-slot input. Use
// the same stock quadrotor watchers as a human activation, but launch the
// vehicle directly once this bot owns the crafted drone and has a live target.

bot_origins_shoot_blood_plane(plane, weapon)
{
    if(!isdefined(plane) || !isdefined(plane.origin) ||
       !isdefined(weapon) || !self hasweapon(weapon) ||
       !isdefined(self.zombie_vars) ||
       !isdefined(self.zombie_vars["zombie_powerup_zombie_blood_on"]) ||
       !self.zombie_vars["zombie_powerup_zombie_blood_on"])
        return false;

    current_weapon = self getcurrentweapon();
    self.bot.is_objective_using = 1;
    self switchtoweaponimmediate(weapon);
    wait 0.25;

    // The plane is a moving vehicle, not a ground navigation target. Stay put
    // and refresh its live origin before every shot; stock needs one valid hit
    // while the attacking player has Zombie Blood active.
    fire_deadline = gettime() + 16000;
    while(gettime() < fire_deadline && isalive(self) &&
          !flag("ee_maxis_drone_retrieved") &&
          isdefined(plane) && isdefined(plane.origin) &&
          !plane ent_flag("biplane_down") &&
          isdefined(self.zombie_vars) &&
          isdefined(self.zombie_vars["zombie_powerup_zombie_blood_on"]) &&
          self.zombie_vars["zombie_powerup_zombie_blood_on"])
    {
        self lookat(plane.origin);
        self pressattackbutton(0.18);
        wait 0.12;
    }

    self clearlookat();
    self.bot.is_objective_using = undefined;

    if(isdefined(current_weapon) && current_weapon != "none" &&
       current_weapon != weapon && self hasweapon(current_weapon) &&
       isalive(self))
        self switchtoweaponimmediate(current_weapon);

    return true;
}

bot_origins_try_deploy_drone()
{
    if(!self hasweapon("equip_dieseldrone_zm"))
        return false;

    // Only launch while the stock quest has installed its Panzer-hole or
    // final-portal flight callback. Between these stages the drone merely
    // follows its owner and can waste the objective item.
    if(!isdefined(level.quadrotor_custom_behavior))
        return false;

    if(!isdefined(self.bot) || !isdefined(self.bot.threat) ||
       !isdefined(self.bot.threat.entity) || !isalive(self.bot.threat.entity))
        return false;

    if(!self isonground() || self isonladder() || self ismantling() ||
       self isreloading() || self isswitchingweapons() || self isthrowinggrenade())
        return false;

    if(isdefined(level.maxis_quadrotor) && isalive(level.maxis_quadrotor))
        return false;

    existing_drones = getentarray("quadrotor_ai", "targetname");
    if(isdefined(existing_drones) && existing_drones.size > 0)
        return false;

    if(flag("quadrotor_cooling_down"))
        return false;

    if(isdefined(self.bot.origins_drone_deploy_after) &&
       gettime() < self.bot.origins_drone_deploy_after)
        return false;

    drone_death_watcher = getfunction("maps/mp/zm_tomb_craftables", "quadrotor_death_watcher");
    drone_instance_watcher = getfunction("maps/mp/zm_tomb_craftables", "quadrotor_instance_watcher");
    if(!isdefined(drone_death_watcher) || !isdefined(drone_instance_watcher))
        return false;

    drone_weapon = "equip_dieseldrone_zm";
    weapons = self getweaponslistprimaries();
    switch_weapon = undefined;

    foreach(weapon in weapons)
    {
        if(weapon != drone_weapon)
        {
            switch_weapon = weapon;
            break;
        }
    }

    // Keep a real firearm equipped before consuming the action-slot drone.
    if(!isdefined(switch_weapon))
        return false;

    self switchtoweapon(switch_weapon);
    switch_deadline = gettime() + 2000;
    while(self isswitchingweapons() && gettime() < switch_deadline)
        wait 0.05;

    if(!self hasweapon(drone_weapon))
        return false;

    self playsound("veh_qrdrone_takeoff");
    self takeweapon(drone_weapon);
    self setactionslot(2, "");

    vehicle_name = "heli_quadrotor_zm";
    if(flag("ee_maxis_drone_retrieved"))
        vehicle_name = "heli_quadrotor_upgraded_zm";

    drone = spawnvehicle(
        "veh_t6_dlc_zm_quadrotor",
        "quadrotor_ai",
        vehicle_name,
        self.origin + vectorscale((0, 0, 1), 96.0),
        self.angles
    );

    if(!isdefined(drone))
    {
        self giveweapon(drone_weapon);
        self setweaponammoclip(drone_weapon, 1);
        self setactionslot(2, "weapon", drone_weapon);
        return false;
    }

    level thread [[ drone_death_watcher ]](drone);
    drone thread [[ drone_instance_watcher ]](self);
    self.bot.origins_drone_deploy_after = gettime() + 15000;
    return true;
}


// -----------------------------------------------------------------------------
// Origins robot Wind Staff parts: shoot the live hatch sole, then stand on the
// stock footprint and let the native stomp trigger teleport the bot inside.
// -----------------------------------------------------------------------------
bot_origins_robot_bullet_weapon()
{
    weapons = self getweaponslistprimaries();
    foreach(weapon in weapons)
    {
        if(!isdefined(weapon) || weapon == "none")
            continue;

        // The sole needs ordinary bullet damage; the Ray Guns and BOOMHILDA do
        // not open it.
        if(issubstr(weapon, "staff_") || issubstr(weapon, "ray") ||
           issubstr(weapon, "boomhilda") || issubstr(weapon, "mauser_upgraded") ||
           issubstr(weapon, "mauser_zm_upgraded") || issubstr(weapon, "crossbow_explosive") ||
           issubstr(weapon, "rpg") || issubstr(weapon, "m32") ||
           issubstr(weapon, "china_lake") || issubstr(weapon, "ballistic") ||
           weapon == "jetgun_zm" || weapon == "slipgun_zm")
            continue;

        if(self getweaponammoclip(weapon) + self getweaponammostock(weapon) <= 0)
            continue;

        return weapon;
    }
    return undefined;
}

bot_origins_robot_footprint(robot)
{
    if(!isdefined(robot) || !isdefined(robot.giant_robot_id) ||
       !isdefined(robot.hatch_foot))
        return undefined;

    if(robot.hatch_foot == "left")
        foot_tag = "TAG_ATTACH_HATCH_LE";
    else if(robot.hatch_foot == "right")
        foot_tag = "TAG_ATTACH_HATCH_RI";
    else
        return undefined;

    foot_origin = robot gettagorigin(foot_tag);
    if(!isdefined(foot_origin))
        return undefined;

    footprints = getstructarray("giant_robot_footprint_center", "targetname");
    if(!isdefined(footprints) || footprints.size == 0)
        return undefined;

    nearest = undefined;
    nearest_dist = 999999999;

    foreach(footprint in footprints)
    {
        if(!isdefined(footprint) || !isdefined(footprint.origin) ||
           !isdefined(footprint.script_int) ||
           footprint.script_int != robot.giant_robot_id)
            continue;

        if(isdefined(footprint.bot_origins_wind_owner) &&
           footprint.bot_origins_wind_owner != self &&
           isdefined(footprint.bot_origins_wind_owner_until) &&
           gettime() < footprint.bot_origins_wind_owner_until &&
           isalive(footprint.bot_origins_wind_owner))
            continue;

        distance = distancesquared(foot_origin, footprint.origin);
        if(distance < nearest_dist)
        {
            nearest = footprint;
            nearest_dist = distance;
        }
    }

    return nearest;
}

bot_origins_release_robot_wind_claim(robot, footprint, reserve)
{
    if(!isdefined(robot))
        return;

    if(isdefined(reserve) && reserve)
    {
        robot.bot_origins_wind_owner = self;
        robot.bot_origins_wind_owner_until = gettime() + 30000;

        if(isdefined(footprint))
        {
            footprint.bot_origins_wind_owner = self;
            footprint.bot_origins_wind_owner_until = gettime() + 30000;
        }
        return;
    }

    if(isdefined(robot.bot_origins_wind_owner) && robot.bot_origins_wind_owner == self)
    {
        robot.bot_origins_wind_owner = undefined;
        robot.bot_origins_wind_owner_until = 0;
    }

    if(isdefined(footprint) && isdefined(footprint.bot_origins_wind_owner) &&
       footprint.bot_origins_wind_owner == self)
    {
        footprint.bot_origins_wind_owner = undefined;
        footprint.bot_origins_wind_owner_until = 0;
    }
}

bot_quest_origins_robot_wind_parts()
{
    if(!isdefined(level.staff_part_count) ||
       !isdefined(level.staff_part_count["elemental_staff_air"]) ||
       level.staff_part_count["elemental_staff_air"] <= 0)
        return false;

    // The stock head pickup/craftable worker owns collection after teleport.
    if(isdefined(self.in_giant_robot_head))
        return true;

    if(isdefined(self.bot.origins_wind_robot_retry_after) &&
       gettime() < self.bot.origins_wind_robot_retry_after)
        return false;

    if(!isdefined(level.a_giant_robots) || level.a_giant_robots.size == 0 ||
       !isdefined(level.gr_foot_hatch_closed))
        return false;

    best_robot = undefined;
    best_footprint = undefined;
    best_stage_origin = undefined;
    best_dist_sq = 999999999;

    for(robot_index = 0; robot_index < level.a_giant_robots.size; robot_index++)
    {
        robot = level.a_giant_robots[robot_index];

        if(!isdefined(robot) || !isdefined(robot.giant_robot_id) ||
           !isdefined(robot.is_walking) || !robot.is_walking ||
           !isdefined(robot.b_has_hatch) || !robot.b_has_hatch ||
           !isdefined(robot.hatch_foot))
            continue;

        robot_id = robot.giant_robot_id;

        // isdefined(false) is still true in GSC. Explicitly require a CLOSED
        // hatch, otherwise bots waste the walk cycle on an already-open foot.
        if(!isdefined(level.gr_foot_hatch_closed[robot_id]) ||
           !level.gr_foot_hatch_closed[robot_id])
            continue;

        if(robot.hatch_foot != "left" && robot.hatch_foot != "right")
            continue;

        if(isdefined(robot.bot_origins_wind_owner) &&
           robot.bot_origins_wind_owner != self &&
           isdefined(robot.bot_origins_wind_owner_until) &&
           gettime() < robot.bot_origins_wind_owner_until &&
           isalive(robot.bot_origins_wind_owner))
            continue;

        footprint = self bot_origins_robot_footprint(robot);
        if(!isdefined(footprint) || !isdefined(footprint.origin))
            continue;

        // Keep the bot outside the stomp footprint. The previous 128-180 unit
        // offsets could place it inside the robot's kill trigger while it
        // approached the sole.
        offsets = [];
        offsets[0] = (360, 0, 0);
        offsets[1] = (-360, 0, 0);
        offsets[2] = (0, 360, 0);
        offsets[3] = (0, -360, 0);
        offsets[4] = (255, 255, 0);
        offsets[5] = (255, -255, 0);
        offsets[6] = (-255, 255, 0);
        offsets[7] = (-255, -255, 0);

        for(offset_index = 0; offset_index < offsets.size; offset_index++)
        {
            stage_origin = footprint.origin + offsets[offset_index];
            if(!findpath(self.origin, stage_origin, undefined, 0, 1))
                continue;

            stage_dist = distancesquared(self.origin, stage_origin);
            if(stage_dist < best_dist_sq)
            {
                best_robot = robot;
                best_footprint = footprint;
                best_stage_origin = stage_origin;
                best_dist_sq = stage_dist;
            }
        }
    }

    if(!isdefined(best_robot) || !isdefined(best_footprint) ||
       !isdefined(best_stage_origin))
        return false;

    robot_id = best_robot.giant_robot_id;

    if(isdefined(best_robot.bot_origins_wind_owner) &&
       best_robot.bot_origins_wind_owner != self &&
       isdefined(best_robot.bot_origins_wind_owner_until) &&
       gettime() < best_robot.bot_origins_wind_owner_until &&
       isalive(best_robot.bot_origins_wind_owner))
        return false;

    self bot_origins_release_robot_wind_claim(best_robot, best_footprint, 1);
    self.bot.is_objective_using = 1;

    arrived = self scripts\zm\zm_bo2_bots::bot_quest_move_to(
        best_stage_origin, "bot_origins_robot_stage", 40, 9000);

    entered = false;
    original_weapon = self getcurrentweapon();

    if(arrived && isalive(self) && !isdefined(self.in_giant_robot_head) &&
       isdefined(best_robot.is_walking) && best_robot.is_walking &&
       isdefined(level.gr_foot_hatch_closed[robot_id]) &&
       level.gr_foot_hatch_closed[robot_id])
    {
        sole = getent("target_sole_" + robot_id, "targetname");

        // Shoot the live sole attached to hatch_foot (left/right), never the
        // opposite foot or the robot body.
        if(isdefined(sole) && isdefined(sole.origin))
        {
            bullet_weapon = self bot_origins_robot_bullet_weapon();

            if(isdefined(bullet_weapon))
            {
                self switchtoweaponimmediate(bullet_weapon);
                wait 0.35;

                fire_deadline = gettime() + 22000;
                while(gettime() < fire_deadline &&
                      isdefined(level.gr_foot_hatch_closed[robot_id]) &&
                      level.gr_foot_hatch_closed[robot_id] &&
                      isdefined(sole) && isdefined(sole.origin) &&
                      isdefined(best_robot.is_walking) && best_robot.is_walking &&
                      !isdefined(self.in_giant_robot_head) &&
                      self scripts\zm\zm_bo2_bots::bot_objective_can_run())
                {
                    // If the active foot closes in on the bot, stop firing and
                    // back out before the next stomp instead of standing under it.
                    current_footprint = self bot_origins_robot_footprint(best_robot);
                    if(isdefined(current_footprint) &&
                       distancesquared(self.origin, current_footprint.origin) < 280 * 280)
                    {
                        retreat_dir = vectornormalize(self.origin - current_footprint.origin);
                        retreat_origin = current_footprint.origin + vectorscale(retreat_dir, 400);
                        self clearlookat();
                        self cancelgoal("bot_origins_robot_stage");
                        self scripts\zm\zm_bo2_bots::bot_quest_move_to(
                            retreat_origin, "bot_origins_robot_retreat", 48, 4500);
                        break;
                    }

                    self lookat(sole.origin);
                    self pressattackbutton(0.12);
                    wait 0.16;
                }
            }
        }

        self clearlookat();

        // Enter through the actual matching stock foot trigger. A generic
        // footprint-center goal can land beside the trigger and never teleport.
        if(isdefined(level.gr_foot_hatch_closed[robot_id]) &&
           !level.gr_foot_hatch_closed[robot_id] &&
           !isdefined(self.in_giant_robot_head) &&
           isdefined(best_robot.hatch_foot))
        {
            entry_trigger = getent(
                "trig_stomp_kill_" + best_robot.hatch_foot + "_" + robot_id,
                "targetname");

            if(isdefined(entry_trigger) && isdefined(entry_trigger.origin))
            {
                entry_deadline = gettime() + 18000;
                next_goal_refresh = 0;

                while(gettime() < entry_deadline && isalive(self) &&
                      !isdefined(self.in_giant_robot_head))
                {
                    if(isdefined(self.in_giant_robot_head) &&
                       self.in_giant_robot_head == robot_id)
                    {
                        entered = true;
                        break;
                    }

                    if(!isdefined(best_robot.is_walking) || !best_robot.is_walking ||
                       !isdefined(level.gr_foot_hatch_closed[robot_id]) ||
                       level.gr_foot_hatch_closed[robot_id])
                        break;

                    // The trigger is linked to the moving foot. Refresh the
                    // goal so the bot follows its current position, not an old
                    // footprint coordinate from before the hatch opened.
                    if(gettime() >= next_goal_refresh &&
                       isdefined(entry_trigger.origin))
                    {
                        self cancelgoal("bot_origins_robot_enter");
                        self addgoal(entry_trigger.origin, 8, 2, "bot_origins_robot_enter");
                        next_goal_refresh = gettime() + 350;
                    }

                    wait 0.1;
                }

                self cancelgoal("bot_origins_robot_enter");
            }
        }
    }

    self clearlookat();
    self cancelgoal("bot_origins_robot_stage");
    self cancelgoal("bot_origins_robot_retreat");
    self.bot.is_objective_using = undefined;

    if(isdefined(original_weapon) && original_weapon != "none" &&
       self hasweapon(original_weapon) && isalive(self) &&
       self getcurrentweapon() != original_weapon)
        self switchtoweaponimmediate(original_weapon);

    if(entered || (isdefined(self.in_giant_robot_head) &&
                   self.in_giant_robot_head == robot_id))
    {
        // Hold the claim through the native in-head part pickup/eject sequence.
        self bot_origins_release_robot_wind_claim(best_robot, best_footprint, 1);
        self.bot.origins_wind_robot_retry_after = gettime() + 30000;
        return true;
    }

    self bot_origins_release_robot_wind_claim(best_robot, best_footprint, 0);
    self.bot.origins_wind_robot_retry_after = gettime() + 2500;
    return false;
}

bot_quest_origins()
{
    // Hard runtime gate: never run Origins objectives on TranZit or any other map.
    if(getdvar("mapname") != "zm_tomb")
        return;

    if(isdefined(self.in_giant_robot_head))
        return;

    if(flag("ee_souls_absorbed"))
    {
        self.bot.is_origins_soul_holding = undefined;
        self cancelgoal("bot_origins_soul_chamber_hold");
    }

    // The chamber soul step owns this bot's movement until the native count
    // completes; do not start individual errands while the bot is anchored.
    if(is_true(self.bot.is_origins_soul_holding))
    {
        self bot_quest_origins_main_steps();
        if(is_true(self.bot.is_origins_soul_holding))
            return;
    }

    // Deploy the assembled Maxis drone during combat. Stock quadrotor watchers
    // retain control of its AI, cooldown and return/death lifecycle.
    if(self bot_origins_try_deploy_drone())
        return;

    // An active generator capture is the squad's highest-priority objective.
    // Reinforce it before individual shovel, dig, or staff errands can pull
    // otherwise-idle bots away from the capture volume.
    if(flag("zone_capture_in_progress") && self bot_quest_origins_generators())
        return;

    // Opening priorities when no generator capture is active.
    if(self bot_quest_origins_shovel())
        return;
    if(self bot_quest_origins_generators())
        return;
    if(self bot_quest_origins_dig_ice_staff_parts())
        return;
    if(self bot_quest_origins_robot_wind_parts())
        return;
    if(self bot_quest_origins_chamber_door())
        return;
    if(self bot_quest_origins_staff_puzzles())
        return;
    if(self bot_quest_origins_crypt_gems())
        return;

    // Insert carried elemental staffs into their native charge triggers. Stock
    // quest code counts the nearby zombie kills and creates the upgraded pickup.
    if(isdefined(level.a_elemental_staffs))
    {
        foreach(staff in level.a_elemental_staffs)
        {
            if(!isdefined(staff) || !isdefined(staff.weapname) || !self hasweapon(staff.weapname))
                continue;

            if(isdefined(staff.charger) && isdefined(staff.charger.is_inserted) && staff.charger.is_inserted)
                continue;

            if(isdefined(staff.charge_trigger) && isdefined(staff.charge_trigger.origin))
            {
                self scripts\zm\zm_bo2_bots::bot_quest_use_target(staff.charge_trigger, "bot_origins_staff_charge", 48, 4);
                return;
            }
        }
    }

    // Recover upgraded staffs once their stock pickup trigger is enabled.
    if(isdefined(level.a_elemental_staffs_upgraded))
    {
        foreach(staff_upgraded in level.a_elemental_staffs_upgraded)
        {
            if(!isdefined(staff_upgraded) || !isdefined(staff_upgraded.weapname) ||
               self hasweapon(staff_upgraded.weapname))
                continue;

            if(isdefined(staff_upgraded.trigger) && isdefined(staff_upgraded.trigger.origin))
            {
                self scripts\zm\zm_bo2_bots::bot_quest_use_target(staff_upgraded.trigger, "bot_origins_staff_pickup", 40, 4);
                return;
            }
        }
    }

    // Step two of Little Lost Girl: put each upgraded staff into its matching
    // robot-head plinth. The stock trigger checks the actual weapon name.
    if(flag("ee_all_staffs_upgraded") && !flag("ee_all_staffs_placed"))
    {
        head_stubs = getstructarray("robot_head_staff", "targetname");
        foreach(head in head_stubs)
        {
            if(!isdefined(head) || !isdefined(head.script_noteworthy) || !isdefined(head.m_plinth))
                continue;

            weapon_name = "staff_" + head.script_noteworthy + "_upgraded_zm";
            if(self hasweapon(weapon_name) &&
               (!isdefined(head.m_plinth.m_staff) || !isdefined(head.m_plinth.m_staff.origin)))
            {
                self scripts\zm\zm_bo2_bots::bot_quest_use_target(head, "bot_origins_staff_plinth", 40, 5);
                return;
            }
        }
    }

    if(self bot_quest_origins_main_steps())
        return;

    // Last step: use the real portal trigger once the map has activated it.
    if(flag("ee_souls_absorbed") && flag("ee_quadrotor_disabled") && !flag("ee_samantha_released"))
    {
        if(!self bot_origins_point_is_in_chamber(self.origin))
        {
            self bot_quest_origins_enter_chamber(0);
            return;
        }
        final_portal = getstruct("player_portal_final", "targetname");
        if(isdefined(final_portal) && isdefined(final_portal.origin))
        {
            point = spawnstruct();
            point.origin = final_portal.origin;
            self scripts\zm\zm_bo2_bots::bot_quest_use_target(point, "bot_origins_final_portal", 80, 5);
        }
    }
}
bot_origins_grant_shield(current_weapon)
{
	self scripts\zm\zm_bo2_bots::bot_grant_map_shield("tomb_shield_zm", current_weapon);
}
