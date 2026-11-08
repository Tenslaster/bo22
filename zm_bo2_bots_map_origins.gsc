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
    while(isalive(self) && gettime() < hold_deadline &&
          !zone ent_flag("player_controlled") &&
          (flag("zone_capture_in_progress") || zone ent_flag("zone_contested")))
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
       !isdefined(level.zone_capture.zones) || flag("all_zones_captured"))
        return false;

    // Once a generator is active, every bot should help hold its capture area.
    if(flag("zone_capture_in_progress"))
    {
        active_zone = undefined;

        if(isdefined(level.bot_origins_generator_target) &&
           isdefined(level.bot_origins_generator_target.origin) &&
           !level.bot_origins_generator_target ent_flag("player_controlled"))
            active_zone = level.bot_origins_generator_target;

        if(!isdefined(active_zone))
        {
            zone_keys = getarraykeys(level.zone_capture.zones);
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
            self bot_origins_hold_generator_zone(active_zone);

        return true;
    }

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

    // Ask the stock map function for its real cost instead of maintaining a
    // duplicate formula. The stock cost is 200 times the current player count.
    get_cost_func = getfunction("maps/mp/zm_tomb_capture_zones", "get_generator_capture_start_cost");
    if(isdefined(get_cost_func))
        cost = [[ get_cost_func ]]();
    else
        cost = 200 * get_players().size;

    if(!isdefined(self.score) || self.score < cost)
        return false;

    best_zone = undefined;
    best_distance = 999999999;
    zone_keys = getarraykeys(level.zone_capture.zones);

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

    // The generator's stock unitrigger is a 128-unit box centered on the zone
    // origin. The stock unitrigger callback rejects scripted test clients via
    // is_player_valid(), so do not wait for its per-player trigger thread.
    // Move inside that box and dispatch the zone's native capture event below.
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

    // This is the exact event consumed by the stock wait_for_capture_trigger()
    // thread. It still deducts the proper price, starts the zombies, and runs
    // the native capture / ownership state machine.
    if(!flag("zone_capture_in_progress") &&
       !best_zone ent_flag("zone_contested") &&
       !best_zone ent_flag("player_controlled"))
        best_zone notify("start_generator_capture", self);

    self clearlookat();
    self.bot.is_objective_using = undefined;

    // The stock event sets this flag as soon as its listener receives the
    // notification. Give the listener a short window before releasing the lock.
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

    // Keep the activating bot in the stock capture volume until ownership flips.
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
            primary = self scripts\zm\zm_bo2_bots::bot_quest_primary_weapon();
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
            if(isdefined(torch) && isdefined(torch.origin) && isdefined(torch.b_correct_torch) && torch.b_correct_torch &&
               !isdefined(torch.e_fx))
            {
                self scripts\zm\zm_bo2_bots::bot_quest_fire_at(torch.origin, "staff_fire_zm", "bot_origins_fire_torch", 720, 1, 0.12);
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
        level.bot_origins_crypt_gem_pos[gem_name] = gem.origin;
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
                before = disc.position;
                self scripts\zm\zm_bo2_bots::bot_quest_use_target(selected_lever.trigger_stub, "bot_origins_crypt_disc", 40, 1);
                wait 0.3;
                if(disc.position == before)
                    break;
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
        // Once the aligned orb has descended onto its original chamber plinth,
        // the stock gem worker waits for damage from the matching staff. Find
        // that native orb by the saved position + element index and hit it.
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

    self.bot.is_objective_using = 1;
    self lookat(target.origin + (0, 0, 24));
    self pressmelee();
    wait 0.45;
    self clearlookat();
    self.bot.is_objective_using = undefined;
    return true;
}

bot_quest_origins_main_steps()
{
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
            self scripts\zm\zm_bo2_bots::bot_quest_fire_at(plane.origin, primary, "bot_origins_blood_plane", 1500, 10, 0.1);
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

    // Step 6: initialize the stock One Inch Punch melee system, collect 20
    // Crazy Place souls, and physically touch the player-specific tablet.
    if(!flag("ee_all_players_upgraded_punch"))
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

            // The stock quest requires a tablet pickup for every player,
            // including the local host. Once this bot earns the real 20-soul
            // tablet, spawn the same stock pickup for any remaining teammates
            // at their current positions; the original callback marks each
            // player upgraded and sets ee_all_players_upgraded_punch itself.
            if(isdefined(self.n_ee_punch_souls) && self.n_ee_punch_souls >= 20 &&
               !is_true(level.bot_origins_punch_tablets_given))
            {
                level.bot_origins_punch_tablets_given = 1;
                all_players = get_players();
                foreach(punch_player in all_players)
                {
                    if(!isdefined(punch_player) || punch_player == self ||
                       (isdefined(punch_player.b_punch_upgraded) && punch_player.b_punch_upgraded))
                        continue;
                    level thread bot_origins_spawn_punch_upgrade_tablet(punch_player.origin, punch_player);
                }
            }

            tablets = getentarray("script_model", "classname");
            foreach(tablet in tablets)
            {
                if(!isdefined(tablet) || !isdefined(tablet.origin))
                    continue;
                if((!isdefined(tablet.modelname) || tablet.modelname != "p6_zm_tm_tablet") &&
                   (!isdefined(tablet.model) || tablet.model != "p6_zm_tm_tablet"))
                    continue;
                if(isdefined(tablet.owner) && tablet.owner != self)
                    continue;
                if(isdefined(self.n_ee_punch_souls) && self.n_ee_punch_souls >= 20)
                {
                    self scripts\zm\zm_bo2_bots::bot_quest_move_to(tablet.origin, "bot_origins_punch_tablet", 32, 10000);
                    return true;
                }
            }
        }
    }

    // Step 7: remain in the Crazy Place while squad kills count toward the
    // 100-soul portal requirement. The map callback, not the bot, increments it.
    if(flag("ee_sam_portal_active") && !flag("ee_souls_absorbed"))
    {
        if(!self bot_origins_point_is_in_chamber(self.origin))
        {
            self bot_quest_origins_enter_chamber(0);
            return true;
        }
        center = getstruct("chamber_center", "targetname");
        if(isdefined(center) && isdefined(center.origin))
            self scripts\zm\zm_bo2_bots::bot_quest_hold_in_volume(center.origin, "bot_origins_soul_chamber", 340, 4.0);
        return true;
    }

    // Step 8 portal interaction is handled in bot_quest_origins().
    return false;
}

bot_quest_origins()
{
    // Hard runtime gate: never run Origins objectives on TranZit or any other map.
    if(getdvar("mapname") != "zm_tomb")
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

// Local equivalent of the stock Origins punch-tablet pickup. Keeping this
// implementation here avoids linking the Origins-only zm_tomb_ee_main_step_6
// module while the shared bot scripts are loaded on maps such as TranZit.
bot_origins_spawn_punch_upgrade_tablet(v_origin, e_player)
{
    m_tablet = spawn("script_model", v_origin + vectorscale((0, 0, 1), 50.0));
    m_tablet setmodel("p6_zm_tm_tablet");
    m_fx = spawn("script_model", m_tablet.origin);
    m_fx setmodel("tag_origin");
    m_fx setinvisibletoall();
    m_fx setvisibletoplayer(e_player);
    m_tablet linkto(m_fx);
    playfxontag(level._effect["special_glow"], m_fx, "tag_origin");
    m_fx thread bot_origins_rotate_punch_upgrade_tablet();
    m_tablet playloopsound("zmb_squest_punchtime_tablet_loop", 0.5);
    m_tablet setinvisibletoall();
    m_tablet setvisibletoplayer(e_player);

    while(isdefined(e_player) && !e_player istouching(m_tablet))
        wait 0.05;

    m_tablet delete();
    m_fx delete();
    e_player playsound("zmb_squest_punchtime_tablet_pickup");

    if(isdefined(e_player))
    {
        e_player thread [[ maps\mp\gametypes_zm\_hud::fadetoblackforxsec ]](0, 0.3, 0.5, 0.5, "white");
        a_zombies = getaispeciesarray(level.zombie_team, "all");
        knockdown_func = bot_origins_punch_func("knockdown_zombie_animate");

        foreach(zombie in a_zombies)
        {
            if(isdefined(knockdown_func) && distance2dsquared(e_player.origin, zombie.origin) < 65536 &&
               !is_true(zombie.is_mechz) && is_true(zombie.has_legs) &&
               is_true(zombie.completed_emerging_into_playable_area))
            {
                zombie.v_punched_from = e_player.origin;
                zombie animcustom(knockdown_func);
            }
        }

        wait 1;
        e_player.b_punch_upgraded = 1;

        if(e_player hasweapon("staff_fire_upgraded_zm"))
            e_player.str_punch_element = "fire";
        else if(e_player hasweapon("staff_air_upgraded_zm"))
            e_player.str_punch_element = "air";
        else if(e_player hasweapon("staff_lightning_upgraded_zm"))
            e_player.str_punch_element = "lightning";
        else if(e_player hasweapon("staff_water_upgraded_zm"))
            e_player.str_punch_element = "ice";
        else
            e_player.str_punch_element = "upgraded";

        punch_attack = bot_origins_punch_func("one_inch_punch_melee_attack");
        if(isdefined(punch_attack))
            e_player thread [[ punch_attack ]]();
        a_players = getplayers();

        foreach(player in a_players)
        {
            if(!isdefined(player.b_punch_upgraded) || !player.b_punch_upgraded)
                return;
        }

        flag_set("ee_all_players_upgraded_punch");
    }
}

bot_origins_rotate_punch_upgrade_tablet()
{
    self endon("death");

    while(true)
    {
        self rotateyaw(360, 5);
        self waittill("rotatedone");
    }
}

